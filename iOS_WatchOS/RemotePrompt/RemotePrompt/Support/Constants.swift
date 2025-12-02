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

    /// 自動フォールバックが有効かどうか
    static var autoFallbackEnabled: Bool {
        ServerConfigurationStore.shared.currentConfiguration?.autoFallback ?? false
    }

    /// 全ての有効なURL（メイン + 代替）を返す
    /// autoFallbackが無効の場合はメインURLのみ
    static var allURLs: [String] {
        guard let config = ServerConfigurationStore.shared.currentConfiguration else {
            let legacy = legacyConfiguration.baseURL
            return legacy.isEmpty ? [] : [legacy]
        }

        var urls: [String] = []
        if !config.url.isEmpty {
            urls.append(sanitizeURL(config.url))
        }

        // autoFallbackが有効な場合のみ代替URLを追加
        if config.autoFallback {
            for altURL in config.alternativeURLs {
                let sanitized = sanitizeURL(altURL)
                if !sanitized.isEmpty && !urls.contains(sanitized) {
                    urls.append(sanitized)
                }
            }
        }

        return urls
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
