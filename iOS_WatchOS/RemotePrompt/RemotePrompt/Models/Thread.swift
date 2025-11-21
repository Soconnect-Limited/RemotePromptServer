import Foundation

/// スレッド情報を表すモデル
/// バックエンドのthreadsテーブルに対応
/// v4.2: runnerフィールド削除（Thread = 純粋な会話コンテナ）
struct Thread: Codable, Identifiable, Hashable {
    let id: String
    let roomId: String
    var name: String
    let deviceId: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case name
        case deviceId = "device_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
