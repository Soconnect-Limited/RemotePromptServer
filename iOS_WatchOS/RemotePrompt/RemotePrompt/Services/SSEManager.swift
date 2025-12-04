import Combine
import Foundation
import Security

#if canImport(UIKit)
import UIKit
#endif

final class SSEManager: NSObject, ObservableObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    @Published var jobStatus: String = "queued"
    @Published var isConnected = false
    @Published var errorMessage: String?

    /// 証明書変更イベント受信時のコールバック
    var onCertificateChanged: ((CertificateChangedEvent) -> Void)?

    /// 証明書失効イベント受信時のコールバック
    var onCertificateRevoked: ((CertificateRevokedEvent) -> Void)?

    /// 証明書モード変更イベント受信時のコールバック
    var onCertificateModeChanged: ((CertificateModeChangedEvent) -> Void)?

    enum SSEState: String {
        case idle
        case connecting
        case responseReceived
        case receiving
        case success
        case failed
        case disconnected
    }

    private var session: URLSession?
    private var delegateQueue: OperationQueue? {
        if Constants.useMainDelegateQueue {
            return .main
        } else {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .userInitiated
            return queue
        }
    }
    private var buffer = Data()
    private var task: URLSessionDataTask?
    private var jobId: String?
    private var sseState: SSEState = .idle {
        didSet {
            let thread = OperationQueue.current == OperationQueue.main ? "main" : "bg"
            print("DEBUG: [SSE-STATE] \(oldValue.rawValue) → \(sseState.rawValue) [thread:\(thread)] job=\(jobId ?? "nil")")
        }
    }

    private let MAX_BUFFER_SIZE = 1_048_576  // 1MB

    // MARK: - Certificate Pinning
    private let pinningDelegate = CertificatePinningDelegate.shared
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        createSession()
        print("DEBUG: SSEManager.init() - Created URLSession with \(Constants.useMainDelegateQueue ? "main" : "bg") delegateQueue")

        // 設定変更を監視してセッション再生成
        NotificationCenter.default.publisher(for: .serverConfigurationChanged)
            .sink { [weak self] _ in
                self?.recreateSession()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .certificateTrustChanged)
            .sink { [weak self] _ in
                self?.recreateSession()
            }
            .store(in: &cancellables)
    }

    private func createSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 7200  // 2時間（長い推論時間に対応）
        config.httpAdditionalHeaders = [
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache",
            "Accept-Encoding": "identity",
        ]
        session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }

    private func recreateSession() {
        session?.invalidateAndCancel()
        createSession()
        print("DEBUG: SSEManager - Session recreated due to configuration change")
    }

    /// 現在の接続先URLインデックス（フォールバック用）
    private var currentURLIndex = 0

    func connect(jobId: String) {
        self.jobId = jobId
        currentURLIndex = 0
        connectToNextURL(jobId: jobId)
    }

    private func connectToNextURL(jobId: String) {
        let allURLs = Constants.allURLs
        guard currentURLIndex < allURLs.count else {
            DispatchQueue.main.async {
                self.errorMessage = L10n.Connection.failedAll
            }
            return
        }

        let baseURL = allURLs[currentURLIndex]

        // セッションが無効な場合は再生成（長時間接続後のフォールバック）
        if session == nil || !Constants.reuseSSESession {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 7200
            config.httpAdditionalHeaders = [
                "Accept": "text/event-stream",
                "Cache-Control": "no-cache",
                "Accept-Encoding": "identity",
            ]
            session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
            print("DEBUG: SSEManager.connect() - Recreated URLSession (\(Constants.useMainDelegateQueue ? "main" : "bg"))")
        }

        // 既存のタスクがあればキャンセル
        task?.cancel()
        task = nil
        buffer.removeAll()

        if currentURLIndex > 0 {
            print("DEBUG: SSEManager.connect() - Fallback to: \(baseURL)")
        } else {
            print("DEBUG: SSEManager.connect() - Connecting to: \(baseURL)")
        }

        guard let url = URL(string: "\(baseURL)/jobs/\(jobId)/stream") else {
            currentURLIndex += 1
            connectToNextURL(jobId: jobId)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 7200.0

        task = session?.dataTask(with: request)
        print("DEBUG: SSEManager.connect() - Starting data task for job: \(jobId)")
        task?.resume()
        sseState = .connecting
        // バックグラウンドスレッドから実行されるため、メインスレッドで更新
        DispatchQueue.main.async {
            self.isConnected = true
            print("DEBUG: SSEManager.connect() - isConnected set to true")
        }

#if DEBUG && MEMORY_METRICS
        MemoryMetrics.logRSS("SSE connect", extra: "job=\(jobId)")
#endif
    }

    func disconnect() {
        print("DEBUG: SSEManager.disconnect() - Starting cleanup")
        task?.cancel()
        task = nil
        buffer.removeAll()

        // sessionは再利用するためinvalidateしない（deinitで実施）
        print("DEBUG: SSEManager.disconnect() - Task cancelled, session kept for reuse")

        // バックグラウンドスレッドから実行されるため、メインスレッドで更新
        DispatchQueue.main.async {
            self.isConnected = false
            print("DEBUG: SSEManager.disconnect() - isConnected set to false")
        }
        sseState = .disconnected

#if DEBUG && MEMORY_METRICS
        if let jobId {
            MemoryMetrics.logRSS("SSE disconnect", extra: "job=\(jobId)")
        } else {
            MemoryMetrics.logRSS("SSE disconnect", extra: "job=nil")
        }
#endif
    }

    deinit {
        session?.invalidateAndCancel()
        print("DEBUG: SSEManager deinit - Instance deallocated, URLSession invalidated")
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if Constants.enableVerboseLogs {
            let thread = OperationQueue.current == OperationQueue.main ? "main" : "bg"
            print("DEBUG: [SSE-DATA] received: \(data.count) bytes, bufferSize: \(buffer.count) bytes [thread:\(thread)]")
        }

        if buffer.count + data.count > MAX_BUFFER_SIZE {
            print("DEBUG: [SSE-BUFFER] LIMIT EXCEEDED! current=\(buffer.count) incoming=\(data.count) max=\(MAX_BUFFER_SIZE)")
            print("DEBUG: [SSE-BUFFER] Clearing buffer and discarding incoming data")
            buffer.removeAll()
            return
        }

        buffer.append(data)
        guard let chunk = String(data: buffer, encoding: .utf8) else {
            print("DEBUG: [SSE-DATA] Failed to decode buffer as UTF-8")
            return
        }
        let events = chunk.components(separatedBy: "\n\n")
        if Constants.enableVerboseLogs {
            print("DEBUG: [SSE-EVENTS] parsed \(events.count) event blocks from buffer")
        }

        for index in 0..<(events.count - 1) {
            let eventBlock = events[index]

            // 証明書関連イベントをチェック
            if eventBlock.contains("event:") {
                parseCertificateEvent(from: eventBlock)
            }

            let dataPayload = eventBlock
                .split(separator: "\n")
                .compactMap { line -> String? in
                    guard line.hasPrefix("data:") else { return nil }
                    let trimmed = line.dropFirst("data:".count)
                    if trimmed.first == " " {
                        return String(trimmed.dropFirst())
                    }
                    return String(trimmed)
                }
                .joined()

            guard !dataPayload.isEmpty, let jsonData = dataPayload.data(using: .utf8) else {
                continue
            }
            if let event = try? JSONDecoder().decode(JobStatusEvent.self, from: jsonData) {
                if Constants.enableVerboseLogs {
                    print("DEBUG: [SSE-DECODE] SUCCESS - status: \(event.status)")
                }
                DispatchQueue.main.async {
                    self.jobStatus = event.status
                }
                if sseState == .responseReceived {
                    sseState = .receiving
                }
            } else {
                print("DEBUG: [SSE-DECODE] FAILED - payload: \(dataPayload)")
            }
        }

        if let trailing = events.last, !trailing.isEmpty {
            buffer = Data(trailing.utf8)
        } else {
            buffer.removeAll()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("DEBUG: urlSession(didCompleteWithError:) called - error: \(error?.localizedDescription ?? "nil")")

        // セッションが無効化された場合は再生成フラグ
        if let error = error as NSError?,
           error.domain == NSURLErrorDomain,
           error.code == NSURLErrorNetworkConnectionLost {
            print("DEBUG: URLSession invalidated, will recreate in next connect()")
            self.session?.invalidateAndCancel()
            self.session = nil  // 次回connect()で再生成
        }

        // 接続エラー時にフォールバックを試す
        if let error = error as NSError?,
           error.domain == NSURLErrorDomain,
           let jobId = self.jobId {
            // ネットワークエラーの場合、次のURLを試す
            let fallbackCodes = [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorSecureConnectionFailed,
            ]
            if fallbackCodes.contains(error.code) && currentURLIndex + 1 < Constants.allURLs.count {
                print("DEBUG: SSE connection failed, trying fallback URL...")
                currentURLIndex += 1
                connectToNextURL(jobId: jobId)
                return
            }
        }

        // バックグラウンドスレッドから実行されるため、メインスレッドで更新
        DispatchQueue.main.async {
            self.isConnected = false
            if let error = error {
                let nsError = error as NSError
                // バックグラウンド移行による切断は無視（処理はサーバー側で継続）
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNetworkConnectionLost {
                    print("DEBUG: Ignoring network connection lost (background transition)")
                } else {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        if error == nil {
            sseState = .success
        } else {
            sseState = .failed
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        sseState = .responseReceived
        completionHandler(.allow)
    }

    // MARK: - URLSessionDelegate (Certificate Pinning)

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // CertificatePinningDelegateに委譲
        pinningDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    // MARK: - Certificate Event Notifications

    /// 証明書変更通知
    static let certificateChangedNotification = Notification.Name("SSECertificateChanged")
    /// 証明書失効通知
    static let certificateRevokedNotification = Notification.Name("SSECertificateRevoked")
    /// 証明書モード変更通知
    static let certificateModeChangedNotification = Notification.Name("SSECertificateModeChanged")

    // MARK: - Certificate Event Parsing

    /// SSEイベントから証明書関連イベントをパース
    private func parseCertificateEvent(from eventBlock: String) {
        // イベント名を取得
        var eventName: String?
        var dataPayload: String = ""

        for line in eventBlock.split(separator: "\n") {
            let lineStr = String(line)
            if lineStr.hasPrefix("event:") {
                eventName = String(lineStr.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            } else if lineStr.hasPrefix("data:") {
                let data = String(lineStr.dropFirst("data:".count))
                if data.first == " " {
                    dataPayload += String(data.dropFirst())
                } else {
                    dataPayload += data
                }
            }
        }

        guard let eventName = eventName, !dataPayload.isEmpty,
              let jsonData = dataPayload.data(using: .utf8) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch eventName {
        case "certificate_changed":
            if let event = try? decoder.decode(CertificateChangedEvent.self, from: jsonData) {
                print("[SSEManager] Received certificate_changed event")
                DispatchQueue.main.async {
                    self.onCertificateChanged?(event)
                    // 信頼状態をリセット
                    if var config = ServerConfigurationStore.shared.currentConfiguration {
                        config.isTrusted = false
                        ServerConfigurationStore.shared.save(config)
                    }
                    // NotificationCenterで通知
                    NotificationCenter.default.post(
                        name: SSEManager.certificateChangedNotification,
                        object: event
                    )
                }
            }

        case "certificate_revoked":
            if let event = try? decoder.decode(CertificateRevokedEvent.self, from: jsonData) {
                print("[SSEManager] Received certificate_revoked event")
                DispatchQueue.main.async {
                    self.onCertificateRevoked?(event)
                    // 証明書をクリアして接続切断
                    ServerConfigurationStore.shared.clearTrustedCertificate()
                    self.disconnect()
                    // NotificationCenterで通知
                    NotificationCenter.default.post(
                        name: SSEManager.certificateRevokedNotification,
                        object: event
                    )
                }
            }

        case "certificate_mode_changed":
            if let event = try? decoder.decode(CertificateModeChangedEvent.self, from: jsonData) {
                print("[SSEManager] Received certificate_mode_changed event")
                DispatchQueue.main.async {
                    self.onCertificateModeChanged?(event)
                    // 信頼状態をリセット
                    if var config = ServerConfigurationStore.shared.currentConfiguration {
                        config.isTrusted = false
                        ServerConfigurationStore.shared.save(config)
                    }
                    // NotificationCenterで通知
                    NotificationCenter.default.post(
                        name: SSEManager.certificateModeChangedNotification,
                        object: event
                    )
                }
            }

        default:
            break
        }
    }
}

struct JobStatusEvent: Codable {
    let status: String
    let startedAt: String?
    let finishedAt: String?
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case exitCode = "exit_code"
    }
}
