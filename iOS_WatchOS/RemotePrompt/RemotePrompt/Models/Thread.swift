import Foundation

/// スレッド情報を表すモデル
/// バックエンドのthreadsテーブルに対応
/// v4.2: runnerフィールド削除（Thread = 純粋な会話コンテナ）
/// v4.3: hasUnreadフィールド追加（未読通知用）
/// v4.3.1: unreadRunnersフィールド追加（runner別未読）
/// v4.4: aiSettingsフィールド追加（スレッド固有AI設定）
struct Thread: Codable, Identifiable, Hashable {
    let id: String
    let roomId: String
    var name: String
    let deviceId: String
    /// v4.3: 未読フラグ（推論完了時にtrue、スレッド表示時にfalse）
    var hasUnread: Bool
    /// v4.3.1: runner別未読リスト（例: ["claude", "codex"]）
    var unreadRunners: [String]
    /// v4.4: スレッド固有のAI設定（サーバー設定をオーバーライド）
    var aiSettings: ThreadAISettings?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case name
        case deviceId = "device_id"
        case hasUnread = "has_unread"
        case unreadRunners = "unread_runners"
        case aiSettings = "ai_settings"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        roomId = try container.decode(String.self, forKey: .roomId)
        name = try container.decode(String.self, forKey: .name)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        // v4.3: has_unreadがない場合はfalseとして扱う（後方互換性）
        hasUnread = try container.decodeIfPresent(Bool.self, forKey: .hasUnread) ?? false
        // v4.3.1: unread_runnersがない場合は空配列として扱う（後方互換性）
        unreadRunners = try container.decodeIfPresent([String].self, forKey: .unreadRunners) ?? []
        // v4.4: ai_settingsがない場合はnilとして扱う（後方互換性）
        aiSettings = try container.decodeIfPresent(ThreadAISettings.self, forKey: .aiSettings)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(roomId, forKey: .roomId)
        try container.encode(name, forKey: .name)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(hasUnread, forKey: .hasUnread)
        try container.encode(unreadRunners, forKey: .unreadRunners)
        try container.encodeIfPresent(aiSettings, forKey: .aiSettings)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    /// 通常のイニシャライザ（Preview用）
    init(
        id: String,
        roomId: String,
        name: String,
        deviceId: String,
        hasUnread: Bool = false,
        unreadRunners: [String] = [],
        aiSettings: ThreadAISettings? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.name = name
        self.deviceId = deviceId
        self.hasUnread = hasUnread
        self.unreadRunners = unreadRunners
        self.aiSettings = aiSettings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Thread作成リクエスト
/// device_idはQuery Parameterで送信されるため、Bodyに含まない
/// v4.2: runnerフィールド削除（サーバー側でrunner不要）
struct CreateThreadRequest: Codable {
    let name: String

    enum CodingKeys: String, CodingKey {
        case name
    }
}

/// Thread更新リクエスト
struct UpdateThreadRequest: Codable {
    let name: String
}

/// v4.4: スレッド固有のAI設定
/// サーバー設定をスレッドレベルでオーバーライドする
struct ThreadAISettings: Codable, Hashable {
    /// カスタムシステムプロンプト（nil = サーバー設定を使用）
    var systemPrompt: String?
    /// モデル名（nil = サーバー設定を使用）
    var model: String?
    /// 温度パラメータ（nil = サーバー設定を使用）
    var temperature: Double?

    enum CodingKeys: String, CodingKey {
        case systemPrompt = "system_prompt"
        case model
        case temperature
    }
}
