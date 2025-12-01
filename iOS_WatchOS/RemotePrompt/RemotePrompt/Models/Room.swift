import Foundation

/// v4.3.2: unreadCountフィールド追加（未読スレッド数）
struct Room: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var workspacePath: String
    var icon: String
    let deviceId: String
    var sortOrder: Int
    /// v4.3.2: このRoom内の未読スレッド数
    var unreadCount: Int
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case workspacePath = "workspace_path"
        case icon
        case deviceId = "device_id"
        case sortOrder = "sort_order"
        case unreadCount = "unread_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        workspacePath = try container.decode(String.self, forKey: .workspacePath)
        icon = try container.decode(String.self, forKey: .icon)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    init(
        id: String,
        name: String,
        workspacePath: String,
        icon: String,
        deviceId: String,
        sortOrder: Int = 0,
        unreadCount: Int = 0,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.workspacePath = workspacePath
        self.icon = icon
        self.deviceId = deviceId
        self.sortOrder = sortOrder
        self.unreadCount = unreadCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
