import Foundation
import SwiftUI
import Combine

/// サーバー設定画面のViewModel
@MainActor
final class ServerSettingsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var serverURL: String = ""
    @Published var alternativeURLs: [String] = []
    @Published var apiKey: String = ""
    @Published var serverName: String = "My Server"
    @Published var autoFallback: Bool = false

    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var connectedURL: String?
    @Published var certificateInfo: CertificateInfo?

    @Published var showCertificateAlert: Bool = false
    @Published var showCertificateChangedAlert: Bool = false
    @Published var pendingCertificateInfo: CertificateInfo?

    /// 信頼待ちの証明書DERデータ（TLS接続から取得）
    private var pendingCertificateData: Data?

    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    // MARK: - Private Properties

    private let store: ServerConfigurationStore
    private var cancellables = Set<AnyCancellable>()

    /// 接続テスト用の証明書バイパスDelegate
    private lazy var testConnectionDelegate: TestConnectionDelegate = {
        TestConnectionDelegate()
    }()

    // MARK: - Initialization

    init(store: ServerConfigurationStore = .shared) {
        self.store = store
        loadConfiguration()
    }

    // MARK: - Public Methods

    /// 保存された設定を読み込み
    func loadConfiguration() {
        guard let config = store.currentConfiguration else { return }

        serverURL = config.url
        alternativeURLs = config.alternativeURLs
        apiKey = config.apiKey
        serverName = config.name
        autoFallback = config.autoFallback

        if config.isTrusted, let fingerprint = config.certificateFingerprint {
            // 簡易的なCertificateInfo作成（詳細はサーバーから取得）
            certificateInfo = CertificateInfo(
                fingerprint: fingerprint,
                commonName: nil,
                validFrom: nil,
                validUntil: nil,
                issuer: nil,
                serialNumber: nil,
                isSelfSigned: true,
                pendingRestart: nil,
                pendingFingerprint: nil
            )
        }

        // 接続状態を復元：設定が保存済みで信頼済みなら「接続成功」として表示
        if config.isTrusted && !config.url.isEmpty {
            connectionStatus = .success(connectedURL: config.url)
            connectedURL = config.url
        } else if !config.url.isEmpty {
            // URLはあるが未信頼の場合は idle のまま（接続テストが必要）
            connectionStatus = .idle
        }
    }

    /// 接続テスト実行
    func testConnection() async {
        guard !serverURL.isEmpty else {
            connectionStatus = .failed(error: .invalidURL)
            return
        }

        connectionStatus = .connecting
        connectedURL = nil
        errorMessage = nil

        // 試行するURLリスト
        var urlsToTry = [serverURL]
        if autoFallback {
            urlsToTry.append(contentsOf: alternativeURLs.filter { !$0.isEmpty })
        }

        for url in urlsToTry {
            let result = await tryConnect(to: url)
            switch result {
            case .success(let info):
                connectedURL = url
                await handleConnectionSuccess(url: url, certificateInfo: info)
                return
            case .failure(let error):
                print("[ServerSettingsViewModel] Connection to \(url) failed: \(error)")
                continue
            }
        }

        // 全て失敗
        connectionStatus = .failed(error: .networkError("全てのURLへの接続に失敗しました"))
    }

    /// 代替URLを追加
    func addAlternativeURL(_ url: String) {
        guard !url.isEmpty, !alternativeURLs.contains(url) else { return }
        alternativeURLs.append(url)
    }

    /// 代替URLを削除
    func removeAlternativeURL(at index: Int) {
        guard alternativeURLs.indices.contains(index) else { return }
        alternativeURLs.remove(at: index)
    }

    /// 証明書を信頼
    func trustCertificate() {
        guard let info = pendingCertificateInfo ?? certificateInfo else { return }

        // 重要: 先にViewModel上の設定を保存してから証明書信頼を設定する
        // これにより alternativeURLs 等の設定が失われない
        // （store.trustCertificate は currentConfiguration を使って保存するため）

        // 1. まずViewModelの設定を保存（alternativeURLs等を含む）
        saveConfiguration()

        // 2. その後で証明書信頼を設定（フィンガープリントとisTrustedを更新）
        store.trustCertificate(fingerprint: info.fingerprint, certificateData: pendingCertificateData)

        showCertificateAlert = false
        showCertificateChangedAlert = false
        pendingCertificateInfo = nil
        pendingCertificateData = nil

        // 接続成功として更新
        if let url = connectedURL {
            connectionStatus = .success(connectedURL: url)
        }
    }

    /// 証明書信頼を拒否
    func rejectCertificate() {
        showCertificateAlert = false
        showCertificateChangedAlert = false
        pendingCertificateInfo = nil
        connectionStatus = .idle
        connectedURL = nil
    }

    /// 設定を保存
    func saveConfiguration() {
        let config = ServerConfiguration(
            id: store.currentConfiguration?.id ?? UUID(),
            name: serverName,
            url: serverURL,
            alternativeURLs: alternativeURLs.filter { !$0.isEmpty },
            apiKey: apiKey,
            certificateFingerprint: certificateInfo?.fingerprint ?? store.currentConfiguration?.certificateFingerprint,
            isTrusted: store.currentConfiguration?.isTrusted ?? false,
            autoFallback: autoFallback,
            lastConnected: store.currentConfiguration?.lastConnected,
            createdAt: store.currentConfiguration?.createdAt ?? Date()
        )

        store.save(config)
    }

    /// 証明書信頼をリセット
    func resetCertificateTrust() {
        store.clearTrustedCertificate()
        certificateInfo = nil
        connectionStatus = .idle
    }

    /// 全設定をリセット
    func resetAllSettings() {
        store.resetAllConfiguration()
        serverURL = ""
        alternativeURLs = []
        apiKey = ""
        serverName = "My Server"
        autoFallback = false
        connectionStatus = .idle
        connectedURL = nil
        certificateInfo = nil
    }

    // MARK: - Private Methods

    /// 指定URLへの接続を試行
    private func tryConnect(to urlString: String) async -> Result<CertificateInfo?, ConnectionError> {
        guard let baseURL = URL(string: urlString) else {
            return .failure(.invalidURL)
        }

        // /server/certificate エンドポイントを試行
        let certificateURL = baseURL.appendingPathComponent("server/certificate")

        var request = URLRequest(url: certificateURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        // APIキーがあれば付与
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        do {
            // 自己署名証明書を許可するカスタムセッション
            // 初回接続テストでは証明書を取得するために検証をバイパス
            // 取得した証明書情報をユーザーに確認してもらい、信頼後はピンニングで検証
            testConnectionDelegate.reset() // 前回の接続テスト結果をクリア
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: config, delegate: testConnectionDelegate, delegateQueue: nil)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkError("Invalid response"))
            }

            // 証明書フィンガープリントを取得（Delegateから）
            let detectedFingerprint = testConnectionDelegate.lastFingerprint
            let detectedCertData = testConnectionDelegate.lastCertificateData

            switch httpResponse.statusCode {
            case 200..<300:
                // 証明書情報をデコード
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if var info = try? decoder.decode(CertificateInfo.self, from: data) {
                    // TLS接続から取得したフィンガープリントも保持
                    if let detected = detectedFingerprint {
                        // サーバーが返したものとTLS接続のものが一致するか確認
                        // 一致しない場合は中間者攻撃の可能性
                        if !info.fingerprint.isEmpty && info.fingerprint != detected {
                            print("[ServerSettingsViewModel] WARNING: Fingerprint mismatch!")
                            print("  From TLS: \(detected)")
                            print("  From API: \(info.fingerprint)")
                        }
                        // TLS接続から取得したものを優先（より信頼性が高い）
                        info = CertificateInfo(
                            fingerprint: detected,
                            commonName: info.commonName,
                            validFrom: info.validFrom,
                            validUntil: info.validUntil,
                            issuer: info.issuer,
                            serialNumber: info.serialNumber,
                            isSelfSigned: info.isSelfSigned,
                            pendingRestart: info.pendingRestart,
                            pendingFingerprint: info.pendingFingerprint
                        )
                    }
                    return .success(info)
                }
                // API応答がデコードできなくても、TLSから証明書情報を取得できていれば成功
                if let detected = detectedFingerprint {
                    let info = CertificateInfo(
                        fingerprint: detected,
                        commonName: nil,
                        validFrom: nil,
                        validUntil: nil,
                        issuer: nil,
                        serialNumber: nil,
                        isSelfSigned: true,
                        pendingRestart: nil,
                        pendingFingerprint: nil
                    )
                    return .success(info)
                }
                return .success(nil)

            case 401, 403:
                return .failure(.authenticationError)

            default:
                return .failure(.serverError(statusCode: httpResponse.statusCode))
            }
        } catch let error as URLError {
            // 証明書エラーの場合
            if error.code == .serverCertificateUntrusted ||
               error.code == .serverCertificateHasBadDate ||
               error.code == .serverCertificateHasUnknownRoot {
                return .failure(.certificateError(error.localizedDescription))
            }
            return .failure(.networkError(error.localizedDescription))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }

    /// 接続成功時の処理
    private func handleConnectionSuccess(url: String, certificateInfo info: CertificateInfo?) async {
        // TLS接続から取得した証明書DERデータを保持
        let certData = testConnectionDelegate.lastCertificateData

        // 証明書情報を取得
        if let info = info {
            // 保存済みフィンガープリントと比較
            if let savedFingerprint = store.currentConfiguration?.certificateFingerprint,
               store.currentConfiguration?.isTrusted == true {
                if savedFingerprint == info.fingerprint {
                    // 一致: 接続成功
                    certificateInfo = info
                    connectionStatus = .success(connectedURL: url)
                    store.updateLastConnected(url: url)
                } else {
                    // 不一致: 証明書変更警告
                    pendingCertificateInfo = info
                    pendingCertificateData = certData
                    showCertificateChangedAlert = true
                    connectionStatus = .failed(error: .certificateError("証明書が変更されました"))
                }
            } else {
                // 未保存: 新規証明書確認
                pendingCertificateInfo = info
                pendingCertificateData = certData
                certificateInfo = info
                showCertificateAlert = true
            }
        } else {
            // 証明書情報なし（商用証明書の場合など）
            connectionStatus = .success(connectedURL: url)
            store.updateLastConnected(url: url)
        }
    }
}

// MARK: - URL Validation Extension

extension ServerSettingsViewModel {
    /// メインURLの有効性チェック
    var isValidMainURL: Bool {
        guard let url = URL(string: serverURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    /// APIキーの有効性チェック
    var isValidAPIKey: Bool {
        !apiKey.isEmpty
    }

    /// 保存可能かどうか
    var canSave: Bool {
        isValidMainURL && isValidAPIKey
    }
}

// MARK: - Test Connection Delegate

/// 接続テスト用のURLSessionDelegate
/// 自己署名証明書を許可し、証明書情報を取得する
final class TestConnectionDelegate: NSObject, URLSessionDelegate {
    /// 最後に取得した証明書のフィンガープリント
    private(set) var lastFingerprint: String?

    /// 最後に取得した証明書データ
    private(set) var lastCertificateData: Data?

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 証明書フィンガープリントを抽出
        if let fingerprint = CertificateValidator.extractFingerprint(from: serverTrust) {
            lastFingerprint = fingerprint
        }

        // 証明書データを抽出
        if let certData = CertificateValidator.extractCertificateData(from: serverTrust) {
            lastCertificateData = certData
        }

        // ホスト名検証をスキップ: 接続テストではIPアドレスでもドメイン名でも許可
        // BasicX509ポリシーでホスト名検証を無効化
        let policy = SecPolicyCreateBasicX509()
        SecTrustSetPolicies(serverTrust, policy)

        // 接続テストでは全ての証明書を許可（ユーザー確認前）
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }

    /// 状態をリセット
    func reset() {
        lastFingerprint = nil
        lastCertificateData = nil
    }
}
