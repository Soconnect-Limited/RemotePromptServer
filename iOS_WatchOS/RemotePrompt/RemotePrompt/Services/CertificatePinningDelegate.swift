import Foundation
import Security
import Combine

/// 証明書エラーの種類
enum CertificateErrorType: Equatable {
    case mismatch(storedFingerprint: String, receivedFingerprint: String)
    case extractionFailed
    case noTrustedCertificate
}

/// 証明書エラー通知の情報
struct CertificateErrorInfo {
    let type: CertificateErrorType
    let serverTrust: SecTrust?
    let fingerprint: String?
}

/// 自己署名証明書用のURLSessionDelegate
/// 保存済みフィンガープリントと照合して接続を許可/拒否する
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    // MARK: - Singleton

    static let shared = CertificatePinningDelegate()

    // MARK: - Notifications

    static let certificateMismatchNotification = Notification.Name("CertificateMismatchDetected")
    static let certificateErrorNotification = Notification.Name("CertificateErrorDetected")

    // MARK: - Properties

    private let store: ServerConfigurationStore

    /// 証明書検証をバイパスするかどうか（接続テスト用）
    var bypassValidation: Bool = false

    /// 最後に検出した証明書エラー（UI表示用）
    @Published private(set) var lastCertificateError: CertificateErrorInfo?

    // MARK: - Callbacks

    /// 新規証明書検出時のコールバック（設定画面で使用）
    var onNewCertificateDetected: ((String, Data, @escaping (Bool) -> Void) -> Void)?

    /// 証明書不一致検出時のコールバック（設定画面で使用）
    var onCertificateMismatchDetected: ((String, String, @escaping (Bool) -> Void) -> Void)?

    // MARK: - Initialization

    private override init() {
        self.store = .shared
        super.init()
    }

    // For testing
    init(store: ServerConfigurationStore) {
        self.store = store
        super.init()
    }

    // MARK: - Public Methods

    func onNewCertificate(_ handler: @escaping (String, Data, @escaping (Bool) -> Void) -> Void) {
        self.onNewCertificateDetected = handler
    }

    func onCertificateMismatch(_ handler: @escaping (String, String, @escaping (Bool) -> Void) -> Void) {
        self.onCertificateMismatchDetected = handler
    }

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[CertificatePinningDelegate] urlSession didReceive START @ \(Date()) isMainThread: \(Foundation.Thread.isMainThread)")

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            print("[CertificatePinningDelegate] performDefaultHandling @ \(Date())")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // バイパスモードの場合は無条件で信頼（接続テスト用）
        if bypassValidation {
            print("[CertificatePinningDelegate] Bypass mode - accepting certificate")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }

        // 証明書のフィンガープリントを取得
        guard let receivedFingerprint = CertificateValidator.extractFingerprint(from: serverTrust) else {
            print("[CertificatePinningDelegate] Failed to extract fingerprint")
            // 即座にエラーを通知
            notifyCertificateError(.extractionFailed, fingerprint: nil)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 保存済みフィンガープリントを確認
        guard let config = store.currentConfiguration,
              config.isTrusted,
              let storedFingerprint = config.certificateFingerprint else {
            // 信頼済み設定がない場合
            print("[CertificatePinningDelegate] No trusted certificate stored")

            // コールバックが設定されていれば呼び出す（設定画面から）
            if let handler = onNewCertificateDetected,
               let certData = CertificateValidator.extractCertificateData(from: serverTrust) {
                handler(receivedFingerprint, certData) { trusted in
                    if trusted {
                        let credential = URLCredential(trust: serverTrust)
                        completionHandler(.useCredential, credential)
                    } else {
                        completionHandler(.cancelAuthenticationChallenge, nil)
                    }
                }
            } else {
                // コールバック未設定 → 自己署名証明書を一時的に受け入れる
                // （初回接続時のみ。設定画面で正式に信頼を設定する）
                print("[CertificatePinningDelegate] Temporarily accepting self-signed certificate")
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            }
            return
        }

        // フィンガープリント比較
        if storedFingerprint.uppercased() == receivedFingerprint.uppercased() {
            // 一致 → 即座に接続許可
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("[CertificatePinningDelegate] Certificate fingerprint matched in \(String(format: "%.3f", elapsed))s @ \(Date())")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // 不一致 → 警告（即座に通知）
            print("[CertificatePinningDelegate] Certificate fingerprint MISMATCH!")
            print("  Stored: \(storedFingerprint)")
            print("  Received: \(receivedFingerprint)")

            // 即座にミスマッチを通知（待たせない）
            notifyCertificateMismatch(stored: storedFingerprint, received: receivedFingerprint)

            if let handler = onCertificateMismatchDetected {
                handler(storedFingerprint, receivedFingerprint) { trustNew in
                    if trustNew {
                        let credential = URLCredential(trust: serverTrust)
                        completionHandler(.useCredential, credential)
                    } else {
                        completionHandler(.cancelAuthenticationChallenge, nil)
                    }
                }
            } else {
                // ハンドラ未設定 → セキュリティのため即座に拒否
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    // MARK: - Private Methods

    /// 証明書エラーを即座に通知
    private func notifyCertificateError(_ type: CertificateErrorType, fingerprint: String?) {
        let info = CertificateErrorInfo(type: type, serverTrust: nil, fingerprint: fingerprint)
        lastCertificateError = info

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.certificateErrorNotification,
                object: info
            )
        }
    }

    /// 証明書ミスマッチを即座に通知
    private func notifyCertificateMismatch(stored: String, received: String) {
        let info = CertificateErrorInfo(
            type: .mismatch(storedFingerprint: stored, receivedFingerprint: received),
            serverTrust: nil,
            fingerprint: received
        )
        lastCertificateError = info

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.certificateMismatchNotification,
                object: info,
                userInfo: [
                    "storedFingerprint": stored,
                    "receivedFingerprint": received
                ]
            )
        }
    }

    /// エラー状態をクリア
    func clearError() {
        lastCertificateError = nil
    }
}
