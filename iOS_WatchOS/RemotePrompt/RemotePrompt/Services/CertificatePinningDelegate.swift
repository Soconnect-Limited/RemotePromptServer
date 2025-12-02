import Foundation
import Security

/// 証明書ピンニング用のURLSessionDelegate
/// 自己署名証明書の検証とピンニングを行う
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    // MARK: - Callback Types

    /// 新規証明書検出時のコールバック
    /// - Parameters:
    ///   - fingerprint: 新規証明書のフィンガープリント
    ///   - certificateData: 証明書データ（DER形式）
    ///   - completion: 信頼する場合は true を渡して呼び出す
    typealias NewCertificateHandler = (
        _ fingerprint: String,
        _ certificateData: Data,
        _ completion: @escaping (Bool) -> Void
    ) -> Void

    /// 証明書不一致検出時のコールバック
    /// - Parameters:
    ///   - storedFingerprint: 保存済みフィンガープリント
    ///   - receivedFingerprint: 受信した証明書のフィンガープリント
    ///   - completion: 新しい証明書を信頼する場合は true を渡して呼び出す
    typealias CertificateMismatchHandler = (
        _ storedFingerprint: String,
        _ receivedFingerprint: String,
        _ completion: @escaping (Bool) -> Void
    ) -> Void

    // MARK: - Properties

    private let store: ServerConfigurationStore
    private var newCertificateHandler: NewCertificateHandler?
    private var mismatchHandler: CertificateMismatchHandler?

    /// 証明書検証をバイパスするかどうか（接続テスト用）
    var bypassValidation: Bool = false

    // MARK: - Initialization

    init(store: ServerConfigurationStore = .shared) {
        self.store = store
        super.init()
    }

    // MARK: - Configuration

    /// 新規証明書検出時のハンドラを設定
    func onNewCertificate(_ handler: @escaping NewCertificateHandler) {
        self.newCertificateHandler = handler
    }

    /// 証明書不一致時のハンドラを設定
    func onCertificateMismatch(_ handler: @escaping CertificateMismatchHandler) {
        self.mismatchHandler = handler
    }

    // MARK: - URLSessionDelegate

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

        // バイパスモードの場合は無条件で信頼
        if bypassValidation {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }

        // 証明書のフィンガープリントを取得
        guard let receivedFingerprint = CertificateValidator.extractFingerprint(from: serverTrust),
              let certificateData = CertificateValidator.extractCertificateData(from: serverTrust) else {
            print("[CertificatePinningDelegate] Failed to extract certificate fingerprint")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 保存済み設定を確認
        guard let config = store.currentConfiguration else {
            // 設定なし → 新規証明書として処理
            handleNewCertificate(
                fingerprint: receivedFingerprint,
                certificateData: certificateData,
                serverTrust: serverTrust,
                completionHandler: completionHandler
            )
            return
        }

        // 信頼済みでない場合 → 新規証明書として処理
        guard config.isTrusted, let storedFingerprint = config.certificateFingerprint else {
            handleNewCertificate(
                fingerprint: receivedFingerprint,
                certificateData: certificateData,
                serverTrust: serverTrust,
                completionHandler: completionHandler
            )
            return
        }

        // フィンガープリント比較
        if storedFingerprint.uppercased() == receivedFingerprint.uppercased() {
            // 一致 → 接続許可
            print("[CertificatePinningDelegate] Certificate fingerprint matched")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // 不一致 → 証明書変更警告
            print("[CertificatePinningDelegate] Certificate fingerprint mismatch!")
            print("  Stored: \(storedFingerprint)")
            print("  Received: \(receivedFingerprint)")

            handleCertificateMismatch(
                storedFingerprint: storedFingerprint,
                receivedFingerprint: receivedFingerprint,
                certificateData: certificateData,
                serverTrust: serverTrust,
                completionHandler: completionHandler
            )
        }
    }

    // MARK: - Private Methods

    private func handleNewCertificate(
        fingerprint: String,
        certificateData: Data,
        serverTrust: SecTrust,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let handler = newCertificateHandler else {
            // ハンドラ未設定の場合は拒否
            print("[CertificatePinningDelegate] New certificate detected but no handler set")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        handler(fingerprint, certificateData) { trusted in
            if trusted {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    private func handleCertificateMismatch(
        storedFingerprint: String,
        receivedFingerprint: String,
        certificateData: Data,
        serverTrust: SecTrust,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let handler = mismatchHandler else {
            // ハンドラ未設定の場合は拒否
            print("[CertificatePinningDelegate] Certificate mismatch but no handler set")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        handler(storedFingerprint, receivedFingerprint) { trustNew in
            if trustNew {
                // 新しい証明書を信頼
                self.store.trustCertificate(fingerprint: receivedFingerprint, certificateData: certificateData)
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}

// MARK: - Singleton for Shared URLSession

extension CertificatePinningDelegate {
    /// 共有インスタンス（APIClient用）
    static let shared = CertificatePinningDelegate()
}
