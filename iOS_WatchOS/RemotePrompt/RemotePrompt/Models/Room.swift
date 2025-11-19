import Foundation

struct Room: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var workspacePath: String
    var icon: String
    let deviceId: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case workspacePath = "workspace_path"
        case icon
        case deviceId = "device_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
