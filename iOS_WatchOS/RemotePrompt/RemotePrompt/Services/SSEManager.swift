import Combine
import Foundation

final class SSEManager: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var jobStatus: String = "queued"
    @Published var isConnected = false
    @Published var errorMessage: String?

    private var session: URLSession?
    private var buffer = Data()
    private var task: URLSessionDataTask?
    private var jobId: String?

    func connect(jobId: String) {
        self.jobId = jobId

        // 既存のタスクがあればキャンセル
        task?.cancel()
        task = nil
        buffer.removeAll()

        // R-8.1.1修正: connect()ごとに新しいURLSessionを生成
        // disconnect()で無効化されたsessionの再利用を回避
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.httpAdditionalHeaders = [
            "Accept": "text/event-stream",
        ]
        // delegateQueue: nilでバックグラウンドキュー使用（メインスレッドブロック回避）
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        print("DEBUG: SSEManager.connect() - Created new URLSession for job: \(jobId)")

        guard let url = URL(string: "\(Constants.baseURL)/jobs/\(jobId)/stream") else {
            errorMessage = "無効なSSE URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")

        task = session?.dataTask(with: request)
        print("DEBUG: SSEManager.connect() - Starting data task for job: \(jobId)")
        task?.resume()
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

        // R-8.1.1: URLSession invalidate追加（強参照サイクル解消）
        // 各Job完了時にsessionをinvalidateし、delegateとの参照を切断
        session?.invalidateAndCancel()
        session = nil
        print("DEBUG: SSEManager.disconnect() - URLSession invalidated and set to nil")

        DispatchQueue.main.async {
            self.isConnected = false
            print("DEBUG: SSEManager.disconnect() - isConnected set to false")
        }

#if DEBUG && MEMORY_METRICS
        if let jobId {
            MemoryMetrics.logRSS("SSE disconnect", extra: "job=\(jobId)")
        } else {
            MemoryMetrics.logRSS("SSE disconnect", extra: "job=nil")
        }
#endif
    }

    deinit {
        print("DEBUG: SSEManager deinit - Instance deallocated (URLSession already invalidated in disconnect())")
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        guard let chunk = String(data: buffer, encoding: .utf8) else {
            return
        }
        let events = chunk.components(separatedBy: "\n\n")

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
                DispatchQueue.main.async {
                    self.jobStatus = event.status
                }
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
        DispatchQueue.main.async {
            self.isConnected = false
            if let error = error {
                self.errorMessage = error.localizedDescription
            }
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
