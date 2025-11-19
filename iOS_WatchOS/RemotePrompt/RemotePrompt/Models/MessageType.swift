import Foundation

enum MessageType: String, Codable {
    case user
    case assistant
    case system
}

enum MessageStatus: String, Codable {
    case sending
    case queued
    case running
    case completed
    case failed
}
