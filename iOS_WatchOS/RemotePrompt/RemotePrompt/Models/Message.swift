import Foundation

struct Message: Identifiable, Codable {
    let id: String
    let jobId: String?
    let roomId: String
    let type: MessageType
    var content: String
    var status: MessageStatus
    let createdAt: Date
    var finishedAt: Date?
    var errorMessage: String?

    var isRunning: Bool {
        status == .sending || status == .queued || status == .running
    }

    init(
        id: String = UUID().uuidString,
        jobId: String? = nil,
        roomId: String,
        type: MessageType,
        content: String,
        status: MessageStatus,
        createdAt: Date = Date(),
        finishedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.jobId = jobId
        self.roomId = roomId
        self.type = type
        self.content = content
        self.status = status
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case jobId = "job_id"
        case roomId = "room_id"
        case type
        case content
        case status
        case createdAt = "created_at"
        case finishedAt = "finished_at"
        case errorMessage = "error_message"
    }
}
