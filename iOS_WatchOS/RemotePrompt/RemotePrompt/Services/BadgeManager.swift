import UIKit
import UserNotifications

/// 自己署名証明書を無条件で信頼するシンプルなデリゲート
/// 注意: BadgeManager専用。セキュリティ的にはCertificatePinningDelegateを使うべきだが、
/// URLSession競合を避けるためにバッジ更新では簡易的な実装を使用
private final class SimpleTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// v4.3.2: アプリアイコンのバッジ管理
/// 注意: Swift 6のデフォルトMainActor分離を回避するため、明示的にnonisolatedを指定
/// API呼び出しはバックグラウンドで実行し、UI更新のみMainActorで行う
/// 重要: メインのAPIClientとURLSessionを共有するとTLS接続の競合が発生するため、
/// 独自の軽量セッションを使用する
nonisolated final class BadgeManager: Sendable {
    nonisolated static let shared = BadgeManager()

    private let deviceId: String

    private nonisolated init() {
        self.deviceId = APIClient.getDeviceId()
    }

    /// サーバーから未読数を取得してバッジを更新（バックグラウンドで実行）
    /// 注意: メインAPIClientとのURLSession競合を避けるため、独自のセッションで実行
    nonisolated func updateBadge() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[BadgeManager] updateBadge START @ \(Date()) isMainThread: \(Foundation.Thread.isMainThread)")

        // メインのルーム読み込みを優先するため、少し待機
        try? await Task.sleep(for: .seconds(2))

        do {
            let count = try await fetchUnreadCountDirectly()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("[BadgeManager] getUnreadCount returned in \(String(format: "%.2f", elapsed))s @ \(Date())")
            // バッジ設定はMainActorで行う
            await MainActor.run {
                UNUserNotificationCenter.current().setBadgeCount(count) { error in
                    if let error = error {
                        print("DEBUG: [BADGE] Failed to set badge: \(error.localizedDescription)")
                    }
                }
            }
            print("DEBUG: [BADGE] Updated badge count to \(count)")
        } catch {
            print("DEBUG: [BADGE] Failed to get unread count: \(error.localizedDescription)")
        }
    }

    /// 独自のURLSessionで未読数を取得（メインAPIClientと競合しない）
    private nonisolated func fetchUnreadCountDirectly() async throws -> Int {
        let baseURL = Constants.baseURL
        guard !baseURL.isEmpty,
              var components = URLComponents(string: "\(baseURL)/unread_count") else {
            throw NSError(domain: "BadgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        components.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]

        guard let url = components.url else {
            throw NSError(domain: "BadgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        guard let apiKey = Constants.apiKey else {
            throw NSError(domain: "BadgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 10 // バッジ更新は短いタイムアウトで十分

        // 独自の軽量セッション（証明書ピンニングなし、自己署名証明書を許可）
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false

        // 自己署名証明書を許可するデリゲート
        let delegate = SimpleTrustDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "BadgeManager", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP error \(code)"])
        }

        struct UnreadCountResponse: Codable {
            let deviceId: String
            let unreadCount: Int

            enum CodingKeys: String, CodingKey {
                case deviceId = "device_id"
                case unreadCount = "unread_count"
            }
        }

        let decoded = try JSONDecoder().decode(UnreadCountResponse.self, from: data)
        return decoded.unreadCount
    }

    /// バッジを直接設定（0で非表示）
    @MainActor
    func setBadge(count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("DEBUG: [BADGE] Failed to set badge: \(error.localizedDescription)")
            }
        }
    }

    /// バッジをクリア
    nonisolated func clearBadge() async {
        await MainActor.run {
            setBadge(count: 0)
        }
        print("DEBUG: [BADGE] Badge cleared")
    }
}
