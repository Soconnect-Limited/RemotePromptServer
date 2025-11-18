import Foundation

struct Job: Codable, Identifiable {
    let id: String
    let runner: String
    var status: String
    let stdout: String?
    let stderr: String?
    let exitCode: Int?
    let createdAt: Date?
    let startedAt: Date?
    let finishedAt: Date?

    var isRunning: Bool {
        status == "queued" || status == "running"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case runner
        case status
        case stdout
        case stderr
        case exitCode = "exit_code"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}
