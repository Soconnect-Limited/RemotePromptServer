import Foundation

/// スレッド情報を表すモデル
/// バックエンドのthreadsテーブルに対応
/// v4.2: runnerフィールド削除（Thread = 純粋な会話コンテナ）
/// v4.3: hasUnreadフィールド追加（未読通知用）
/// v4.3.1: unreadRunnersフィールド追加（runner別未読）
struct Thread: Codable, Identifiable, Hashable {
    let id: String
    let roomId: String
    var name: String
    let deviceId: String
    /// v4.3: 未読フラグ（推論完了時にtrue、スレッド表示時にfalse）
    var hasUnread: Bool
    /// v4.3.1: runner別未読リスト（例: ["claude", "codex"]）
    var unreadRunners: [String]
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case name
        case deviceId = "device_id"
        case hasUnread = "has_unread"
        case unreadRunners = "unread_runners"
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
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// 通常のイニシャライザ（Preview用）
    init(
        id: String,
        roomId: String,
        name: String,
        deviceId: String,
        hasUnread: Bool = false,
        unreadRunners: [String] = [],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.name = name
        self.deviceId = deviceId
        self.hasUnread = hasUnread
        self.unreadRunners = unreadRunners
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
