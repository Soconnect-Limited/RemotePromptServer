import Combine
import Foundation

/// `MessageStore` maintains an in-memory cache of messages keyed by (roomId, runner).
/// サーバーが唯一の情報源となるため、永続化は行わず、UIの即時更新/キャッシュ用途に限定する。
final class MessageStore: ObservableObject {
    struct Context: Hashable {
        let roomId: String
        let runner: String
    }

    @Published private(set) var messages: [Message] = []

    private var storage: [Context: [Message]] = [:]
    private var activeContext: Context
    private let cacheLimit: Int
    private let legacyStorageKey = "chat_messages"

    init(defaultRoomId: String = "default-room", defaultRunner: String = "claude", cacheLimit: Int = 100) {
        self.cacheLimit = cacheLimit
        let context = Context(roomId: defaultRoomId, runner: defaultRunner)
        self.activeContext = context
        storage[context] = []
        migrateLegacyMessages(for: context)
    }

    func setActiveContext(roomId: String, runner: String) {
        let context = Context(roomId: roomId, runner: runner)
        activeContext = context
        if storage[context] == nil {
            storage[context] = []
        }
        messages = storage[context] ?? []
    }

    func messages(for context: Context) -> [Message] {
        storage[context] ?? []
    }

    func replaceAll(_ newMessages: [Message], for context: Context? = nil) {
        let target = context ?? activeContext
        let trimmed = trimCache(newMessages)
        storage[target] = trimmed
        if target == activeContext {
            messages = trimmed
        }
    }

    func addMessage(_ message: Message, context: Context? = nil) {
        let target = context ?? activeContext
        var list = storage[target] ?? []
        list.append(message)
        list = trimCache(list)
        storage[target] = list
        if target == activeContext {
            messages = list
        }
    }

    func updateMessage(_ message: Message, context: Context? = nil) {
        let target = context ?? activeContext
        guard var list = storage[target], let index = list.firstIndex(where: { $0.id == message.id }) else { return }
        list[index] = message
        storage[target] = list
        if target == activeContext {
            messages = list
        }
    }

    func clear(context: Context? = nil) {
        let target = context ?? activeContext
        storage[target] = []
        if target == activeContext {
            messages = []
        }
    }

    func clearAll() {
        storage.removeAll()
        messages.removeAll()
    }

    private func trimCache(_ list: [Message]) -> [Message] {
        let overflow = max(0, list.count - cacheLimit)
        return overflow > 0 ? Array(list.dropFirst(overflow)) : list
    }

    private func migrateLegacyMessages(for context: Context) {
        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacyMessages = try? decoder.decode([LegacyMessage].self, from: data) else {
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            return
        }

        let converted = legacyMessages.map { $0.toMessage(roomId: context.roomId) }
        let trimmed = trimCache(converted)
        storage[context] = trimmed
        messages = trimmed
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
    }

    private struct LegacyMessage: Codable {
        let id: String
        let jobId: String?
        let type: MessageType
        var content: String
        var status: MessageStatus
        let createdAt: Date
        var finishedAt: Date?
        var errorMessage: String?

        func toMessage(roomId: String) -> Message {
            Message(
                id: id,
                jobId: jobId,
                roomId: roomId,
                type: type,
                content: content,
                status: status,
                createdAt: createdAt,
                finishedAt: finishedAt,
                errorMessage: errorMessage
            )
        }
    }
}
