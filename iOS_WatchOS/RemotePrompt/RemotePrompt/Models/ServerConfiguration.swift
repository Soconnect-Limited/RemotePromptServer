import Foundation

/// サーバー接続設定
/// Keychain/UserDefaultsに永続化される
struct ServerConfiguration: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var alternativeURLs: [String]
    var apiKey: String
    var certificateFingerprint: String?
    var isTrusted: Bool
    var autoFallback: Bool
    var lastConnected: Date?
    let createdAt: Date
    var aiProviders: [AIProviderConfiguration]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case alternativeURLs = "alternative_urls"
        case apiKey = "api_key"
        case certificateFingerprint = "certificate_fingerprint"
        case isTrusted = "is_trusted"
        case autoFallback = "auto_fallback"
        case lastConnected = "last_connected"
        case createdAt = "created_at"
        case aiProviders = "ai_providers"
    }

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        alternativeURLs: [String] = [],
        apiKey: String,
        certificateFingerprint: String? = nil,
        isTrusted: Bool = false,
        autoFallback: Bool = false,
        lastConnected: Date? = nil,
        createdAt: Date = Date(),
        aiProviders: [AIProviderConfiguration] = AIProviderConfiguration.defaultConfigurations()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.alternativeURLs = alternativeURLs
        self.apiKey = apiKey
        self.certificateFingerprint = certificateFingerprint
        self.isTrusted = isTrusted
        self.autoFallback = autoFallback
        self.lastConnected = lastConnected
        self.createdAt = createdAt
        self.aiProviders = aiProviders
    }

    // MARK: - Custom Decoder for Backward Compatibility

    /// カスタムデコーダ: ai_providersがない既存データでもデコード可能にする
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        alternativeURLs = try container.decodeIfPresent([String].self, forKey: .alternativeURLs) ?? []
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        certificateFingerprint = try container.decodeIfPresent(String.self, forKey: .certificateFingerprint)
        isTrusted = try container.decodeIfPresent(Bool.self, forKey: .isTrusted) ?? false
        autoFallback = try container.decodeIfPresent(Bool.self, forKey: .autoFallback) ?? false
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        // ai_providersは省略可能（後方互換性）
        aiProviders = try container.decodeIfPresent([AIProviderConfiguration].self, forKey: .aiProviders)
            ?? AIProviderConfiguration.defaultConfigurations()
    }

    /// 有効なAIプロバイダーをソート順で取得
    var enabledAIProviders: [AIProviderConfiguration] {
        aiProviders.enabledProviders
    }

    /// URLバリデーション（https://必須）
    var isValidURL: Bool {
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "https",
              parsed.host != nil else {
            return false
        }
        return true
    }

    /// URL と APIキーの両方が設定されているか
    var isFullyConfigured: Bool {
        isValidURL && !apiKey.isEmpty
    }

    /// 代替URLのバリデーション
    var validAlternativeURLs: [String] {
        alternativeURLs.filter { urlString in
            guard let parsed = URL(string: urlString),
                  let scheme = parsed.scheme?.lowercased(),
                  scheme == "https",
                  parsed.host != nil else {
                return false
            }
            return true
        }
    }

    /// 全ての有効なURL（メイン + 代替）を返す
    var allValidURLs: [String] {
        var urls: [String] = []
        if isValidURL {
            urls.append(url)
        }
        urls.append(contentsOf: validAlternativeURLs)
        return urls
    }
}

// MARK: - 接続状態

/// 接続テスト結果
enum ConnectionStatus: Equatable {
    case idle
    case connecting
    case success(connectedURL: String)
    case failed(error: ConnectionError)
}

/// 接続エラー種別
enum ConnectionError: Error, Equatable {
    case invalidURL
    case networkError(String)
    case certificateError(String)
    case authenticationError
    case serverError(statusCode: Int)
    case unknown(String)

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return L10n.Error.invalidUrl
        case .networkError(let message):
            return L10n.Error.network(message)
        case .certificateError(let message):
            return L10n.Error.certificate(message)
        case .authenticationError:
            return L10n.Error.auth
        case .serverError(let statusCode):
            return L10n.Error.server(statusCode)
        case .unknown(let message):
            return L10n.Error.unknown(message)
        }
    }
}

// MARK: - 証明書情報

/// サーバーから取得した証明書情報
struct CertificateInfo: Codable, Equatable {
    let fingerprint: String
    let commonName: String?
    let validFrom: Date?
    let validUntil: Date?
    let issuer: String?
    let serialNumber: String?
    let isSelfSigned: Bool
    let pendingRestart: Bool?
    let pendingFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case fingerprint
        case commonName = "common_name"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
        case issuer
        case serialNumber = "serial_number"
        case isSelfSigned = "is_self_signed"
        case pendingRestart = "pending_restart"
        case pendingFingerprint = "pending_fingerprint"
    }

    /// フィンガープリントの短縮表示（確認用）
    var shortFingerprint: String {
        let components = fingerprint.split(separator: ":")
        if components.count >= 8 {
            let first4 = components.prefix(4).joined(separator: ":")
            let last4 = components.suffix(4).joined(separator: ":")
            return "\(first4)...\(last4)"
        }
        return fingerprint
    }
}

// MARK: - SSEイベント

/// 証明書変更イベント（SSE経由で受信）
struct CertificateChangedEvent: Codable {
    let oldFingerprint: String
    let newFingerprint: String
    let reason: String
    let effectiveAfterRestart: Bool
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case oldFingerprint = "old_fingerprint"
        case newFingerprint = "new_fingerprint"
        case reason
        case effectiveAfterRestart = "effective_after_restart"
        case timestamp
    }
}

/// 証明書失効イベント（SSE経由で受信）
struct CertificateRevokedEvent: Codable {
    let revokedFingerprint: String
    let reason: String
    let revokedAt: Date
    let actionRequired: String

    enum CodingKeys: String, CodingKey {
        case revokedFingerprint = "revoked_fingerprint"
        case reason
        case revokedAt = "revoked_at"
        case actionRequired = "action_required"
    }
}

/// 証明書モード変更イベント（SSE経由で受信）
struct CertificateModeChangedEvent: Codable {
    let modeBefore: String
    let modeAfter: String
    let reason: String
    let triggeredAt: Date

    enum CodingKeys: String, CodingKey {
        case modeBefore = "mode_before"
        case modeAfter = "mode_after"
        case reason
        case triggeredAt = "triggered_at"
    }
}
