import Foundation

enum Constants {
    /// Base URL for the RemotePrompt server (no trailing slash).
    static let baseURL: String = {
        if let fromInfo = Bundle.main.object(forInfoDictionaryKey: "RemotePromptBaseURL") as? String,
           !fromInfo.isEmpty {
            return fromInfo.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let env = ProcessInfo.processInfo.environment["REMOTE_PROMPT_BASE_URL"], !env.isEmpty {
            return env.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "http://100.100.30.35:35000"
    }()

    /// API Key sent via `x-api-key` header.
    static let apiKey: String = {
        if let fromInfo = Bundle.main.object(forInfoDictionaryKey: "RemotePromptAPIKey") as? String,
           !fromInfo.isEmpty {
            return fromInfo
        }
        if let env = ProcessInfo.processInfo.environment["REMOTE_PROMPT_API_KEY"], !env.isEmpty {
            return env
        }
        fatalError("API Key not configured. Set REMOTE_PROMPT_API_KEY env or RemotePromptAPIKey in Info.plist")
    }()
}
