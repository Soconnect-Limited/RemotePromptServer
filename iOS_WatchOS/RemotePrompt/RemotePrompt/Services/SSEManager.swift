import Combine
import Foundation

final class SSEManager: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var jobStatus: String = "queued"
    @Published var isConnected = false
    @Published var errorMessage: String?

    private var session: URLSession!
    private var buffer = Data()
    private var task: URLSessionDataTask?
    private var jobId: String?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.httpAdditionalHeaders = [
            "Accept": "text/event-stream",
        ]
        // Use main queue for delegate callbacks to avoid threading issues
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func connect(jobId: String) {
        self.jobId = jobId

        // 既存のタスクがあればキャンセル（isConnected状態は変更しない）
        task?.cancel()
        task = nil
        buffer.removeAll()

        guard let url = URL(string: "\(Constants.baseURL)/jobs/\(jobId)/stream") else {
            errorMessage = "無効なSSE URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")

        task = session.dataTask(with: request)
        print("DEBUG: SSEManager.connect() - Starting data task for job: \(jobId)")
        task?.resume()
        DispatchQueue.main.async {
            self.isConnected = true
            print("DEBUG: SSEManager.connect() - isConnected set to true")
        }
    }

    func disconnect() {
        print("DEBUG: SSEManager.disconnect() - Starting cleanup")
        task?.cancel()
        task = nil
        buffer.removeAll()

        // R-8.1.1: URLSession invalidate追加（強参照サイクル解消）
        // 各Job完了時にsessionをinvalidateし、delegateとの参照を切断
        session.invalidateAndCancel()
        print("DEBUG: SSEManager.disconnect() - URLSession invalidated")

        DispatchQueue.main.async {
            self.isConnected = false
            print("DEBUG: SSEManager.disconnect() - isConnected set to false")
        }
    }

    deinit {
        print("DEBUG: SSEManager deinit - Instance deallocated (URLSession already invalidated in disconnect())")
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        print("DEBUG: urlSession(didReceive:) called with \(data.count) bytes")
        buffer.append(data)
        guard let chunk = String(data: buffer, encoding: .utf8) else {
            print("SSE DEBUG: Failed to decode buffer as UTF-8")
            return
        }
        let events = chunk.components(separatedBy: "\n\n")
        print("SSE DEBUG: Received \(events.count) events")

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
                print("SSE DEBUG: Empty payload or failed to convert to data")
                continue
            }
            print("SSE DEBUG: Attempting to decode: \(dataPayload)")
            if let event = try? JSONDecoder().decode(JobStatusEvent.self, from: jsonData) {
                print("SSE DEBUG: Decoded event - status: \(event.status)")
                print("SSE DEBUG: Current jobStatus: '\(self.jobStatus)'")
                print("SSE DEBUG: Setting jobStatus to '\(event.status)'")
                self.jobStatus = event.status
                print("SSE DEBUG: jobStatus updated to '\(self.jobStatus)'")
            } else {
                print("SSE DEBUG: Failed to decode JSON")
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
