//
//  RemotePromptApp.swift
//  RemotePrompt
//
//  Created by MacStudio on 2025/11/18.
//

import SwiftUI
import UserNotifications

@main
struct RemotePromptApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // v4.3.2: フォアグラウンド復帰時にバッジを更新
            if newPhase == .active {
                Task { @MainActor in
                    await BadgeManager.shared.updateBadge()
                }
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set notification delegate for foreground notifications
        UNUserNotificationCenter.current().delegate = self

        // v4.3.3: DeviceIdをログ出力
        let deviceId = APIClient.getDeviceId()
        print("📱 DeviceId: \(deviceId)")

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Failed to request notification permission: \(error)")
                return
            }

            if granted {
                print("✅ Notification permission granted")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("⚠️ Notification permission denied")
            }
        }
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// フォアグラウンドでも通知バナーを表示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📬 Received notification in foreground: \(notification.request.content.title)")
        completionHandler([.banner, .sound, .badge])
    }

    /// 通知タップ時の処理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📬 User tapped notification: \(response.notification.request.content.title)")
        completionHandler()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert device token to hex string
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 APNs Device Token: \(token)")

        // Save to UserDefaults
        UserDefaults.standard.set(token, forKey: "apns_device_token")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for push: \(error)")
    }
}
