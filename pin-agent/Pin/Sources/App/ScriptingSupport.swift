import Foundation
import AppKit

/// AppleScript command handlers for IPC
/// Raycast extension communicates with Agent via AppleScript
@MainActor
final class ScriptingSupport {

    static let shared = ScriptingSupport()
    private var stateMachine: AgentStateMachine?

    private init() {}

    func setStateMachine(_ stateMachine: AgentStateMachine) {
        self.stateMachine = stateMachine
    }

    /// Handle "pin" command from AppleScript
    func handlePin() async -> String {
        guard let stateMachine = stateMachine else {
            return "error:agent_not_ready"
        }

        do {
            try await stateMachine.pinActiveWindow()
            return "success:pinned"
        } catch {
            return "error:\(error.localizedDescription)"
        }
    }

    /// Handle "unpin" command from AppleScript
    func handleUnpin() -> String {
        guard let stateMachine = stateMachine else {
            return "error:agent_not_ready"
        }

        stateMachine.unpin()
        return "success:unpinned"
    }

    /// Handle "panic" command from AppleScript
    func handlePanic() -> String {
        guard let stateMachine = stateMachine else {
            return "error:agent_not_ready"
        }

        stateMachine.panic()
        return "success:panic_complete"
    }

    /// Handle "status" command from AppleScript
    func handleStatus() -> String {
        guard let stateMachine = stateMachine else {
            return "error:agent_not_ready"
        }

        let status = stateMachine.getStatus()

        // Return JSON-formatted status
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys

        do {
            let data = try encoder.encode(status)
            return String(data: data, encoding: .utf8) ?? "error:encoding_failed"
        } catch {
            return "error:encoding_failed"
        }
    }
}

// MARK: - AppleScript Command Handling via NSAppleEventManager

extension AppDelegate {

    func setupAppleScriptHandling() {
        let appleEventManager = NSAppleEventManager.shared()

        // Register for "do script" events
        appleEventManager.setEventHandler(
            self,
            andSelector: #selector(handleAppleScriptCommand(_:withReply:)),
            forEventClass: AEEventClass(kAECoreSuite),
            andEventID: AEEventID(kAEDoScript)
        )
    }

    @objc func handleAppleScriptCommand(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let commandString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return
        }

        Task { @MainActor in
            let result = await processCommand(commandString)
            // Note: Setting reply is complex with async; for MVP, we use osascript with do shell script
            print("Command result: \(result)")
        }
    }

    @MainActor
    private func processCommand(_ command: String) async -> String {
        switch command.lowercased() {
        case "pin":
            return await ScriptingSupport.shared.handlePin()
        case "unpin":
            return ScriptingSupport.shared.handleUnpin()
        case "panic":
            return ScriptingSupport.shared.handlePanic()
        case "status":
            return ScriptingSupport.shared.handleStatus()
        default:
            return "error:unknown_command"
        }
    }
}
