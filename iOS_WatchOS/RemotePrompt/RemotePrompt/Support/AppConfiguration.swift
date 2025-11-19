import Foundation

struct AppConfiguration {
    enum Key: String {
        case baseURL = "RemotePromptBaseURL"
        case apiKey = "RemotePromptAPIKey"

        var environmentName: String {
            switch self {
            case .baseURL:
                return "REMOTE_PROMPT_BASE_URL"
            case .apiKey:
                return "REMOTE_PROMPT_API_KEY"
            }
        }
    }

    private let infoDictionary: [String: Any]
    private let configDictionary: [String: Any]
    private let environment: [String: String]

    init(
        infoDictionary: [String: Any]? = nil,
        configDictionary: [String: Any]? = nil,
        environment: [String: String]? = nil,
        bundle: Bundle = .main
    ) {
        self.infoDictionary = infoDictionary ?? bundle.infoDictionary ?? [:]
        self.configDictionary = configDictionary ?? AppConfiguration.loadConfig(from: bundle)
        self.environment = environment ?? ProcessInfo.processInfo.environment
    }

    var baseURL: String {
        sanitizeBaseURL(value(for: .baseURL) ?? "http://100.100.30.35:35000")
    }

    var apiKey: String? {
        guard let key = value(for: .apiKey) else {
#if DEBUG
            assertionFailure("API Key not configured. Provide REMOTE_PROMPT_API_KEY env, RemotePromptAPIKey in Info.plist, or RemotePromptConfig.plist")
#endif
            return nil
        }
        return key
    }

    var isAPIKeyConfigured: Bool {
        value(for: .apiKey) != nil
    }

    private func value(for key: Key) -> String? {
        if let infoValue = trimmed(infoDictionary[key.rawValue] as? String) {
            return infoValue
        }
        if let configValue = trimmed(configDictionary[key.rawValue] as? String) {
            return configValue
        }
        if let envValue = trimmed(environment[key.environmentName]) {
            return envValue
        }
        return nil
    }

    private func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func sanitizeBaseURL(_ raw: String) -> String {
        var url = raw
        while url.last == "/" {
            url.removeLast()
        }
        return url
    }

    private static func loadConfig(from bundle: Bundle) -> [String: Any] {
        guard let url = bundle.url(forResource: "RemotePromptConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
