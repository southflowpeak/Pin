import Foundation

/// Agent application states as defined in SPEC 6.10
enum AgentState: String, Sendable {
    case idle = "idle"
    case mirroring = "mirroring"
    case mirrorHidden = "mirror_hidden"
    case error = "error"
}

/// Status information for IPC response
struct AgentStatus: Codable, Sendable {
    let state: String
    let pinned: Bool
    let targetAppName: String?
    let targetWindowTitle: String?
    let mirrorVisible: Bool
    let pinnedSince: Date?

    init(
        state: AgentState,
        pinned: Bool,
        targetAppName: String? = nil,
        targetWindowTitle: String? = nil,
        mirrorVisible: Bool = false,
        pinnedSince: Date? = nil
    ) {
        self.state = state.rawValue
        self.pinned = pinned
        self.targetAppName = targetAppName
        self.targetWindowTitle = targetWindowTitle
        self.mirrorVisible = mirrorVisible
        self.pinnedSince = pinnedSince
    }
}
