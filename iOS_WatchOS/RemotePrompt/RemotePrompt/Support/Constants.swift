import Foundation

enum Constants {
    private static let legacyConfiguration = AppConfiguration()

    /// Base URL for the RemotePrompt server (without trailing slash).
    /// ServerConfigurationStoreを優先し、未設定の場合は旧設定にフォールバック
    static var baseURL: String {
        if let config = ServerConfigurationStore.shared.currentConfiguration,
           !config.url.isEmpty {
            return sanitizeURL(config.url)
        }
        return legacyConfiguration.baseURL
    }

    /// API Key sent via `x-api-key` header.
    /// ServerConfigurationStoreを優先し、未設定の場合は旧設定にフォールバック
    static var apiKey: String? {
        if let config = ServerConfigurationStore.shared.currentConfiguration,
           !config.apiKey.isEmpty {
            return config.apiKey
        }
        return legacyConfiguration.apiKey
    }

    static var isAPIKeyConfigured: Bool {
        if let config = ServerConfigurationStore.shared.currentConfiguration {
            return !config.apiKey.isEmpty
        }
        return legacyConfiguration.isAPIKeyConfigured
    }

    /// サーバーが設定済みかどうか
    static var isServerConfigured: Bool {
        ServerConfigurationStore.shared.currentConfiguration != nil || !legacyConfiguration.baseURL.isEmpty
    }

    static var missingAPIKeyMessage: String {
        "APIキーが未設定です。サーバー設定画面からAPIキーを設定してください。"
    }

    /// 現在のサーバー設定
    static var currentServerConfiguration: ServerConfiguration? {
        ServerConfigurationStore.shared.currentConfiguration
    }

    /// URLの末尾スラッシュを除去
    private static func sanitizeURL(_ url: String) -> String {
        var result = url
        while result.last == "/" {
            result.removeLast()
        }
        return result
    }

    // Debug/behavior toggles (defaults follow spec unless上書き)
    static var useMainDelegateQueue: Bool {
        // デフォルトをBG寄りに倒し、必要なときのみ main を明示（env=1）。
        if let env = ProcessInfo.processInfo.environment["REMOTE_PROMPT_SSE_MAIN_QUEUE"], env == "1" {
            return true
        }
        return false
    }

    static var reuseSSESession: Bool {
        // env REMOTE_PROMPT_SSE_REUSE_SESSION=1 で再利用、デフォルトはSpec準拠で都度生成
        if let env = ProcessInfo.processInfo.environment["REMOTE_PROMPT_SSE_REUSE_SESSION"], env == "1" {
            return true
        }
        return false
    }

    static var enableVerboseLogs: Bool {
        ProcessInfo.processInfo.environment["REMOTE_PROMPT_VERBOSE_LOGS"] == "1"
    }
}
