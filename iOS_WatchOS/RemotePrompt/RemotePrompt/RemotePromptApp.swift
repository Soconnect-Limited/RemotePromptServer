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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
