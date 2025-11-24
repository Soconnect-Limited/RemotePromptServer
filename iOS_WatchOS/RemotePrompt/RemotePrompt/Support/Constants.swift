import Foundation

enum Constants {
    private static let configuration = AppConfiguration()

    /// Base URL for the RemotePrompt server (without trailing slash).
    static var baseURL: String {
        configuration.baseURL
    }

    /// API Key sent via `x-api-key` header, optional for local development.
    static var apiKey: String? {
        configuration.apiKey
    }

    static var isAPIKeyConfigured: Bool {
        configuration.isAPIKeyConfigured
    }

    static var missingAPIKeyMessage: String {
        "APIキーが未設定です。RemotePromptConfig.plistのRemotePromptAPIKey、Info.plist、または REMOTE_PROMPT_API_KEY 環境変数を設定してください。"
    }

    // Debug/behavior toggles (defaults follow spec unless上書き)
    static var useMainDelegateQueue: Bool {
        // env REMOTE_PROMPT_SSE_MAIN_QUEUE=0 でBGキューに切替
        if let env = ProcessInfo.processInfo.environment["REMOTE_PROMPT_SSE_MAIN_QUEUE"], env == "0" {
            return false
        }
        return true // Spec準拠デフォルト
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
