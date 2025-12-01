import UIKit
import UserNotifications

/// v4.3.2: アプリアイコンのバッジ管理
@MainActor
final class BadgeManager {
    static let shared = BadgeManager()

    private let apiClient: APIClientProtocol
    private let deviceId: String

    private init(
        apiClient: APIClientProtocol = APIClient.shared,
        deviceIdProvider: () -> String = APIClient.getDeviceId
    ) {
        self.apiClient = apiClient
        self.deviceId = deviceIdProvider()
    }

    /// サーバーから未読数を取得してバッジを更新
    func updateBadge() async {
        do {
            let count = try await apiClient.getUnreadCount(deviceId: deviceId)
            await setBadge(count: count)
            print("DEBUG: [BADGE] Updated badge count to \(count)")
        } catch {
            print("DEBUG: [BADGE] Failed to get unread count: \(error.localizedDescription)")
        }
    }

    /// バッジを直接設定（0で非表示）
    func setBadge(count: Int) async {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("DEBUG: [BADGE] Failed to set badge: \(error.localizedDescription)")
            }
        }
    }

    /// バッジをクリア
    func clearBadge() async {
        await setBadge(count: 0)
        print("DEBUG: [BADGE] Badge cleared")
    }
}
