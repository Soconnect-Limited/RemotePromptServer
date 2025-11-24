import Foundation

enum FeatureFlags {
    /// UIKit版チャット一覧を有効にするフラグ（デフォルトfalse）。
    /// UserDefaults.standard.bool(forKey: "USE_UIKIT_CHAT_LIST") が true の場合に有効。
    /// Build 設定やテストでは環境変数 USE_UIKIT_CHAT_LIST=1 でも上書き可能。
    static var useUIKitChatList: Bool {
        if let env = ProcessInfo.processInfo.environment["USE_UIKIT_CHAT_LIST"], env == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "USE_UIKIT_CHAT_LIST")
    }
}
