import Foundation

struct RoomSettings: Codable, Equatable {
    var claude: ClaudeSettings
    var codex: CodexSettings
    var gemini: GeminiSettings

    static var `default`: RoomSettings {
        RoomSettings(claude: .default, codex: .default, gemini: .default)
    }

    // MARK: - Custom Decoder for Backward Compatibility

    init(claude: ClaudeSettings, codex: CodexSettings, gemini: GeminiSettings) {
        self.claude = claude
        self.codex = codex
        self.gemini = gemini
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claude = try container.decode(ClaudeSettings.self, forKey: .claude)
        codex = try container.decode(CodexSettings.self, forKey: .codex)
        // geminiは省略可能（後方互換性）
        gemini = try container.decodeIfPresent(GeminiSettings.self, forKey: .gemini) ?? .default
    }

    enum CodingKeys: String, CodingKey {
        case claude, codex, gemini
    }
}

struct ClaudeSettings: Codable, Equatable {
    var model: String
    var permissionMode: String
    var tools: [String]
    var customFlags: [String]
    // v4.6: 動的ツール許可/拒否
    var allowedTools: [String]
    var disallowedTools: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case permissionMode = "permission_mode"
        case tools
        case customFlags = "custom_flags"
        case allowedTools = "allowed_tools"
        case disallowedTools = "disallowed_tools"
    }

    // 後方互換性のためのカスタムデコーダ
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        permissionMode = try container.decode(String.self, forKey: .permissionMode)
        tools = try container.decode([String].self, forKey: .tools)
        customFlags = try container.decode([String].self, forKey: .customFlags)
        // v4.6: 新フィールドは省略可能
        allowedTools = try container.decodeIfPresent([String].self, forKey: .allowedTools) ?? []
        disallowedTools = try container.decodeIfPresent([String].self, forKey: .disallowedTools) ?? []
    }

    init(model: String, permissionMode: String, tools: [String], customFlags: [String], allowedTools: [String] = [], disallowedTools: [String] = []) {
        self.model = model
        self.permissionMode = permissionMode
        self.tools = tools
        self.customFlags = customFlags
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
    }

    static var `default`: ClaudeSettings {
        ClaudeSettings(
            model: "sonnet",
            permissionMode: "default",
            tools: ["Bash", "Edit", "Read", "Write", "Grep", "Glob"],
            customFlags: [],
            allowedTools: [],
            disallowedTools: []
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

struct GeminiSettings: Codable, Equatable {
    var model: String
    var sandbox: Bool
    var yolo: Bool
    var approvalMode: String
    var customFlags: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case sandbox
        case yolo
        case approvalMode = "approval_mode"
        case customFlags = "custom_flags"
    }

    static var `default`: GeminiSettings {
        GeminiSettings(
            model: "gemini-3.0-pro",
            sandbox: false,
            yolo: false,
            approvalMode: "default",
            customFlags: []
        )
    }
}
