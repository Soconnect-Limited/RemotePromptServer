import Foundation

struct RoomSettings: Codable, Equatable {
    var claude: ClaudeSettings
    var codex: CodexSettings

    static var `default`: RoomSettings {
        RoomSettings(claude: .default, codex: .default)
    }
}

struct ClaudeSettings: Codable, Equatable {
    var model: String
    var permissionMode: String
    var tools: [String]
    var customFlags: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case permissionMode = "permission_mode"
        case tools
        case customFlags = "custom_flags"
    }

    static var `default`: ClaudeSettings {
        ClaudeSettings(
            model: "sonnet",
            permissionMode: "default",
            tools: ["Bash", "Edit", "Read", "Write", "Grep", "Glob"],
            customFlags: []
        )
    }
}

struct CodexSettings: Codable, Equatable {
    var model: String
    var sandbox: String
    var approvalPolicy: String
    var reasoningEffort: String
    var customFlags: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case sandbox
        case approvalPolicy = "approval_policy"
        case reasoningEffort = "reasoning_effort"
        case customFlags = "custom_flags"
    }

    static var `default`: CodexSettings {
        CodexSettings(
            model: "gpt-5.1-codex",
            sandbox: "workspace-write",
            approvalPolicy: "on-failure",
            reasoningEffort: "medium",
            customFlags: []
        )
    }
}
