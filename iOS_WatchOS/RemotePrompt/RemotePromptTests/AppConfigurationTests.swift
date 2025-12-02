@testable import RemotePrompt
import Foundation
import XCTest

final class AppConfigurationTests: XCTestCase {

    func testBaseURLPrefersInfoDictionary() throws {
        let config = AppConfiguration(
            infoDictionary: ["RemotePromptBaseURL": "https://example.com/"],
            configDictionary: [:],
            environment: [:]
        )

        XCTAssertEqual(config.baseURL, "https://example.com")
    }

    func testBaseURLFallsBackToConfig() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: ["RemotePromptBaseURL": "https://config.example.com///"],
            environment: [:]
        )

        XCTAssertEqual(config.baseURL, "https://config.example.com")
    }

    func testBaseURLUsesDefaultWhenNoSource() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: [:],
            environment: [:]
        )

        // デフォルト値はHTTPS対応後 https://100.100.30.35:8443 に変更
        XCTAssertEqual(config.baseURL, "https://100.100.30.35:8443")
    }

    func testApiKeyPrefersConfigOverEnv() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: ["RemotePromptAPIKey": "config-key"],
            environment: ["REMOTE_PROMPT_API_KEY": "env-key"]
        )

        XCTAssertEqual(config.apiKey, "config-key")
    }

    func testApiKeyFallsBackToEnv() throws {
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: [:],
            environment: ["REMOTE_PROMPT_API_KEY": "env-key"]
        )

        XCTAssertEqual(config.apiKey, "env-key")
    }

    func testApiKeyReturnsNilWhenMissingInDebug() throws {
        // DEBUG時はassertionFailureが発生するため、isAPIKeyConfiguredで確認
        // apiKey プロパティ自体はassertionFailure後もnilを返す設計
        let config = AppConfiguration(
            infoDictionary: [:],
            configDictionary: [:],
            environment: [:]
        )

        // isAPIKeyConfiguredがfalseであることを確認
        XCTAssertFalse(config.isAPIKeyConfigured)
    }

    func testReportsAPIKeyConfiguredState() throws {
        let configured = AppConfiguration(
            infoDictionary: [:],
            configDictionary: ["RemotePromptAPIKey": "config-key"],
            environment: [:]
        )

        XCTAssertTrue(configured.isAPIKeyConfigured)

        let missing = AppConfiguration(
            infoDictionary: [:],
            configDictionary: [:],
            environment: [:]
        )

        XCTAssertFalse(missing.isAPIKeyConfigured)
    }
}
