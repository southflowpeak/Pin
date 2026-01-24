import Foundation
import CoreGraphics

/// Information about the target window being mirrored
struct TargetWindowInfo: Sendable {
    let pid: pid_t
    let windowID: CGWindowID
    let appName: String
    let windowTitle: String?
    let bounds: CGRect

    init(
        pid: pid_t,
        windowID: CGWindowID,
        appName: String,
        windowTitle: String?,
        bounds: CGRect
    ) {
        self.pid = pid
        self.windowID = windowID
        self.appName = appName
        self.windowTitle = windowTitle
        self.bounds = bounds
    }
}
