import Foundation
import ScreenCaptureKit
import AppKit

/// Checks and requests required system permissions
final class PermissionChecker: Sendable {

    static let shared = PermissionChecker()

    init() {}

    /// Check Screen Recording permission
    /// Returns true if granted, false otherwise
    func checkScreenRecording() async -> Bool {
        do {
            // Requesting shareable content will prompt for permission if not granted
            _ = try await SCShareableContent.current
            return true
        } catch {
            print("Screen Recording permission check failed: \(error)")
            return false
        }
    }

    /// Check Accessibility permission
    /// Returns true if granted, false otherwise
    func checkAccessibility() -> Bool {
        // Check if accessibility is enabled
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Prompt user to grant Accessibility permission
    func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Get human-readable permission status
    func getPermissionStatus() async -> PermissionStatus {
        let screenRecording = await checkScreenRecording()
        let accessibility = checkAccessibility()

        return PermissionStatus(
            screenRecordingGranted: screenRecording,
            accessibilityGranted: accessibility
        )
    }

    /// Show an alert explaining Screen Recording permission is required
    @MainActor
    func showScreenRecordingPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Pin needs Screen Recording permission to capture and display windows.\n\nPlease enable it in System Settings > Privacy & Security > Screen Recording, then restart the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }

    /// Open System Settings to Screen Recording pane
    @MainActor
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PermissionStatus: Codable, Sendable {
    let screenRecordingGranted: Bool
    let accessibilityGranted: Bool

    var allGranted: Bool {
        screenRecordingGranted && accessibilityGranted
    }

    var missingPermissions: [String] {
        var missing: [String] = []
        if !screenRecordingGranted {
            missing.append("Screen Recording")
        }
        if !accessibilityGranted {
            missing.append("Accessibility")
        }
        return missing
    }
}
