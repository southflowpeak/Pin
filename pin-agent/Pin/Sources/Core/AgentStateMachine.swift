import Foundation
import AppKit
import ScreenCaptureKit

/// State machine for the Agent application
/// Manages transitions between Idle, Mirroring, MirrorHidden, and Error states
@MainActor
final class AgentStateMachine {

    private(set) var currentState: AgentState = .idle
    private(set) var targetInfo: TargetWindowInfo?
    private(set) var pinnedSince: Date?

    private var windowCaptureManager: WindowCaptureManager?
    private var mirrorWindowController: MirrorWindowController?

    // Monitoring
    private var frontmostAppObserver: Any?
    private var windowExistenceTimer: Timer?
    private let targetWindowDetector = TargetWindowDetector()

    // Timestamp when mirror was hidden (to suppress immediate showMirror)
    private var mirrorHiddenAt: Date?
    private let showMirrorDelay: TimeInterval = 0.5

    // UserDefaults keys
    private static let opacityKey = "mirrorOpacity"

    /// Saved opacity value from UserDefaults (defaults to 1.0)
    private var savedOpacity: Float {
        get {
            let value = UserDefaults.standard.float(forKey: Self.opacityKey)
            // If not set (returns 0), default to 1.0
            return value > 0 ? value : 1.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.opacityKey)
        }
    }

    init() {
        setupFrontmostAppObserver()
    }

    /// Clean up resources - call before releasing the state machine
    func shutdown() {
        removeFrontmostAppObserver()
        stopWindowExistenceMonitoring()
        cleanup()
    }

    // MARK: - Public Commands

    /// Pin the currently active window
    func pinActiveWindow() async throws {
        // すでにpinされている場合はunpinしてからpinする
        if currentState == .mirroring || currentState == .mirrorHidden {
            unpin()
        }

        guard currentState == .idle else {
            throw AgentError.invalidStateTransition(from: currentState, to: .mirroring)
        }

        // Get frontmost window info
        let detector = TargetWindowDetector()
        guard let target = await detector.detectFrontmostWindow() else {
            throw AgentError.noTargetWindow
        }

        try await pinWindow(target)
    }

    /// Pin a specific window
    func pinWindow(_ target: TargetWindowInfo) async throws {
        // すでにpinされている場合はunpinしてからpinする
        if currentState == .mirroring || currentState == .mirrorHidden {
            unpin()
        }

        guard currentState == .idle else {
            throw AgentError.invalidStateTransition(from: currentState, to: .mirroring)
        }

        targetInfo = target
        pinnedSince = Date()

        // Get SCShareableContent to find SCWindow and SCDisplay
        let content = try await SCShareableContent.current
        guard let scWindow = content.windows.first(where: { $0.windowID == target.windowID }) else {
            throw AgentError.captureFailure("Target window not found in shareable content")
        }

        // Find the display that contains the target window
        let scDisplay = content.displays.first { display in
            target.bounds.intersects(display.frame)
        }

        // Create capture manager
        let captureManager = WindowCaptureManager()
        self.windowCaptureManager = captureManager

        // Create mirror window controller with the capture manager
        let mirrorController = MirrorWindowController(targetInfo: target, captureManager: captureManager)
        self.mirrorWindowController = mirrorController

        // Handle hover events (based on Topit's onHover behavior)
        // Note: We don't change state here, just toggle visibility
        // This prevents the hover loop issue
        mirrorController.onHoverChanged = { [weak self] isHovering in
            guard let self = self, self.currentState == .mirroring else { return }
            if isHovering {
                // Mouse entered mirror window - make transparent and show original
                self.mirrorWindowController?.hideMirror()
            } else {
                // Mouse exited mirror window - make visible again
                self.mirrorWindowController?.unhideMirror()
            }
        }
        mirrorController.onGeometryChange = { [weak self] newSize in
            guard let self = self else { return }
            // Use the screen where the mirror window is displayed, not NSScreen.main
            // This ensures correct scaling when moving between Retina and non-Retina screens
            let screen = self.mirrorWindowController?.currentScreen
            self.windowCaptureManager?.updateStreamSize(
                newWidth: newSize.width,
                newHeight: newSize.height,
                screen: screen
            )
        }
        mirrorController.onUnpin = { [weak self] in
            self?.unpin()
        }

        // Apply saved opacity
        mirrorController.setOpacity(savedOpacity)

        // Show mirror window first
        mirrorController.showMirror()

        // Start capture
        await captureManager.startCapture(display: scDisplay, window: scWindow)

        // Attach video layer after capture starts
        mirrorController.attachVideoLayer()

        // Start monitoring for window existence
        startWindowExistenceMonitoring()

        currentState = .mirroring
    }

    /// Unpin the current target
    func unpin() {
        cleanup()
        currentState = .idle
    }

    /// Emergency panic unpin - guaranteed to restore system
    func panic() {
        cleanup()
        currentState = .idle
        print("Panic unpin executed")
    }

    /// Hide mirror temporarily (for 2-click model)
    func hideMirror() {
        guard currentState == .mirroring else { return }
        mirrorHiddenAt = Date()
        mirrorWindowController?.hideMirror()
        currentState = .mirrorHidden
    }

    /// Show mirror again
    func showMirror() {
        print("showMirror")
        guard currentState == .mirrorHidden else { return }
        mirrorWindowController?.showMirror()
        currentState = .mirroring
    }

    /// Get current status
    func getStatus() -> AgentStatus {
        return AgentStatus(
            state: currentState,
            pinned: currentState == .mirroring || currentState == .mirrorHidden,
            targetAppName: targetInfo?.appName,
            targetWindowTitle: targetInfo?.windowTitle,
            mirrorVisible: currentState == .mirroring,
            pinnedSince: pinnedSince
        )
    }

    /// Set the mirror opacity (0.1 - 1.0, i.e., 10% - 100%)
    func setMirrorOpacity(_ opacity: Float) {
        let clampedOpacity = max(0.1, min(1.0, opacity))
        savedOpacity = clampedOpacity
        mirrorWindowController?.setOpacity(clampedOpacity)
    }

    /// Get the current mirror opacity (from saved value or current controller)
    var mirrorOpacity: Float {
        mirrorWindowController?.mirrorOpacity ?? savedOpacity
    }

    // MARK: - Private

    private func cleanup() {
        // Following Topit's cleanup pattern for crash prevention

        // 1. Stop monitoring timers first (prevents callbacks during cleanup)
        stopWindowExistenceMonitoring()

        // 2. Clear callbacks to prevent calls during teardown
        mirrorWindowController?.onHoverChanged = nil
        mirrorWindowController?.onGeometryChange = nil
        mirrorWindowController?.onUnpin = nil

        // 3. Stop capture first (invalidates stream output to stop callbacks)
        // This must happen before closing the mirror window
        windowCaptureManager?.stopCapture()

        // 4. Close mirror window (handles its own cleanup cascade)
        mirrorWindowController?.closeMirror()

        // 5. Clear our references immediately
        // The objects will handle their own deferred cleanup internally
        windowCaptureManager = nil
        mirrorWindowController = nil
        targetInfo = nil
        pinnedSince = nil
    }

    // MARK: - Frontmost App Observer (Phase 6.3: Mirror Re-Show Policy)

    private func setupFrontmostAppObserver() {
        frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleFrontmostAppChange(notification)
            }
        }
    }

    private func removeFrontmostAppObserver() {
        if let observer = frontmostAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontmostAppObserver = nil
        }
    }

    /// Check if mirror should be shown (called after delay)
    private func checkAndShowMirrorIfNeeded() {
        guard currentState == .mirrorHidden,
              let targetInfo = targetInfo else { return }

        // Check current frontmost app
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }

        let isTargetApp = frontmostApp.processIdentifier == targetInfo.pid

        if !isTargetApp {
            showMirror()
        }
    }

    private func handleFrontmostAppChange(_ notification: Notification) {
        guard let targetInfo = targetInfo else { return }

        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let isTargetApp = app.processIdentifier == targetInfo.pid

        switch currentState {
        case .mirrorHidden:
            // If target app is no longer frontmost, show mirror again
            // But wait for delay to allow activate() to take effect
            if !isTargetApp {
                if let hiddenAt = mirrorHiddenAt,
                   Date().timeIntervalSince(hiddenAt) < showMirrorDelay {
                    // Too soon after hiding, schedule a delayed check
                    DispatchQueue.main.asyncAfter(deadline: .now() + showMirrorDelay) { [weak self] in
                        self?.checkAndShowMirrorIfNeeded()
                    }
                } else {
                    showMirror()
                }
            }
        case .mirroring:
            // Mirror stays visible
            break
        case .idle, .error:
            break
        }
    }

    // MARK: - Window Existence Monitoring (Phase 7.2: Auto-recovery)

    private func startWindowExistenceMonitoring() {
        windowExistenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkWindowExistence()
            }
        }
    }

    private func stopWindowExistenceMonitoring() {
        windowExistenceTimer?.invalidate()
        windowExistenceTimer = nil
    }

    private func checkWindowExistence() {
        guard let targetInfo = targetInfo else { return }

        // Check if target window still exists
        if !targetWindowDetector.windowExists(windowID: targetInfo.windowID) {
            print("Target window disappeared, auto-unpinning")
            unpin()
        }
    }
}

// MARK: - Errors

enum AgentError: LocalizedError {
    case invalidStateTransition(from: AgentState, to: AgentState)
    case noTargetWindow
    case captureFailure(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .invalidStateTransition(let from, let to):
            return "Invalid state transition from \(from.rawValue) to \(to.rawValue)"
        case .noTargetWindow:
            return "No target window found"
        case .captureFailure(let reason):
            return "Capture failed: \(reason)"
        case .permissionDenied(let permission):
            return "Permission denied: \(permission)"
        }
    }
}
