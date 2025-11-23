import Combine
import Foundation

#if canImport(UIKit)
import UIKit
#endif

final class SSEManager: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var jobStatus: String = "queued"
    @Published var isConnected = false
    @Published var errorMessage: String?

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

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // heartbeat 30s + 余裕30s
        config.httpAdditionalHeaders = [
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache",
            "Accept-Encoding": "identity",
        ]
        // バックグラウンドキュー使用（メインスレッドブロック回避）
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        print("DEBUG: SSEManager.init() - Created URLSession with background delegateQueue")
    }

    func connect(jobId: String) {
        self.jobId = jobId

        // セッションが無効な場合は再生成（長時間接続後のフォールバック）
        if session == nil {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.httpAdditionalHeaders = [
                "Accept": "text/event-stream",
                "Cache-Control": "no-cache",
                "Accept-Encoding": "identity",
            ]
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .userInitiated
            session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            print("DEBUG: SSEManager.connect() - Recreated URLSession")
        }

        // 既存のタスクがあればキャンセル
        task?.cancel()
        task = nil
        buffer.removeAll()

        print("DEBUG: SSEManager.connect() - Reusing existing URLSession for job: \(jobId)")

        guard let url = URL(string: "\(Constants.baseURL)/jobs/\(jobId)/stream") else {
            DispatchQueue.main.async {
                self.errorMessage = "無効なSSE URL"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 60.0

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
        let thread = OperationQueue.current == OperationQueue.main ? "main" : "bg"
        print("DEBUG: [SSE-DATA] received: \(data.count) bytes, bufferSize: \(buffer.count) bytes [thread:\(thread)]")

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
        print("DEBUG: [SSE-EVENTS] parsed \(events.count) event blocks from buffer")

        for index in 0..<(events.count - 1) {
            let eventBlock = events[index]
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
                print("DEBUG: [SSE-DECODE] SUCCESS - status: \(event.status)")
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

        // バックグラウンドスレッドから実行されるため、メインスレッドで更新
        DispatchQueue.main.async {
            self.isConnected = false
            if let error = error {
                self.errorMessage = error.localizedDescription
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
