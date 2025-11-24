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
    private var finalResultFetched: Set<String> = []  // ジョブごとの最終取得ガード（@MainActor 保護）
    private var terminalStatusReceived: Set<String> = []  // success/failed を受信済みのジョブ
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
        print("DEBUG: ChatViewModel init - roomId: \(roomId), threadId: \(threadId ?? "nil"), runner: \(runner)")
        print("DEBUG: ChatViewModel init - autoLoadMessages: \(autoLoadMessages), messages count: \(messages.count)")
        if autoLoadMessages {
            Task {
                print("DEBUG: ChatViewModel init - Starting autoLoadMessages Task")
                await loadLatestMessages()
                await recoverIncompleteJobs()
                print("DEBUG: ChatViewModel init - autoLoadMessages Task completed")
            }
        }
    }

    func loadLatestMessages() async {
        print("DEBUG: loadLatestMessages() - START")
        await fetchHistory(reset: true)
        print("DEBUG: loadLatestMessages() - COMPLETED")
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
            let combinedMessages: [Message]
            if reset {
                combinedMessages = historicalMessages
            } else {
                // R-8.6.1: Message ID重複排除（ForEach警告・UI凍結の原因）
                let existingIds = Set(messages.map { $0.id })
                let newMessages = historicalMessages.filter { !existingIds.contains($0.id) }
                let duplicateCount = historicalMessages.count - newMessages.count
                if duplicateCount > 0 {
                    print("DEBUG: fetchHistory() - Filtered \(duplicateCount) duplicate messages")
                }
                combinedMessages = newMessages + messages
            }

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
        print("DEBUG: recoverIncompleteJobs() - Found \(incomplete.count) incomplete jobs")

        for message in incomplete {
            guard let jobId = message.jobId else { continue }
            print("DEBUG: recoverIncompleteJobs() - Checking job: \(jobId)")
            do {
                let job = try await apiClient.fetchJob(id: jobId)
                print("DEBUG: recoverIncompleteJobs() - Job \(jobId) status: \(job.status)")
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
                    print("DEBUG: recoverIncompleteJobs() - Starting SSE for running job: \(jobId)")
                    startSSEStreaming(jobId: jobId, messageId: updated.id)
                }
            } catch {
                print("DEBUG: recoverIncompleteJobs() - Error fetching job \(jobId): \(error.localizedDescription)")
                guard let index = messages.firstIndex(where: { $0.id == message.id }) else { continue }
                var failed = messages[index]
                failed.status = .failed
                failed.errorMessage = "回復失敗: \(error.localizedDescription)"
                messages[index] = failed
                messageStore.updateMessage(failed)
            }
        }
        print("DEBUG: recoverIncompleteJobs() - Completed")
    }

    func sendMessage() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard ensureAPIKeyConfigured() else { return }

#if DEBUG && MEMORY_METRICS
        MemoryMetrics.logRSS("before sendMessage", extra: "messages=\(messages.count) sseConns=\(sseConnections.count)")
#endif

        print("DEBUG: sendMessage() - START")
        print("DEBUG: sendMessage() - messages.count: \(messages.count)")
        print("DEBUG: sendMessage() - Active SSE connections: \(sseConnections.keys.joined(separator: ", "))")
        print("DEBUG: sendMessage() - isLoading: \(isLoading)")

        inputText = ""
        isLoading = true
        print("DEBUG: sendMessage() - isLoading set to true")

        let userMessage = Message(
            roomId: roomId,
            type: .user,
            content: prompt,
            status: .sending
        )
        messages.append(userMessage)
        messageStore.addMessage(userMessage)

        Task {
            do {
                let response = try await apiClient.createJob(
                    runner: runner,
                    prompt: prompt,
                    deviceId: deviceId,
                    roomId: roomId,  // v3.0: Room ID
                    threadId: threadId  // v4.0: Thread ID (nil = use default thread)
                )
                print("DEBUG: Job created: \(response.id)")

#if DEBUG && MEMORY_METRICS
                MemoryMetrics.logRSS("after createJob", extra: "job=\(response.id)")
#endif

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

                // Job作成成功後、すぐに入力フィールドを有効化（推論中でも入力可能にする）
                isLoading = false
                print("DEBUG: sendMessage() - isLoading set to false after job creation")

                startSSEStreaming(jobId: response.id, messageId: assistantMessage.id)
            } catch {
                print("DEBUG: sendMessage() - Error: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                var failed = userMessage
                failed.status = .failed
                failed.errorMessage = error.localizedDescription
                updateMessage(failed)

                // エラー時も入力フィールドを有効化
                isLoading = false
                print("DEBUG: sendMessage() - isLoading set to false after error")
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
            print("DEBUG: startSSEStreaming() - Streaming disabled, fetching final result for job: \(jobId)")
            Task { @MainActor in
                await self.fetchFinalResult(jobId: jobId, messageId: messageId)
            }
            return
        }
        print("DEBUG: startSSEStreaming() - Starting SSE streaming for job \(jobId), messageId: \(messageId)")
        print("DEBUG: startSSEStreaming() - Current SSE connections: \(sseConnections.keys.joined(separator: ", "))")
        if let existing = sseConnections[jobId] {
            print("DEBUG: startSSEStreaming() - Disconnecting existing SSE connection for job: \(jobId)")
            existing.disconnect()
        }

        let manager = SSEManager()
        sseConnections[jobId] = manager

        // 新規ジョブ開始時に既存フラグをリセット
        finalResultFetched.remove(jobId)
        terminalStatusReceived.remove(jobId)

        // IMPORTANT: sseCancellablesに直接格納するためのSet を先に作成
        sseCancellables[jobId] = Set<AnyCancellable>()

        // IMPORTANT: 購読をconnect()の前に設定
        // SSEManagerは既にdelegateQueue: backgroundで動作し、@Published更新は内部でmain.asyncされるため、receive(on:)不要
        manager.$jobStatus
            .sink { [weak self] status in
                print("DEBUG: Received job status update: \(status)")
                self?.updateMessageStatus(messageId: messageId, status: status)

                // 終端ステータスで二重実行防止付きfetch
                guard let self else { return }
                if status == "success" || status == "failed" {
                    terminalStatusReceived.insert(jobId)
                    guard !self.finalResultFetched.contains(jobId) else {
                        print("DEBUG: Terminal status already fetched for job: \(jobId)")
                        return
                    }
                    self.finalResultFetched.insert(jobId)
                    Task { @MainActor in
                        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
                        self.cleanupConnection(for: jobId)
                    }
                }
            }
            .store(in: &sseCancellables[jobId]!)

        manager.$isConnected
            .dropFirst() // 初期値(false)をスキップ
            .sink { [weak self] connected in
                print("DEBUG: SSE connection status changed: \(connected)")
                guard let self else { return }
                if !connected {
                    print("DEBUG: SSE disconnected")
                    // Terminal statusを受信せず、まだフェッチしていない場合のみ実行
                    guard !self.terminalStatusReceived.contains(jobId) else {
                        print("DEBUG: Terminal status already received for job: \(jobId)")
                        return
                    }
                    guard !self.finalResultFetched.contains(jobId) else {
                        print("DEBUG: Final result already fetched/scheduled for job: \(jobId)")
                        return
                    }
                    self.finalResultFetched.insert(jobId)
                    Task { @MainActor in
                        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
                        self.cleanupConnection(for: jobId)
                    }
                }
            }
            .store(in: &sseCancellables[jobId]!)

        manager.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                print("DEBUG: SSE error: \(message)")
                self?.errorMessage = message
            }
            .store(in: &sseCancellables[jobId]!)

        // 購読設定後にconnect()を呼び出す
        manager.connect(jobId: jobId)
    }

    private func cleanupConnection(for jobId: String) {
        let hasConnection = sseConnections[jobId] != nil
        let hasCancellables = sseCancellables[jobId] != nil

        print("DEBUG: cleanupConnection() - jobId: \(jobId), hasConnection: \(hasConnection), hasCancellables: \(hasCancellables)")
        print("DEBUG: cleanupConnection() - Before cleanup - sseConnections.count: \(sseConnections.count), sseCancellables.count: \(sseCancellables.count)")

        guard hasConnection || hasCancellables else {
            print("DEBUG: cleanupConnection() - Connection for \(jobId) already cleaned up")
            return
        }

        // SSE接続とCombine購読を両方クリーンアップ
        if let manager = sseConnections[jobId] {
            manager.disconnect()
            print("DEBUG: cleanupConnection() - SSEManager.disconnect() called")
        }

        sseConnections.removeValue(forKey: jobId)
        sseCancellables.removeValue(forKey: jobId)?.forEach { $0.cancel() }
        finalResultFetched.remove(jobId)
        terminalStatusReceived.remove(jobId)

        // finalResultFetchedはTask内のdeferで管理するため、ここでは削除しない
        // （Step 1.1/1.2のdeferが責務を持つ）
        print("DEBUG: cleanupConnection() - finalResultFetched managed by caller's defer")

        print("DEBUG: cleanupConnection() - After cleanup - sseConnections.count: \(sseConnections.count), sseCancellables.count: \(sseCancellables.count)")

#if DEBUG && MEMORY_METRICS
        MemoryMetrics.logRSS("after cleanup", extra: "messages=\(messages.count) sseConns=\(sseConnections.count)")
#endif
    }

    private func updateMessageStatus(messageId: String, status: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
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

#if DEBUG && MEMORY_METRICS
            MemoryMetrics.logRSS("after fetchFinalResult", extra: "job=\(jobId) contentLen=\(message.content.count)")
#endif
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

    func cancelInference() {
        print("DEBUG: cancelInference() - Cancelling all running jobs")
        print("DEBUG: cancelInference() - Active SSE connections: \(sseConnections.keys.joined(separator: ", "))")

        guard !sseConnections.isEmpty else {
            print("DEBUG: cancelInference() - No active jobs to cancel")
            return
        }

        // 実行中のJobを全てキャンセル（SSE接続を切断し、ローカルでキャンセル状態にする）
        for (jobId, manager) in sseConnections {
            print("DEBUG: cancelInference() - Cancelling job: \(jobId)")

            // SSE接続を切断
            manager.disconnect()

            // メッセージをキャンセル状態に更新
            if let index = messages.firstIndex(where: { $0.jobId == jobId }) {
                var cancelledMessage = messages[index]
                cancelledMessage.status = .failed
                cancelledMessage.errorMessage = "ユーザーによりキャンセルされました"
                cancelledMessage.finishedAt = Date()
                messages[index] = cancelledMessage
                messageStore.updateMessage(cancelledMessage)
                print("DEBUG: cancelInference() - Message \(cancelledMessage.id) marked as cancelled")
            }
        }

        // 接続をクリーンアップ
        cleanupAllConnections()
        print("DEBUG: cancelInference() - All jobs cancelled")
    }

    private func cleanupAllConnections() {
        sseConnections.removeAll()
        sseCancellables.removeAll()
    }

    deinit {
        for manager in sseConnections.values {
            manager.disconnect()
        }
    }
}
