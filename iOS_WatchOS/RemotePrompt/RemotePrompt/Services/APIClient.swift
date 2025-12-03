import Foundation
import Combine

enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(Int)
    case missingAPIKey
    case certificateError(String)
    case serverNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .httpError(let code):
            return "サーバーエラー(\(code))"
        case .missingAPIKey:
            return "APIキーが未設定です。サーバー設定を確認してください。"
        case .certificateError(let message):
            return "証明書エラー: \(message)"
        case .serverNotConfigured:
            return "サーバーが設定されていません。設定画面からサーバーを追加してください。"
        }
    }
}

struct CreateJobRequest: Codable {
    let runner: String
    let inputText: String
    let deviceId: String
    let roomId: String
    let notifyToken: String?
    let threadId: String?

    enum CodingKeys: String, CodingKey {
        case runner
        case inputText = "input_text"
        case deviceId = "device_id"
        case roomId = "room_id"
        case notifyToken = "notify_token"
        case threadId = "thread_id"
    }
}

struct CreateJobResponse: Codable {
    let id: String
    let runner: String
    let status: String
}

protocol APIClientProtocol {
    func fetchJob(id: String) async throws -> Job
    func createJob(runner: String, prompt: String, deviceId: String, roomId: String, threadId: String?) async throws -> CreateJobResponse
    func fetchRooms(deviceId: String) async throws -> [Room]
    func createRoom(name: String, workspacePath: String, deviceId: String, icon: String) async throws -> Room
    func updateRoom(roomId: String, name: String, workspacePath: String, deviceId: String, icon: String) async throws -> Room
    func deleteRoom(roomId: String, deviceId: String) async throws
    func reorderRooms(deviceId: String, roomIds: [String]) async throws
    func fetchMessages(
        deviceId: String,
        roomId: String,
        runner: String,
        threadId: String?,
        limit: Int,
        offset: Int
    ) async throws -> [Job]
    func getRoomSettings(roomId: String, deviceId: String) async throws -> RoomSettings?
    func updateRoomSettings(roomId: String, deviceId: String, settings: RoomSettings?) async throws -> RoomSettings?

    // Thread Management v4.2: runner パラメータ削除
    func fetchThreads(roomId: String, deviceId: String) async throws -> [Thread]
    func createThread(roomId: String, name: String, deviceId: String) async throws -> Thread
    func updateThread(threadId: String, name: String, deviceId: String) async throws -> Thread
    func deleteThread(threadId: String, deviceId: String) async throws
    // v4.3.1: 既読API（runner指定オプション）
    func markThreadAsRead(threadId: String, deviceId: String, runner: String?) async throws -> Thread
    // v4.3.2: 未読数取得API
    func getUnreadCount(deviceId: String) async throws -> Int
}

final class APIClient: APIClientProtocol {
    static let shared = APIClient()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Certificate Pinning Session
    private var pinnedSession: URLSession?
    private let pinningDelegate = CertificatePinningDelegate.shared
    private var cancellables = Set<AnyCancellable>()

    /// 証明書エラー発生時のコールバック
    var onCertificateError: ((String) -> Void)?

    /// 新規証明書検出時のコールバック
    var onNewCertificate: ((String, Data, @escaping (Bool) -> Void) -> Void)? {
        didSet {
            pinningDelegate.onNewCertificateDetected = onNewCertificate
        }
    }

    /// 証明書不一致時のコールバック
    var onCertificateMismatch: ((String, String, @escaping (Bool) -> Void) -> Void)? {
        didSet {
            pinningDelegate.onCertificateMismatchDetected = onCertificateMismatch
        }
    }

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Use DateFormatter for Python's ISO8601 format with microseconds
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

            if let date = formatter.date(from: dateString) {
                return date
            }

            // Fallback to milliseconds (3 digits)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Fallback to no fractional seconds
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        // 設定変更を監視してセッション再生成
        NotificationCenter.default.publisher(for: .serverConfigurationChanged)
            .sink { [weak self] _ in
                self?.invalidateSession()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .certificateTrustChanged)
            .sink { [weak self] _ in
                self?.invalidateSession()
            }
            .store(in: &cancellables)
    }

    // MARK: - Session Management

    /// 自己署名証明書対応のURLSessionを取得
    private func getSession() -> URLSession {
        if let session = pinnedSession {
            return session
        }

        print("[APIClient] Creating session with self-signed certificate support")
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60

        // HTTP/2を無効化（自己署名証明書との互換性向上）
        config.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate"]

        // ローカルネットワーク向けの最適化
        config.waitsForConnectivity = false
        config.shouldUseExtendedBackgroundIdleMode = false

        // TLS設定を最適化（自己署名証明書用）
        // OCSP/CRL検証を無効化（自己署名証明書にはOCSPサーバーがない）
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13

        // 自己署名証明書対応のdelegateを使用
        // delegateQueue = nil でシステムデフォルトのシリアルキューを使用
        let session = URLSession(configuration: config, delegate: pinningDelegate, delegateQueue: nil)
        pinnedSession = session
        return session
    }

    /// 他のサービスからも使用可能な共有セッション
    var sharedSession: URLSession {
        getSession()
    }

    /// セッションを無効化（設定変更時に呼び出し）
    func invalidateSession() {
        pinnedSession?.invalidateAndCancel()
        pinnedSession = nil
        print("[APIClient] Session invalidated due to configuration change")
    }

    // MARK: - Fallback Request Execution

    /// フォールバック付きでリクエストを実行
    /// - Parameters:
    ///   - path: APIパス（例: "/rooms"）
    ///   - queryItems: クエリパラメータ
    ///   - method: HTTPメソッド
    ///   - body: リクエストボディ（POSTなど）
    /// - Returns: レスポンスデータ
    private func executeWithFallback(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        let allURLs = Constants.allURLs
        print("[APIClient] executeWithFallback: allURLs=\(allURLs), autoFallback=\(Constants.autoFallbackEnabled)")
        guard !allURLs.isEmpty else {
            throw APIError.serverNotConfigured
        }

        guard let apiKey = Constants.apiKey else {
            throw APIError.missingAPIKey
        }

        var lastError: Error = APIError.invalidURL

        for (index, baseURL) in allURLs.enumerated() {
            do {
                var components = URLComponents(string: "\(baseURL)\(path)")
                components?.queryItems = queryItems

                guard let url = components?.url else {
                    continue
                }

                var request = URLRequest(url: url)
                request.httpMethod = method
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                if let body = body {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = body
                }

                if index > 0 {
                    print("[APIClient] Fallback to: \(baseURL)")
                }

                let (data, response) = try await getSession().data(for: request)

                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw APIError.httpError(code)
                }

                // 成功したURLを記録（次回優先）
                if index > 0 {
                    print("[APIClient] ✅ Fallback succeeded: \(baseURL)")
                }

                return data
            } catch {
                lastError = error
                print("[APIClient] Request failed for \(baseURL): \(error.localizedDescription)")

                // 認証エラーはフォールバックしない（全URLで同じAPIキーを使うため）
                if case APIError.httpError(401) = error {
                    throw error
                }
                if case APIError.httpError(403) = error {
                    throw error
                }

                // 次のURLを試す
                continue
            }
        }

        throw lastError
    }

    /// フォールバック付きでリクエストを実行（dataTask版 - fetchRooms用）
    private func executeWithFallbackDataTask(
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> Data {
        // デバッグ: 設定内容を詳細出力
        if let config = ServerConfigurationStore.shared.currentConfiguration {
            print("[APIClient] config.url=\(config.url)")
            print("[APIClient] config.alternativeURLs=\(config.alternativeURLs)")
            print("[APIClient] config.autoFallback=\(config.autoFallback)")
        } else {
            print("[APIClient] currentConfiguration is nil")
        }
        let allURLs = Constants.allURLs
        print("[APIClient] executeWithFallbackDataTask: allURLs=\(allURLs), autoFallback=\(Constants.autoFallbackEnabled)")
        guard !allURLs.isEmpty else {
            throw APIError.serverNotConfigured
        }

        guard let apiKey = Constants.apiKey else {
            throw APIError.missingAPIKey
        }

        var lastError: Error = APIError.invalidURL

        for (index, baseURL) in allURLs.enumerated() {
            do {
                var components = URLComponents(string: "\(baseURL)\(path)")
                components?.queryItems = queryItems

                guard let url = components?.url else {
                    continue
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

                if index > 0 {
                    print("[APIClient] Fallback to: \(baseURL)")
                }

                let session = getSession()
                let result: (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                    session.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let data = data, let response = response {
                            continuation.resume(returning: (data, response))
                        } else {
                            continuation.resume(throwing: APIError.invalidURL)
                        }
                    }.resume()
                }

                let (data, response) = result

                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw APIError.httpError(code)
                }

                if index > 0 {
                    print("[APIClient] ✅ Fallback succeeded: \(baseURL)")
                }

                return data
            } catch {
                lastError = error
                print("[APIClient] Request failed for \(baseURL): \(error.localizedDescription)")

                if case APIError.httpError(401) = error { throw error }
                if case APIError.httpError(403) = error { throw error }

                continue
            }
        }

        throw lastError
    }

    /// 接続のウォームアップ（現在は無効化）
    /// 注意: 共有URLSessionを使用するとメインのリクエストをブロックする問題があるため無効化
    func warmupConnection() {
        // ウォームアップは現在無効化されています
        // サーバーは十分高速なので不要
    }

    /// 証明書バイパスモードの設定（接続テスト用）
    func setBypassValidation(_ bypass: Bool) {
        pinningDelegate.bypassValidation = bypass
    }

    func fetchJob(id: String) async throws -> Job {
        let data = try await executeWithFallback(path: "/jobs/\(id)")
        return try decoder.decode(Job.self, from: data)
    }

    func createJob(runner: String, prompt: String, deviceId: String, roomId: String, threadId: String? = nil) async throws -> CreateJobResponse {
        // Get APNs device token from UserDefaults
        let notifyToken = UserDefaults.standard.string(forKey: "apns_device_token")

        let payload = CreateJobRequest(
            runner: runner,
            inputText: prompt,
            deviceId: deviceId,
            roomId: roomId,
            notifyToken: notifyToken,
            threadId: threadId  // v4.0: nilの場合は互換モードでデフォルトスレッド使用
        )
        let body = try encoder.encode(payload)
        let data = try await executeWithFallback(path: "/jobs", method: "POST", body: body)
        return try decoder.decode(CreateJobResponse.self, from: data)
    }

    func getRoomSettings(roomId: String, deviceId: String) async throws -> RoomSettings? {
        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        let data = try await executeWithFallback(path: "/rooms/\(roomId)/settings", queryItems: queryItems)
        struct SettingsResponse: Codable {
            let roomId: String
            let settings: RoomSettings?
            enum CodingKeys: String, CodingKey {
                case roomId = "room_id"
                case settings
            }
        }
        let decoded = try decoder.decode(SettingsResponse.self, from: data)
        return decoded.settings
    }

    func updateRoomSettings(roomId: String, deviceId: String, settings: RoomSettings?) async throws -> RoomSettings? {
        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        let body: Data
        if let settings = settings {
            body = try encoder.encode(settings)
        } else {
            body = Data("null".utf8)
        }

        let data = try await executeWithFallback(path: "/rooms/\(roomId)/settings", queryItems: queryItems, method: "PUT", body: body)
        struct SettingsResponse: Codable {
            let roomId: String
            let settings: RoomSettings?
            enum CodingKeys: String, CodingKey {
                case roomId = "room_id"
                case settings
            }
        }
        let decoded = try decoder.decode(SettingsResponse.self, from: data)
        return decoded.settings
    }

    // MARK: - Room Management

    func fetchRooms(deviceId: String) async throws -> [Room] {
        let startTime = Date()
        print("[APIClient] fetchRooms START")

        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        let data = try await executeWithFallbackDataTask(path: "/rooms", queryItems: queryItems)

        let elapsed = Date().timeIntervalSince(startTime)
        print("[APIClient] fetchRooms DONE in \(String(format: "%.2f", elapsed))s")

        return try decoder.decode([Room].self, from: data)
    }

    func createRoom(name: String, workspacePath: String, deviceId: String, icon: String = "folder") async throws -> Room {
        let payload: [String: String] = [
            "device_id": deviceId,
            "name": name,
            "workspace_path": workspacePath,
            "icon": icon
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await executeWithFallback(path: "/rooms", method: "POST", body: body)
        return try decoder.decode(Room.self, from: data)
    }

    func updateRoom(roomId: String, name: String, workspacePath: String, deviceId: String, icon: String = "folder") async throws -> Room {
        let payload: [String: String] = [
            "device_id": deviceId,
            "name": name,
            "workspace_path": workspacePath,
            "icon": icon
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await executeWithFallback(path: "/rooms/\(roomId)", method: "PUT", body: body)
        return try decoder.decode(Room.self, from: data)
    }

    func deleteRoom(roomId: String, deviceId: String) async throws {
        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        _ = try await executeWithFallback(path: "/rooms/\(roomId)", queryItems: queryItems, method: "DELETE")
    }

    func reorderRooms(deviceId: String, roomIds: [String]) async throws {
        let payload: [String: Any] = [
            "device_id": deviceId,
            "room_ids": roomIds
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await executeWithFallback(path: "/rooms/reorder", method: "PUT", body: body)
    }

    func fetchMessages(
        deviceId: String,
        roomId: String,
        runner: String,
        threadId: String? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [Job] {
        var queryItems = [
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "room_id", value: roomId),
            URLQueryItem(name: "runner", value: runner),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let threadId = threadId {
            queryItems.append(URLQueryItem(name: "thread_id", value: threadId))
        }

        let data = try await executeWithFallback(path: "/messages", queryItems: queryItems)
        return try decoder.decode([Job].self, from: data)
    }

    /// デバイスIDを取得（Keychainに永続保存、アプリ再インストールでも保持）
    static func getDeviceId() -> String {
        let keychainKey = "device_id"
        let userDefaultsKey = "remote_prompt_device_id"

        // 1. Keychainから取得を試みる
        if let saved = KeychainHelper.get(key: keychainKey) {
            return saved
        }

        // 2. UserDefaultsからの移行（既存ユーザー対応）
        if let legacy = UserDefaults.standard.string(forKey: userDefaultsKey) {
            KeychainHelper.set(key: keychainKey, value: legacy)
            // 移行後もUserDefaultsは残す（バックアップとして）
            return legacy
        }

        // 3. 新規生成してKeychainに保存
        let newId = UUID().uuidString
        KeychainHelper.set(key: keychainKey, value: newId)
        // バックアップとしてUserDefaultsにも保存
        UserDefaults.standard.set(newId, forKey: userDefaultsKey)
        return newId
    }

    // MARK: - Thread Management

    /// v4.2: runner パラメータ削除（全Thread取得、クライアント側でフィルタ）
    func fetchThreads(roomId: String, deviceId: String) async throws -> [Thread] {
        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        let data = try await executeWithFallback(path: "/rooms/\(roomId)/threads", queryItems: queryItems)
        return try decoder.decode([Thread].self, from: data)
    }

    /// v4.2: runner パラメータ削除（Thread作成時にrunner指定不要）
    func createThread(roomId: String, name: String, deviceId: String) async throws -> Thread {
        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        let payload = CreateThreadRequest(name: name)
        let body = try encoder.encode(payload)
        let data = try await executeWithFallback(path: "/rooms/\(roomId)/threads", queryItems: queryItems, method: "POST", body: body)
        return try decoder.decode(Thread.self, from: data)
    }

    func updateThread(threadId: String, name: String, deviceId: String) async throws -> Thread {
        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        let payload = UpdateThreadRequest(name: name)
        let body = try encoder.encode(payload)
        let data = try await executeWithFallback(path: "/threads/\(threadId)", queryItems: queryItems, method: "PATCH", body: body)
        return try decoder.decode(Thread.self, from: data)
    }

    func deleteThread(threadId: String, deviceId: String) async throws {
        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        _ = try await executeWithFallback(path: "/threads/\(threadId)", queryItems: queryItems, method: "DELETE")
    }

    /// v4.3.1: スレッドを既読としてマークする（runner指定オプション）
    func markThreadAsRead(threadId: String, deviceId: String, runner: String?) async throws -> Thread {
        var queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        if let runner = runner {
            queryItems.append(URLQueryItem(name: "runner", value: runner))
        }
        let data = try await executeWithFallback(path: "/threads/\(threadId)/read", queryItems: queryItems, method: "PUT")
        return try decoder.decode(Thread.self, from: data)
    }

    /// v4.3.2: 未読スレッド数を取得する
    func getUnreadCount(deviceId: String) async throws -> Int {
        let queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        let data = try await executeWithFallback(path: "/unread_count", queryItems: queryItems)
        struct UnreadCountResponse: Codable {
            let deviceId: String
            let unreadCount: Int

            enum CodingKeys: String, CodingKey {
                case deviceId = "device_id"
                case unreadCount = "unread_count"
            }
        }
        let decoded = try decoder.decode(UnreadCountResponse.self, from: data)
        return decoded.unreadCount
    }
}
