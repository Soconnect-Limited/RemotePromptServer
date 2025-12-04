import SwiftUI

/// 初回接続時の証明書確認ダイアログ
struct CertificateConfirmationView: View {
    let fingerprint: String
    let onTrust: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // 警告アイコン
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            // タイトル
            Text(L10n.Certificate.verifyFailed)
                .font(.headline)
                .multilineTextAlignment(.center)

            // 説明
            Text(L10n.Certificate.verifyHint)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // フィンガープリント表示
            VStack(spacing: 8) {
                Text(L10n.Certificate.sha256)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(fingerprint)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }

            // ボタン
            VStack(spacing: 12) {
                Button {
                    onTrust()
                } label: {
                    Text(L10n.Certificate.trustConnect)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onCancel()
                } label: {
                    Text(L10n.Common.cancel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

/// 証明書変更検知時の警告ダイアログ
struct CertificateChangedAlertView: View {
    let oldFingerprint: String
    let newFingerprint: String
    let onTrustNew: () -> Void
    let onCancel: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // 警告アイコン
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            // タイトル
            Text(L10n.Certificate.changedTitle)
                .font(.headline)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)

            // 警告メッセージ
            VStack(spacing: 8) {
                Text(L10n.Certificate.mitm)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)

                Text(L10n.Certificate.contactAdmin)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // フィンガープリント比較
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Certificate.oldFingerprint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(shortFingerprint(oldFingerprint))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Certificate.newFingerprint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(shortFingerprint(newFingerprint))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // ボタン
            VStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text(L10n.Certificate.cancelConnection)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    onTrustNew()
                } label: {
                    Text(L10n.Certificate.trustNew)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button {
                    onReset()
                } label: {
                    Text(L10n.Certificate.discardSaved)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .font(.footnote)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func shortFingerprint(_ fingerprint: String) -> String {
        let components = fingerprint.split(separator: ":")
        if components.count >= 8 {
            let first4 = components.prefix(4).joined(separator: ":")
            let last4 = components.suffix(4).joined(separator: ":")
            return "\(first4)...\(last4)"
        }
        return fingerprint
    }
}

// MARK: - Preview

#Preview("Certificate Confirmation") {
    CertificateConfirmationView(
        fingerprint: "A1:B2:C3:D4:E5:F6:G7:H8:I9:J0:K1:L2:M3:N4:O5:P6:Q1:R2:S3:T4:U5:V6:W7:X8:Y9:Z0:A1:B2:C3:D4:E5:F6",
        onTrust: {},
        onCancel: {}
    )
}

#Preview("Certificate Changed Alert") {
    CertificateChangedAlertView(
        oldFingerprint: "A1:B2:C3:D4:E5:F6:G7:H8:I9:J0:K1:L2:M3:N4:O5:P6:Q1:R2:S3:T4:U5:V6:W7:X8:Y9:Z0:A1:B2:C3:D4:E5:F6",
        newFingerprint: "X9:Y8:Z7:W6:V5:U4:T3:S2:R1:Q0:P9:O8:N7:M6:L5:K4:J3:I2:H1:G0:F9:E8:D7:C6:B5:A4:Z3:Y2:X1:W0:V9:U8",
        onTrustNew: {},
        onCancel: {},
        onReset: {}
    )
}
