import Foundation
import Security
import Combine

/// サーバー設定の永続化ストア
/// - APIキー、証明書データ: Keychain（暗号化）
/// - URL、名前等の非機密情報: UserDefaults
final class ServerConfigurationStore: ObservableObject {
    static let shared = ServerConfigurationStore()

    // MARK: - Keychain Keys
    private enum KeychainKey {
        static let apiKey = "server_api_key"
        static let certificateData = "server_certificate_data"
        static let certificateFingerprint = "server_certificate_fingerprint"
    }

    // MARK: - UserDefaults Keys
    private enum DefaultsKey {
        static let configuration = "server_configuration"
        static let migrationCompleted = "settings_migrated_v2"
    }

    // MARK: - Published Properties
    @Published private(set) var currentConfiguration: ServerConfiguration?
    @Published private(set) var isLoaded: Bool = false

    private init() {
        load()
    }

    // MARK: - Public Methods

    /// 設定を保存
    func save(_ config: ServerConfiguration) {
        // APIキーをKeychainに保存
        KeychainHelper.set(key: KeychainKey.apiKey, value: config.apiKey)

        // 証明書フィンガープリントをKeychainに保存
        if let fingerprint = config.certificateFingerprint {
            KeychainHelper.set(key: KeychainKey.certificateFingerprint, value: fingerprint)
        }

        // 非機密情報をUserDefaultsに保存（APIキーは除外）
        var configForDefaults = config
        configForDefaults.apiKey = "" // UserDefaultsには保存しない

        if let data = try? JSONEncoder().encode(configForDefaults) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.configuration)
        }

        currentConfiguration = config
        NotificationCenter.default.post(name: .serverConfigurationChanged, object: config)
    }

    /// 設定を読み込み
    @discardableResult
    func load() -> ServerConfiguration? {
        defer { isLoaded = true }

        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.configuration),
              var config = try? JSONDecoder().decode(ServerConfiguration.self, from: data) else {
            currentConfiguration = nil
            return nil
        }

        // KeychainからAPIキーを復元
        if let apiKey = KeychainHelper.get(key: KeychainKey.apiKey) {
            config.apiKey = apiKey
        }

        // Keychainから証明書フィンガープリントを復元
        if let fingerprint = KeychainHelper.get(key: KeychainKey.certificateFingerprint) {
            config.certificateFingerprint = fingerprint
        }

        currentConfiguration = config
        return config
    }

    /// 設定を削除
    func delete() {
        KeychainHelper.delete(key: KeychainKey.apiKey)
        KeychainHelper.delete(key: KeychainKey.certificateData)
        KeychainHelper.delete(key: KeychainKey.certificateFingerprint)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.configuration)

        currentConfiguration = nil
        NotificationCenter.default.post(name: .serverConfigurationChanged, object: nil)
    }

    // MARK: - Certificate Management

    /// 証明書データを保存
    func saveCertificate(_ data: Data, fingerprint: String) {
        // 証明書データをBase64でKeychain保存
        let base64Data = data.base64EncodedString()
        KeychainHelper.set(key: KeychainKey.certificateData, value: base64Data)
        KeychainHelper.set(key: KeychainKey.certificateFingerprint, value: fingerprint)

        // 現在の設定も更新
        if var config = currentConfiguration {
            config.certificateFingerprint = fingerprint
            config.isTrusted = true
            save(config)
        }
    }

    /// 証明書データを読み込み
    func loadCertificate() -> (data: Data, fingerprint: String)? {
        guard let base64Data = KeychainHelper.get(key: KeychainKey.certificateData),
              let data = Data(base64Encoded: base64Data),
              let fingerprint = KeychainHelper.get(key: KeychainKey.certificateFingerprint) else {
            return nil
        }
        return (data, fingerprint)
    }

    /// 証明書信頼をクリア
    func clearTrustedCertificate() {
        KeychainHelper.delete(key: KeychainKey.certificateData)
        KeychainHelper.delete(key: KeychainKey.certificateFingerprint)

        if var config = currentConfiguration {
            config.certificateFingerprint = nil
            config.isTrusted = false
            save(config)
        }
    }

    /// 全設定をリセット
    func resetAllConfiguration() {
        delete()
        UserDefaults.standard.removeObject(forKey: DefaultsKey.migrationCompleted)
    }

    // MARK: - Trust Management

    /// 証明書を信頼済みに設定
    func trustCertificate(fingerprint: String, certificateData: Data? = nil) {
        if let data = certificateData {
            saveCertificate(data, fingerprint: fingerprint)
        } else {
            KeychainHelper.set(key: KeychainKey.certificateFingerprint, value: fingerprint)
        }

        if var config = currentConfiguration {
            config.certificateFingerprint = fingerprint
            config.isTrusted = true
            save(config)
        }
    }

    /// 信頼を取り消し
    func revokeTrust() {
        clearTrustedCertificate()
    }

    // MARK: - Connection Tracking

    /// 最終接続日時を更新
    func updateLastConnected(url: String? = nil) {
        guard var config = currentConfiguration else { return }
        config.lastConnected = Date()
        save(config)
    }

    // MARK: - Migration

    /// 旧設定からの移行
    /// AppConfiguration.swift の plist 設定から移行
    func migrateIfNeeded(from oldBaseURL: String?, oldAPIKey: String?) {
        // 既に移行済みなら何もしない
        if UserDefaults.standard.bool(forKey: DefaultsKey.migrationCompleted) {
            return
        }

        // 新設定が既に存在するなら移行不要
        if currentConfiguration != nil {
            UserDefaults.standard.set(true, forKey: DefaultsKey.migrationCompleted)
            return
        }

        // 旧設定がなければ移行不要
        guard let oldURL = oldBaseURL, !oldURL.isEmpty else {
            return
        }

        // 新設定に変換
        let newConfig = ServerConfiguration(
            id: UUID(),
            name: "Migrated Server",
            url: oldURL,
            alternativeURLs: [],
            apiKey: oldAPIKey ?? "",
            certificateFingerprint: nil,
            isTrusted: false, // 初回接続時に再確認
            autoFallback: false,
            lastConnected: nil,
            createdAt: Date()
        )

        save(newConfig)
        UserDefaults.standard.set(true, forKey: DefaultsKey.migrationCompleted)

        print("[ServerConfigurationStore] Migrated from legacy settings: \(oldURL)")
    }

    /// 移行が必要かどうか
    var needsMigration: Bool {
        !UserDefaults.standard.bool(forKey: DefaultsKey.migrationCompleted) && currentConfiguration == nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let serverConfigurationChanged = Notification.Name("serverConfigurationChanged")
    static let certificateTrustChanged = Notification.Name("certificateTrustChanged")
}
