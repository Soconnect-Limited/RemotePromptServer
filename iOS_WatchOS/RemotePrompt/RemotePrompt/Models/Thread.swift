import Foundation

/// スレッド情報を表すモデル
/// バックエンドのthreadsテーブルに対応
struct Thread: Codable, Identifiable, Hashable {
    let id: String
    let roomId: String
    var name: String
    let runner: String  // "claude" or "codex"
    let deviceId: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case name
        case runner
        case deviceId = "device_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Thread作成リクエスト
/// device_idはQuery Parameterで送信されるため、Bodyに含まない
struct CreateThreadRequest: Codable {
    let roomId: String
    let name: String
    let runner: String

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case name
        case runner
    }
}

/// Thread更新リクエスト
struct UpdateThreadRequest: Codable {
    let name: String
}
