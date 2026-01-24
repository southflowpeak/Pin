import AppKit
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    @MainActor private var stateMachine: AgentStateMachine?
    @MainActor private var statusBarController: StatusBarController?

    /// Shared response file path for IPC
    static let responseFilePath = "/tmp/pin-response.json"

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        stateMachine = AgentStateMachine()

        // Setup menu bar icon
        if let stateMachine = stateMachine {
            statusBarController = StatusBarController(stateMachine: stateMachine)
        }

        // Register URL scheme handler
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Check required permissions
        Task {
            await checkPermissions()
        }

        print("Pin started")
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        stateMachine?.panic()
        print("Pin terminated")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - URL Scheme Handler

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "pin" else {
            return
        }

        let command = url.host ?? ""
        let query = url.query

        Task { @MainActor in
            await processCommand(command, query: query)
        }
    }

    @MainActor
    private func processCommand(_ command: String, query: String?) async {
        guard let stateMachine = stateMachine else {
            writeResponse(["error": "agent_not_ready"])
            return
        }

        let cmd = command.lowercased()

        // Parse query parameters from URL query string
        var params: [String: String] = [:]
        if let queryString = query {
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    params[String(kv[0])] = String(kv[1])
                }
            }
        }

        switch cmd {
        case "pin":
            do {
                try await stateMachine.pinActiveWindow()
                writeResponse(["success": true, "message": "pinned"])
            } catch {
                writeResponse(["success": false, "error": error.localizedDescription])
            }

        case "pin-window":
            guard let windowIDStr = params["id"],
                  let windowID = UInt32(windowIDStr) else {
                writeResponse(["success": false, "error": "missing_window_id"])
                return
            }
            do {
                try await pinWindowByID(CGWindowID(windowID))
                writeResponse(["success": true, "message": "pinned"])
            } catch {
                writeResponse(["success": false, "error": error.localizedDescription])
            }

        case "list-windows":
            print("Processing list-windows command")
            let detector = TargetWindowDetector()
            let windows = detector.getAllWindows()
            print("Found \(windows.count) windows")
            let windowsData = windows.map { window -> [String: Any] in
                return [
                    "windowID": window.windowID,
                    "pid": window.pid,
                    "appName": window.appName,
                    "windowTitle": window.windowTitle ?? "",
                    "bounds": [
                        "x": window.bounds.origin.x,
                        "y": window.bounds.origin.y,
                        "width": window.bounds.width,
                        "height": window.bounds.height
                    ]
                ]
            }
            print("Writing response")
            writeResponse(["success": true, "windows": windowsData])

        case "unpin":
            stateMachine.unpin()
            writeResponse(["success": true, "message": "unpinned"])

        case "panic":
            stateMachine.panic()
            writeResponse(["success": true, "message": "panic_complete"])

        case "status":
            let status = stateMachine.getStatus()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(status),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                writeResponse(json)
            } else {
                writeResponse(["error": "encoding_failed"])
            }

        default:
            print("Unknown command: '\(cmd)' (original: '\(command)')")
            writeResponse(["error": "unknown_command: \(command)"])
        }
    }

    @MainActor
    private func pinWindowByID(_ windowID: CGWindowID) async throws {
        guard let stateMachine = stateMachine else {
            throw AgentError.captureFailure("agent_not_ready")
        }

        let detector = TargetWindowDetector()
        let windows = detector.getAllWindows()

        guard let target = windows.first(where: { $0.windowID == windowID }) else {
            throw AgentError.noTargetWindow
        }

        try await stateMachine.pinWindow(target)
    }

    private func writeResponse(_ response: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
            try data.write(to: URL(fileURLWithPath: Self.responseFilePath))
        } catch {
            print("Failed to write response: \(error)")
        }
    }

    // MARK: - Permissions

    private func checkPermissions() async {
        let permissionChecker = PermissionChecker()

        let screenRecordingGranted = await permissionChecker.checkScreenRecording()
        let accessibilityGranted = permissionChecker.checkAccessibility()

        if !screenRecordingGranted {
            print("Warning: Screen Recording permission not granted")
        }

        if !accessibilityGranted {
            print("Warning: Accessibility permission not granted")
        }
    }
}
