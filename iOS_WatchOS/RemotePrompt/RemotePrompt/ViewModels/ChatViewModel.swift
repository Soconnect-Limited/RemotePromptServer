import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isHistoryLoading = false
    @Published var isLoadingMoreHistory = false
    @Published var canLoadMoreHistory = true

    private let apiClient: APIClientProtocol
    private let messageStore: MessageStore
    private let deviceIdProvider: () -> String
    private let enableStreaming: Bool
    private let shouldAutoLoadMessages: Bool
    private let shouldValidateAPIKey: Bool
    private var sseConnections: [String: SSEManager] = [:]
    private var sseCancellables: [String: Set<AnyCancellable>] = [:]
    private var runner: String  // v4.1: Changed from `let` to `var` for dynamic runner switching
    private let roomId: String  // v3.0: Room ID
    private let threadId: String?  // v4.0: Thread ID (optional for backward compatibility)
    private let deviceId: String
    private let historyPageSize = 20
    private var historyOffset = 0

    var historyOffsetSnapshot: Int { historyOffset }
    var runnerName: String { runner }

    init(
        runner: String = "claude",
        roomId: String = "default-room",
        threadId: String? = nil,  // v4.0: Thread ID (nil = use default thread in compatibility mode)
        apiClient: APIClientProtocol = APIClient.shared,
        messageStore: MessageStore = MessageStore(),
        deviceIdProvider: @escaping () -> String = APIClient.getDeviceId,
        autoLoadMessages: Bool = true,
        enableStreaming: Bool = true,
        validateAPIKey: Bool = true
    ) {
        self.runner = runner
        self.roomId = roomId
        self.threadId = threadId
        self.apiClient = apiClient
        self.messageStore = messageStore
        self.deviceIdProvider = deviceIdProvider
        self.enableStreaming = enableStreaming
        self.shouldAutoLoadMessages = autoLoadMessages
        self.shouldValidateAPIKey = validateAPIKey
        self.deviceId = deviceIdProvider()
        // v4.2: 3次元キー対応（threadId必須）
        messageStore.setActiveContext(roomId: roomId, runner: runner, threadId: threadId ?? "default-thread")
        messages = messageStore.messages
        if autoLoadMessages {
            Task {
                await loadLatestMessages()
                await recoverIncompleteJobs()
            }
        }
    }

    func loadLatestMessages() async {
        await fetchHistory(reset: true)
    }

    func loadMoreMessages() async {
        await fetchHistory(reset: false)
    }

    private func fetchHistory(reset: Bool) async {
        if reset {
            guard !isHistoryLoading else { return }
            isHistoryLoading = true
        } else {
            guard canLoadMoreHistory, !isLoadingMoreHistory else { return }
            isLoadingMoreHistory = true
        }

        defer {
            if reset {
                isHistoryLoading = false
            } else {
                isLoadingMoreHistory = false
            }
        }

        do {
            let offsetValue = reset ? 0 : historyOffset
            let jobs = try await apiClient.fetchMessages(
                deviceId: deviceId,
                roomId: roomId,
                runner: runner,
                threadId: threadId,  // v4.0: Thread ID for message filtering
                limit: historyPageSize,
                offset: offsetValue
            )

            canLoadMoreHistory = jobs.count == historyPageSize
            historyOffset = reset ? jobs.count : historyOffset + jobs.count

            let historicalMessages = convertJobsToMessages(jobs)
            let combinedMessages = reset ? historicalMessages : (historicalMessages + messages)

            messageStore.replaceAll(combinedMessages)
            messages = messageStore.messages
        } catch {
            // キャンセルエラーは無視（View再生成時に発生）
            if (error as NSError).code != NSURLErrorCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    func convertJobsToMessages(_ jobs: [Job]) -> [Message] {
        var result: [Message] = []
        for job in jobs {
            if let prompt = job.inputText, !prompt.isEmpty {
                let userMessage = Message(
                    id: "\(job.id)-user",
                    jobId: job.id,
                    roomId: job.roomId,
                    type: .user,
                    content: prompt,
                    status: .completed,
                    createdAt: job.createdAt ?? Date()
                )
                result.append(userMessage)
            }

            let assistantMessage = Message(
                id: "\(job.id)-assistant",
                jobId: job.id,
                roomId: job.roomId,
                type: .assistant,
                content: job.stdout ?? "",
                status: mapStatus(from: job.status),
                createdAt: job.startedAt ?? job.createdAt ?? Date(),
                finishedAt: job.finishedAt,
                errorMessage: job.stderr
            )
            result.append(assistantMessage)
        }
        return result
    }

    private func mapStatus(from status: String) -> MessageStatus {
        switch status.lowercased() {
        case "queued":
            return .queued
        case "running":
            return .running
        case "failed":
            return .failed
        default:
            return .completed
        }
    }

    private func recoverIncompleteJobs() async {
        let incomplete = messages.filter { $0.isRunning && $0.jobId != nil }

        for message in incomplete {
            guard let jobId = message.jobId else { continue }
            do {
                let job = try await apiClient.fetchJob(id: jobId)
                guard let index = messages.firstIndex(where: { $0.id == message.id }) else { continue }

                var updated = messages[index]
                updated.status = job.status == "success" ? .completed :
                    job.status == "failed" ? .failed :
                    job.status == "running" ? .running : .queued
                updated.content = job.stdout ?? updated.content
                updated.finishedAt = job.finishedAt
                updated.errorMessage = job.stderr
                messages[index] = updated
                messageStore.updateMessage(updated)

                if updated.isRunning {
                    startSSEStreaming(jobId: jobId, messageId: updated.id)
                }
            } catch {
                guard let index = messages.firstIndex(where: { $0.id == message.id }) else { continue }
                var failed = messages[index]
                failed.status = .failed
                failed.errorMessage = "回復失敗: \(error.localizedDescription)"
                messages[index] = failed
                messageStore.updateMessage(failed)
            }
        }
    }

    func sendMessage() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard ensureAPIKeyConfigured() else { return }

        inputText = ""
        isLoading = true

        let userMessage = Message(
            roomId: roomId,
            type: .user,
            content: prompt,
            status: .sending
        )
        messages.append(userMessage)
        messageStore.addMessage(userMessage)

        Task {
            defer { isLoading = false }
            do {
                let response = try await apiClient.createJob(
                    runner: runner,
                    prompt: prompt,
                    deviceId: deviceId,
                    roomId: roomId,  // v3.0: Room ID
                    threadId: threadId  // v4.0: Thread ID (nil = use default thread)
                )

                var updatedUser = userMessage
                updatedUser.status = .completed
                updatedUser.finishedAt = Date()
                updateMessage(updatedUser)

                let assistantMessage = Message(
                    jobId: response.id,
                    roomId: roomId,
                    type: .assistant,
                    content: "",
                    status: .queued
                )
                messages.append(assistantMessage)
                messageStore.addMessage(assistantMessage)
                historyOffset += 1

                startSSEStreaming(jobId: response.id, messageId: assistantMessage.id)
            } catch {
                errorMessage = error.localizedDescription
                var failed = userMessage
                failed.status = .failed
                failed.errorMessage = error.localizedDescription
                updateMessage(failed)
            }
        }
    }

    private func ensureAPIKeyConfigured() -> Bool {
        guard shouldValidateAPIKey else { return true }
        guard Constants.isAPIKeyConfigured else {
            errorMessage = Constants.missingAPIKeyMessage
            return false
        }
        return true
    }

    private func startSSEStreaming(jobId: String, messageId: String) {
        guard enableStreaming else {
            Task { @MainActor in
                await self.fetchFinalResult(jobId: jobId, messageId: messageId)
            }
            return
        }
        print("DEBUG: Starting SSE streaming for job \(jobId)")
        if let existing = sseConnections[jobId] {
            print("DEBUG: Disconnecting existing SSE connection")
            existing.disconnect()
        }

        let manager = SSEManager()
        sseConnections[jobId] = manager

        var connectionCancellables = Set<AnyCancellable>()

        // IMPORTANT: 購読をconnect()の前に設定
        manager.$jobStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                print("DEBUG: Received job status update: \(status)")
                self?.updateMessageStatus(messageId: messageId, status: status)
            }
            .store(in: &connectionCancellables)

        manager.$isConnected
            .dropFirst() // 初期値(false)をスキップ
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                print("DEBUG: SSE connection status changed: \(connected)")
                guard let self else { return }
                if !connected {
                    print("DEBUG: SSE disconnected, fetching final result")
                    Task { @MainActor in
                        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
                        self.cleanupConnection(for: jobId)
                    }
                }
            }
            .store(in: &connectionCancellables)

        manager.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                print("DEBUG: SSE error: \(message)")
                self?.errorMessage = message
            }
            .store(in: &connectionCancellables)

        sseCancellables[jobId] = connectionCancellables

        // 購読設定後にconnect()を呼び出す
        manager.connect(jobId: jobId)
    }

    private func cleanupConnection(for jobId: String) {
        sseConnections[jobId]?.disconnect()
        sseConnections.removeValue(forKey: jobId)
        sseCancellables.removeValue(forKey: jobId)?.forEach { $0.cancel() }
    }

    private func updateMessageStatus(messageId: String, status: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        var message = messages[index]

        switch status {
        case "running":
            message.status = .running
        case "success":
            message.status = .completed
            message.finishedAt = Date()
        case "failed":
            message.status = .failed
            message.finishedAt = Date()
        default:
            break
        }

        messages[index] = message
        messageStore.updateMessage(message)
    }

    private func fetchFinalResult(jobId: String, messageId: String) async {
        do {
            print("DEBUG: Fetching final result for job \(jobId)")
            let job = try await apiClient.fetchJob(id: jobId)
            print("DEBUG: Successfully fetched job, status: \(job.status)")
            guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

            var message = messages[index]
            message.content = job.stdout ?? message.content
            message.status = job.status == "success" ? .completed :
                job.status == "failed" ? .failed :
                job.status == "running" ? .running : .queued
            message.finishedAt = job.finishedAt
            message.errorMessage = job.stderr

            messages[index] = message
            messageStore.updateMessage(message)
        } catch let decodingError as DecodingError {
            print("DEBUG: Decoding error: \(decodingError)")
            errorMessage = "データ解析エラー: \(decodingError.localizedDescription)"
        } catch let apiError as APIError {
            print("DEBUG: API error: \(apiError)")
            errorMessage = apiError.localizedDescription
        } catch {
            print("DEBUG: Unknown error: \(error)")
            errorMessage = "不明なエラー: \(error.localizedDescription)"
        }
    }

    private func updateMessage(_ message: Message) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = message
        messageStore.updateMessage(message)
    }

    /// v4.1: Update runner dynamically without recreating the ViewModel
    /// This prevents "Request interrupted by user" errors when switching runners
    func updateRunner(_ newRunner: String) async {
        // 1. Same runner - no action needed
        guard newRunner != runner else { return }

        // 2. Cleanup all SSE connections
        for (jobId, manager) in sseConnections {
            manager.disconnect()
            sseCancellables.removeValue(forKey: jobId)?.forEach { $0.cancel() }
        }
        sseConnections.removeAll()

        // 3. Update runner
        runner = newRunner

        // 4. Update MessageStore context (v4.2: threadId必須)
        messageStore.setActiveContext(roomId: roomId, runner: newRunner, threadId: threadId ?? "default-thread")

        // 5. Clear current messages and reset pagination
        messages.removeAll()
        historyOffset = 0
        canLoadMoreHistory = true

        // 6. Reload messages for the new runner
        await loadLatestMessages()
    }

    func clearChat() {
        for (jobId, manager) in sseConnections {
            manager.disconnect()
            sseCancellables.removeValue(forKey: jobId)?.forEach { $0.cancel() }
        }
        sseConnections.removeAll()
        messages.removeAll()
        messageStore.clear()
        historyOffset = 0
        canLoadMoreHistory = true
    }

    deinit {
        for manager in sseConnections.values {
            manager.disconnect()
        }
    }
}
