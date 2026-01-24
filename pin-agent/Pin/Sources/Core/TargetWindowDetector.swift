import Foundation
import AppKit
import CoreGraphics

/// Detects and monitors target windows using Accessibility API
@MainActor
final class TargetWindowDetector {

    /// Bundle IDs to exclude from detection (launchers, self, etc.)
    private let excludedBundleIDs: Set<String> = [
        "com.southflowpeak.Pin",  // Self
        "com.raycast.macos",                         // Raycast
        "com.apple.Spotlight",                       // Spotlight
        "com.apple.alfred",                          // Alfred
        "com.runningwithcrayons.Alfred",             // Alfred (alternative)
    ]

    init() {}

    /// Detect the frontmost window from the frontmost application
    /// If frontmost app is excluded (e.g., Raycast, self), finds the topmost valid window
    func detectFrontmostWindow() async -> TargetWindowInfo? {
        // Get window list sorted by window layer (front to back)
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Get running applications for bundle ID lookup
        let runningApps = NSWorkspace.shared.runningApplications

        // Find first valid window (excluding our app and launchers)
        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? Int else {
                continue
            }

            // Skip non-normal windows (menu bars, docks, overlays, etc.)
            guard windowLayer == 0 else {
                continue
            }

            // Find the app for this window
            guard let app = runningApps.first(where: { $0.processIdentifier == windowPID }) else {
                continue
            }

            // Skip excluded apps (self, Raycast, Spotlight, etc.)
            if let bundleID = app.bundleIdentifier, excludedBundleIDs.contains(bundleID) {
                continue
            }

            // Skip windows with no bounds or tiny windows
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            guard bounds.width > 50 && bounds.height > 50 else {
                continue
            }

            let appName = app.localizedName ?? "Unknown"
            let windowTitle = windowInfo[kCGWindowName as String] as? String

            return TargetWindowInfo(
                pid: windowPID,
                windowID: windowID,
                appName: appName,
                windowTitle: windowTitle,
                bounds: bounds
            )
        }

        return nil
    }

    /// Check if a specific window still exists
    func windowExists(windowID: CGWindowID) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] else {
            return false
        }
        return !windowList.isEmpty
    }

    /// Get list of all valid windows (for window picker)
    func getAllWindows() -> [TargetWindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let runningApps = NSWorkspace.shared.runningApplications
        var windows: [TargetWindowInfo] = []

        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? Int else {
                continue
            }

            // Skip non-normal windows
            guard windowLayer == 0 else {
                continue
            }

            guard let app = runningApps.first(where: { $0.processIdentifier == windowPID }) else {
                continue
            }

            // Skip excluded apps
            if let bundleID = app.bundleIdentifier, excludedBundleIDs.contains(bundleID) {
                continue
            }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            guard bounds.width > 50 && bounds.height > 50 else {
                continue
            }

            let appName = app.localizedName ?? "Unknown"
            let windowTitle = windowInfo[kCGWindowName as String] as? String

            windows.append(TargetWindowInfo(
                pid: windowPID,
                windowID: windowID,
                appName: appName,
                windowTitle: windowTitle,
                bounds: bounds
            ))
        }

        return windows
    }

    /// Get updated bounds for a window
    func getWindowBounds(windowID: CGWindowID) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let windowInfo = windowList.first,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }

        return CGRect(
            x: boundsDict["X"] ?? 0,
            y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0,
            height: boundsDict["Height"] ?? 0
        )
    }
}
