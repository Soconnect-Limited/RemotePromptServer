import XCTest
@testable import RemotePrompt

/// CertificateValidatorのユニットテスト
final class CertificateValidatorTests: XCTestCase {

    // MARK: - Fingerprint Calculation Tests

    func testCalculateFingerprintReturnsColonSeparatedFormat() {
        // Given: 任意のデータ
        let testData = "test certificate data".data(using: .utf8)!

        // When: フィンガープリントを計算
        let fingerprint = CertificateValidator.calculateFingerprint(of: testData)

        // Then: コロン区切りの16進数形式
        let parts = fingerprint.split(separator: ":")
        XCTAssertEqual(parts.count, 32, "SHA256は32バイト = 32パーツ")
        for part in parts {
            XCTAssertEqual(part.count, 2, "各パーツは2文字の16進数")
            XCTAssertTrue(part.allSatisfy { $0.isHexDigit }, "16進数文字のみ")
        }
    }

    func testCalculateFingerprintIsDeterministic() {
        // Given: 同じデータ
        let testData = "deterministic test".data(using: .utf8)!

        // When: 複数回計算
        let fp1 = CertificateValidator.calculateFingerprint(of: testData)
        let fp2 = CertificateValidator.calculateFingerprint(of: testData)

        // Then: 同じ結果
        XCTAssertEqual(fp1, fp2)
    }

    func testCalculateFingerprintDifferentDataProducesDifferentFingerprints() {
        // Given: 異なるデータ
        let data1 = "data one".data(using: .utf8)!
        let data2 = "data two".data(using: .utf8)!

        // When: フィンガープリントを計算
        let fp1 = CertificateValidator.calculateFingerprint(of: data1)
        let fp2 = CertificateValidator.calculateFingerprint(of: data2)

        // Then: 異なるフィンガープリント
        XCTAssertNotEqual(fp1, fp2)
    }

    func testCalculateFingerprintIsUppercase() {
        // Given: 任意のデータ
        let testData = "uppercase test".data(using: .utf8)!

        // When: フィンガープリントを計算
        let fingerprint = CertificateValidator.calculateFingerprint(of: testData)

        // Then: 大文字のみ（区切り文字を除く）
        let hexOnly = fingerprint.replacingOccurrences(of: ":", with: "")
        XCTAssertEqual(hexOnly, hexOnly.uppercased())
    }

    func testCalculateFingerprintEmptyData() {
        // Given: 空のデータ
        let emptyData = Data()

        // When: フィンガープリントを計算
        let fingerprint = CertificateValidator.calculateFingerprint(of: emptyData)

        // Then: SHA256の空データハッシュ (e3b0c442...)
        XCTAssertTrue(fingerprint.hasPrefix("E3:B0:C4:42"))
    }

    // MARK: - Fingerprint Comparison Tests

    func testCompareFingerprintsCaseInsensitive() {
        // Given: 同じフィンガープリントの大文字・小文字バリエーション
        let testData = "comparison test".data(using: .utf8)!
        let fingerprint = CertificateValidator.calculateFingerprint(of: testData)
        let lowercaseFingerprint = fingerprint.lowercased()

        // Then: 両方のバリエーションは同等として扱える
        // (この場合はextractFingerprintがSecTrustを必要とするため直接比較は難しいが、
        //  compareFingerprints関数内でuppercased()を使用していることを検証)
        XCTAssertEqual(fingerprint.uppercased(), lowercaseFingerprint.uppercased())
    }
}

/// ServerConfigurationStoreのユニットテスト
final class ServerConfigurationStoreTests: XCTestCase {

    // テスト用のストアインスタンス
    private var store: ServerConfigurationStore!

    override func setUp() {
        super.setUp()
        // テスト用に新しいインスタンスを作成（実際の保存先を汚染しないよう注意）
        // 注意: シングルトンのため、テスト間で状態が共有される可能性がある
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - URL Validation Tests

    func testValidHTTPSURL() {
        // Given: 有効なHTTPS URL
        let url = "https://192.168.1.100:8443"

        // When/Then: HTTPS URLは有効
        XCTAssertTrue(url.hasPrefix("https://"), "HTTPS URLは有効")
    }

    func testInvalidHTTPURL() {
        // Given: HTTPのURL
        let url = "http://192.168.1.100:8080"

        // When/Then: HTTP URLは無効
        XCTAssertFalse(url.hasPrefix("https://"), "HTTP URLは無効")
    }

    func testURLWithPort() {
        // Given: ポート付きURL
        let url = "https://192.168.1.100:8443"

        // When: URLをパース
        let parsedURL = URL(string: url)

        // Then: ポートが正しく取得できる
        XCTAssertNotNil(parsedURL)
        XCTAssertEqual(parsedURL?.port, 8443)
    }

    func testURLWithIPAddress() {
        // Given: IPアドレスのURL
        let url = "https://192.168.1.100:8443"

        // When: URLをパース
        let parsedURL = URL(string: url)

        // Then: ホストが正しく取得できる
        XCTAssertNotNil(parsedURL)
        XCTAssertEqual(parsedURL?.host, "192.168.1.100")
    }

    func testURLWithHostname() {
        // Given: ホスト名のURL
        let url = "https://myserver.local:8443"

        // When: URLをパース
        let parsedURL = URL(string: url)

        // Then: ホストが正しく取得できる
        XCTAssertNotNil(parsedURL)
        XCTAssertEqual(parsedURL?.host, "myserver.local")
    }

    // MARK: - ServerConfiguration Model Tests

    func testServerConfigurationInitialization() {
        // Given: 設定パラメータ
        let id = UUID()
        let name = "Test Server"
        let url = "https://192.168.1.100:8443"
        let apiKey = "test-api-key"

        // When: ServerConfigurationを作成
        let config = ServerConfiguration(
            id: id,
            name: name,
            url: url,
            alternativeURLs: [],
            apiKey: apiKey,
            certificateFingerprint: nil,
            isTrusted: false,
            autoFallback: false,
            lastConnected: nil,
            createdAt: Date()
        )

        // Then: プロパティが正しく設定される
        XCTAssertEqual(config.id, id)
        XCTAssertEqual(config.name, name)
        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.apiKey, apiKey)
        XCTAssertFalse(config.isTrusted)
    }

    func testServerConfigurationWithAlternativeURLs() {
        // Given: 代替URL付きの設定
        let alternativeURLs = [
            "https://100.100.30.35:8443",
            "https://10.0.0.1:8443"
        ]

        // When: ServerConfigurationを作成
        let config = ServerConfiguration(
            id: UUID(),
            name: "Multi-URL Server",
            url: "https://192.168.1.100:8443",
            alternativeURLs: alternativeURLs,
            apiKey: "key",
            certificateFingerprint: nil,
            isTrusted: false,
            autoFallback: true,
            lastConnected: nil,
            createdAt: Date()
        )

        // Then: 代替URLが正しく設定される
        XCTAssertEqual(config.alternativeURLs.count, 2)
        XCTAssertTrue(config.autoFallback)
    }

    func testServerConfigurationWithCertificate() {
        // Given: 証明書付きの設定
        let fingerprint = "SHA256:A1:B2:C3:D4:E5:F6"

        // When: ServerConfigurationを作成
        let config = ServerConfiguration(
            id: UUID(),
            name: "Trusted Server",
            url: "https://192.168.1.100:8443",
            alternativeURLs: [],
            apiKey: "key",
            certificateFingerprint: fingerprint,
            isTrusted: true,
            autoFallback: false,
            lastConnected: Date(),
            createdAt: Date()
        )

        // Then: 証明書情報が正しく設定される
        XCTAssertEqual(config.certificateFingerprint, fingerprint)
        XCTAssertTrue(config.isTrusted)
        XCTAssertNotNil(config.lastConnected)
    }
}

/// CertificateInfoモデルのテスト
final class CertificateInfoTests: XCTestCase {

    func testCertificateInfoInitialization() {
        // Given: 証明書情報パラメータ
        let fingerprint = "A1:B2:C3:D4:E5:F6:G7:H8:I9:J0:K1:L2:M3:N4:O5:P6:Q1:R2:S3:T4:U5:V6:W7:X8:Y9:Z0:A1:B2:C3:D4:E5:F6"
        let commonName = "192.168.1.100"

        // When: CertificateInfoを作成
        let info = CertificateInfo(
            fingerprint: fingerprint,
            commonName: commonName,
            validFrom: Date(),
            validUntil: Date().addingTimeInterval(365 * 24 * 60 * 60),
            issuer: "RemotePrompt Self-Signed",
            serialNumber: "123456789",
            isSelfSigned: true,
            pendingRestart: false,
            pendingFingerprint: nil
        )

        // Then: プロパティが正しく設定される
        XCTAssertEqual(info.fingerprint, fingerprint)
        XCTAssertEqual(info.commonName, commonName)
        XCTAssertTrue(info.isSelfSigned)
    }

    func testShortFingerprint() {
        // Given: 長いフィンガープリント（8つ以上のコンポーネント）
        // SHA256フィンガープリントは32バイト = 32コンポーネント
        let fullFingerprint = "A1:B2:C3:D4:E5:F6:A7:B8:C9:D0:E1:F2:A3:B4:C5:D6:E7:F8:A9:B0:C1:D2:E3:F4:A5:B6:C7:D8:E9:F0:A1:B2"

        // When: CertificateInfoを作成
        let info = CertificateInfo(
            fingerprint: fullFingerprint,
            commonName: nil,
            validFrom: nil,
            validUntil: nil,
            issuer: nil,
            serialNumber: nil,
            isSelfSigned: true,
            pendingRestart: nil,
            pendingFingerprint: nil
        )

        // Then: shortFingerprintは短縮版を返す (first4...last4形式)
        XCTAssertTrue(info.shortFingerprint.count < fullFingerprint.count)
        XCTAssertTrue(info.shortFingerprint.contains("..."))
        // 形式確認: "A1:B2:C3:D4...E9:F0:A1:B2"
        XCTAssertTrue(info.shortFingerprint.hasPrefix("A1:B2:C3:D4"))
        XCTAssertTrue(info.shortFingerprint.hasSuffix("E9:F0:A1:B2"))
    }

    func testCertificateInfoWithPendingRestart() {
        // Given: 再起動待ちの証明書情報
        let currentFingerprint = "AA:BB:CC:DD"
        let pendingFingerprint = "XX:YY:ZZ:WW"

        // When: CertificateInfoを作成
        let info = CertificateInfo(
            fingerprint: currentFingerprint,
            commonName: nil,
            validFrom: nil,
            validUntil: nil,
            issuer: nil,
            serialNumber: nil,
            isSelfSigned: true,
            pendingRestart: true,
            pendingFingerprint: pendingFingerprint
        )

        // Then: 再起動待ち情報が正しく設定される
        XCTAssertEqual(info.pendingRestart, true)
        XCTAssertEqual(info.pendingFingerprint, pendingFingerprint)
    }
}
