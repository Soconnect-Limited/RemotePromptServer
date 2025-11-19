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
}
