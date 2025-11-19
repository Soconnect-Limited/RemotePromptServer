import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient = APIClient.shared
    private let messageStore = MessageStore()
    private var sseConnections: [String: SSEManager] = [:]
    private var sseCancellables: [String: Set<AnyCancellable>] = [:]
    private let runner: String

    init(runner: String = "claude") {
        self.runner = runner
        loadMessages()
        Task {
            await recoverIncompleteJobs()
        }
    }

    func loadMessages() {
        messages = messageStore.messages
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
                    deviceId: APIClient.getDeviceId()
                )

                var updatedUser = userMessage
                updatedUser.status = .completed
                updatedUser.finishedAt = Date()
                updateMessage(updatedUser)

                let assistantMessage = Message(
                    jobId: response.id,
                    type: .assistant,
                    content: "",
                    status: .queued
                )
                messages.append(assistantMessage)
                messageStore.addMessage(assistantMessage)

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
        guard Constants.isAPIKeyConfigured else {
            errorMessage = Constants.missingAPIKeyMessage
            return false
        }
        return true
    }

    private func startSSEStreaming(jobId: String, messageId: String) {
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

    func clearChat() {
        for (jobId, manager) in sseConnections {
            manager.disconnect()
            sseCancellables.removeValue(forKey: jobId)?.forEach { $0.cancel() }
        }
        sseConnections.removeAll()
        messages.removeAll()
        messageStore.clearAll()
    }

    deinit {
        for manager in sseConnections.values {
            manager.disconnect()
        }
    }
}
