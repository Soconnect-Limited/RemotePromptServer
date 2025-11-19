@testable import RemotePrompt
import Foundation
import Testing

struct AppConfigurationTests {
    @Test func baseURLPrefersInfoDictionary() throws {
        let config = AppConfiguration(
            infoDictionary: ["RemotePromptBaseURL": "https://example.com/"],
            configDictionary: [:],
            environment: [:]
        )

        #expect(config.baseURL == "https://example.com")
    }

    @Test func baseURLFallsBackToConfig() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: ["RemotePromptBaseURL": "https://config.example.com///"],
            environment: [:]
        )

        #expect(config.baseURL == "https://config.example.com")
    }

    @Test func baseURLUsesDefaultWhenNoSource() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: [:],
            environment: [:]
        )

        #expect(config.baseURL == "http://100.100.30.35:35000")
    }

    @Test func apiKeyPrefersConfigOverEnv() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: ["RemotePromptAPIKey": "config-key"],
            environment: ["REMOTE_PROMPT_API_KEY": "env-key"]
        )

        #expect(config.apiKey == "config-key")
    }

    @Test func apiKeyFallsBackToEnv() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: [:],
            environment: ["REMOTE_PROMPT_API_KEY": "env-key"]
        )

        #expect(config.apiKey == "env-key")
    }

    @Test func apiKeyReturnsNilWhenMissingInDebug() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: [:],
            environment: [:]
        )

        #expect(config.apiKey == nil)
    }

    @Test func reportsAPIKeyConfiguredState() throws {
        let configured = AppConfiguration(
            infoDictionary: [:],
            configDictionary: ["RemotePromptAPIKey": "config-key"],
            environment: [:]
        )

        #expect(configured.isAPIKeyConfigured)

        let missing = AppConfiguration(
            infoDictionary: [:],
            configDictionary: [:],
            environment: [:]
        )

        #expect(missing.isAPIKeyConfigured == false)
    }
}
