import Combine
import Foundation

final class MessageStore: ObservableObject {
    @Published private(set) var messages: [Message] = []
    private let storageKey = "chat_messages"
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        loadMessages()
    }

    func addMessage(_ message: Message) {
        messages.append(message)
        saveMessages()
    }

    func updateMessage(_ message: Message) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = message
        saveMessages()
    }

    func replaceAll(with newMessages: [Message]) {
        messages = newMessages
        saveMessages()
    }

    func clearAll() {
        messages.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func saveMessages() {
        guard let data = try? encoder.encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([Message].self, from: data) else {
            messages = []
            return
        }
        messages = decoded
    }
}
