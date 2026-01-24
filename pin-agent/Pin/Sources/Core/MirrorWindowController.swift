import Foundation
import AppKit
import AVFoundation
import QuartzCore
import ScreenCaptureKit

/// Controls the mirror window overlay
/// Based on Topit's implementation using AVSampleBufferDisplayLayer for direct video display
@MainActor
final class MirrorWindowController: NSObject {

    private var window: NSWindow?
    private var hoverView: HoverHandlerView?
    private let targetInfo: TargetWindowInfo

    private var geometryObserver: GeometryObserver?

    /// Global mouse monitor for detecting mouse exit when window ignores events
    private var globalMouseMonitor: Any?

    /// The capture manager that provides the video layer
    private let captureManager: WindowCaptureManager

    /// Callback when hover state changes (true = mouse entered, false = mouse exited)
    /// Based on Topit's onHover behavior
    var onHoverChanged: ((Bool) -> Void)?

    /// Callback when target window geometry changes (for updating capture size)
    var onGeometryChange: ((CGSize) -> Void)?

    /// Callback when unpin button is clicked
    var onUnpin: (() -> Void)?

    /// Separate window for pin button (always clickable even when mirror ignores events)
    private var pinButtonWindow: NSWindow?
    private var pinButton: PinButtonView?

    /// Pin button size and offset constants
    private let pinSize: CGFloat = 72
    private let pinOffset: CGFloat = -16

    /// Access to the capture manager for external control
    var capture: WindowCaptureManager { captureManager }

    init(targetInfo: TargetWindowInfo, captureManager: WindowCaptureManager) {
        self.targetInfo = targetInfo
        self.captureManager = captureManager
        super.init()
    }

    /// Create and show the mirror window
    func showMirror() {
        print("show")
        if window == nil {
            createWindow()
        }
        window?.ignoresMouseEvents = false
        window?.alphaValue = 1
        window?.orderFront(nil)
        window?.hasShadow = true

        // Show pin button window
        pinButtonWindow?.orderFront(nil)

        // Start geometry synchronization
        startGeometrySync()
    }

    /// Hide the mirror window (for hover model)
    /// Makes video layer transparent and ignores mouse events so clicks pass through
    /// Pin button remains visible for user to unpin
    /// Uses global mouse monitoring to detect when to unhide
    func hideMirror() {
        print("hide")
        window?.hasShadow = false
        // Make video layer transparent (not the whole window, so pin stays visible)
        captureManager.videoLayer.opacity = 0
        // Allow clicks to pass through to the window below
        window?.ignoresMouseEvents = true

        // Start monitoring global mouse movement to detect exit
        startGlobalMouseMonitoring()
    }

    /// Make the mirror window visible again (for hover model)
    func unhideMirror() {
        print("unhide")
        // Stop global mouse monitoring
        stopGlobalMouseMonitoring()

        window?.hasShadow = true
        // Make video layer opaque again
        captureManager.videoLayer.opacity = 1
        // Start receiving mouse events again
        window?.ignoresMouseEvents = false
    }

    /// Close and destroy the mirror window
    func closeMirror() {
        // 1. Stop all monitoring/timers first (following Topit's pattern)
        stopGeometrySync()
        stopGlobalMouseMonitoring()

        // 2. Clear all callbacks to prevent calls during teardown
        onHoverChanged = nil
        onGeometryChange = nil
        onUnpin = nil

        // 3. Prepare hover view for removal (clears tracking area and callback)
        hoverView?.prepareForRemoval()

        // 4. Remove video layer from hierarchy before any window operations
        captureManager.videoLayer.removeFromSuperlayer()

        // 5. Remove hover view and pin button from superview explicitly
        hoverView?.removeFromSuperview()
        pinButton?.removeFromSuperview()

        // 6. Hide the windows immediately (orderOut, not close)
        // Don't call close() - it triggers dealloc while animations may still reference the window
        window?.orderOut(nil)
        pinButtonWindow?.orderOut(nil)

        // 7. Clear our references - ARC will deallocate the window
        // when all references (including animation blocks) are gone
        window = nil
        hoverView = nil
        pinButton = nil
        pinButtonWindow = nil
    }

    /// Attach the video layer to the window
    /// Call this after the capture manager starts capturing
    func attachVideoLayer() {
        guard let contentView = window?.contentView,
              let layer = contentView.layer else { return }

        let videoLayer = captureManager.videoLayer
        videoLayer.frame = contentView.bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        // Insert video layer below hover handler view
        layer.insertSublayer(videoLayer, at: 0)
    }

    /// Update the video layer frame when window size changes
    func updateVideoLayerFrame() {
        guard let contentView = window?.contentView else { return }
        captureManager.videoLayer.frame = contentView.bounds
    }

    /// Handle hover enter on mirror window
    /// Activates target application and notifies state machine after delay
    func handleHoverEnter() {
        // Activate target application first
        if let app = NSRunningApplication(processIdentifier: targetInfo.pid) {
            app.activate()
        }

        // Notify state machine to hide mirror after 250ms delay
        // This allows the target window to become fully active before hiding
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.onHoverChanged?(true)
        }
    }

    /// Handle hover exit on mirror window
    /// Notifies state machine to show mirror again
    func handleHoverExit() {
        onHoverChanged?(false)
    }

    // MARK: - Global Mouse Monitoring

    private func startGlobalMouseMonitoring() {
        guard globalMouseMonitor == nil else { return }

        // Monitor global mouse movement to detect when mouse leaves the window area
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            Task { @MainActor in
                self?.checkMousePosition()
            }
        }
    }

    private func stopGlobalMouseMonitoring() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    private func checkMousePosition() {
        guard let windowFrame = window?.frame else { return }

        // Get current mouse location in screen coordinates
        let mouseLocation = NSEvent.mouseLocation

        // Check if mouse is outside the window frame
        if !windowFrame.contains(mouseLocation) {
            // Mouse has left the window area, unhide the mirror
            handleHoverExit()
        }
    }

    // MARK: - Private

    private func createWindow() {
        // Convert CGRect bounds (screen coordinates) to NSRect
        let frame = convertToScreenFrame(targetInfo.bounds)

        // Create borderless, floating window
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Make content view layer-backed for transparency
        // Note: No cornerRadius - ScreenCaptureKit captures window with its original transparency
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        // Set up hover handler
        let hoverView = HoverHandlerView(frame: window.contentView!.bounds)
        hoverView.autoresizingMask = [.width, .height]
        hoverView.onHover = { [weak self] isHovering in
            if isHovering {
                self?.handleHoverEnter()
            }
            // Note: mouseExited is handled by global mouse monitoring when hidden
        }
        window.contentView?.addSubview(hoverView)

        self.window = window
        self.hoverView = hoverView

        // Create separate pin button window (always clickable)
        createPinButtonWindow(relativeTo: frame)
    }

    private func createPinButtonWindow(relativeTo mirrorFrame: NSRect) {
        // Calculate pin button position in screen coordinates
        // Pin is positioned at top-left corner with offset, shifted up by 36px
        let pinFrame = NSRect(
            x: mirrorFrame.origin.x + pinOffset,
            y: mirrorFrame.origin.y + mirrorFrame.height - pinSize - pinOffset + 18,
            width: pinSize,
            height: pinSize
        )

        // Create borderless window for pin button
        let pinWindow = NSWindow(
            contentRect: pinFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Level above the mirror window
        pinWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        pinWindow.isOpaque = false
        pinWindow.backgroundColor = .clear
        pinWindow.hasShadow = false
        pinWindow.ignoresMouseEvents = false  // Always clickable
        pinWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Create pin button view
        let pinButton = PinButtonView(frame: NSRect(origin: .zero, size: pinFrame.size))
        pinButton.autoresizingMask = [.width, .height]
        pinButton.onClicked = { [weak self] in
            self?.onUnpin?()
        }
        pinWindow.contentView = pinButton

        self.pinButtonWindow = pinWindow
        self.pinButton = pinButton
    }

    private func convertToScreenFrame(_ cgRect: CGRect) -> NSRect {
        // CGRect uses top-left origin, NSRect uses bottom-left
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: cgRect.size)
        }

        let screenHeight = screen.frame.height
        let y = screenHeight - cgRect.origin.y - cgRect.height

        return NSRect(
            x: cgRect.origin.x,
            y: y,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    private func startGeometrySync() {
        geometryObserver = GeometryObserver(windowID: targetInfo.windowID) { [weak self] newBounds in
            Task { @MainActor in
                self?.updateWindowFrame(newBounds)
            }
        }
        geometryObserver?.start()
    }

    private func stopGeometrySync() {
        geometryObserver?.stop()
        geometryObserver = nil
    }

    private func updateWindowFrame(_ bounds: CGRect) {
        let frame = convertToScreenFrame(bounds)
        window?.setFrame(frame, display: true, animate: false)

        // Update pin button window position
        updatePinButtonPosition(relativeTo: frame)

        // Update video layer frame
        updateVideoLayerFrame()

        // Notify about geometry change for capture size update
        onGeometryChange?(bounds.size)
    }

    private func updatePinButtonPosition(relativeTo mirrorFrame: NSRect) {
        let pinFrame = NSRect(
            x: mirrorFrame.origin.x + pinOffset,
            y: mirrorFrame.origin.y + mirrorFrame.height - pinSize - pinOffset + 18,
            width: pinSize,
            height: pinSize
        )
        pinButtonWindow?.setFrame(pinFrame, display: true, animate: false)
    }
}

// MARK: - Hover Handler View

/// View that tracks mouse enter/exit events using NSTrackingArea
/// Based on Topit's onHover implementation
private class HoverHandlerView: NSView {

    var onHover: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }

    deinit {
        // Note: Do NOT call removeTrackingArea() in deinit
        // It's unsafe to call NSView methods during deallocation
        // prepareForRemoval() must be called before releasing the view
        onHover = nil
        trackingArea = nil
    }

    /// Prepare view for removal - call before removeFromSuperview()
    func prepareForRemoval() {
        onHover = nil
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
            trackingArea = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        // Remove existing tracking area
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        // Create new tracking area that tracks mouse enter/exit
        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

// MARK: - Geometry Observer

private class GeometryObserver {

    private let windowID: CGWindowID
    private var onBoundsChange: ((CGRect) -> Void)?
    private var timer: Timer?
    private var lastBounds: CGRect?

    init(windowID: CGWindowID, onBoundsChange: @escaping (CGRect) -> Void) {
        self.windowID = windowID
        self.onBoundsChange = onBoundsChange
    }

    deinit {
        // Ensure timer is invalidated to prevent callbacks after deallocation
        timer?.invalidate()
        timer = nil
        onBoundsChange = nil
    }

    func start() {
        // Poll for geometry changes (fallback method)
        // TODO: Use Accessibility API for more efficient notification-based updates
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkBounds()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onBoundsChange = nil
    }

    private func checkBounds() {
        guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let windowInfo = windowList.first,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
            return
        }

        let bounds = CGRect(
            x: boundsDict["X"] ?? 0,
            y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0,
            height: boundsDict["Height"] ?? 0
        )

        if bounds != lastBounds {
            lastBounds = bounds
            onBoundsChange?(bounds)
        }
    }
}

// MARK: - Pin Button View

/// Button view that displays a pin icon and handles click events
private class PinButtonView: NSView {

    var onClicked: (() -> Void)?

    private var imageView: NSImageView?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Create image view for pin icon
        let imageView = NSImageView(frame: bounds)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSImage(named: "PinIcon")
        addSubview(imageView)
        self.imageView = imageView

        // Set up tracking area for hover detection
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        // Visual feedback on click
        alphaValue = 0.7
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = isHovered ? 0.9 : 1.0

        // Check if mouse is still inside the button
        let locationInView = convert(event.locationInWindow, from: nil)
        if bounds.contains(locationInView) {
            onClicked?()
        }
    }

    private func updateAppearance() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = isHovered ? 0.9 : 1.0
        }
    }
}
