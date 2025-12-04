import SwiftUI
import CoreImage.CIFilterBuiltins

/// 設定共有用QRコード表示View
struct SettingsQRCodeView: View {
    @Environment(\.dismiss) private var dismiss

    private let qrCodeGenerator = CIFilter.qrCodeGenerator()
    private let context = CIContext()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(L10n.QR.shareHint)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let qrImage = generateQRCode() {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                } else {
                    Text(L10n.QR.generateFailed)
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.QR.shareInfo)
                        .font(.headline)

                    if let config = ServerConfigurationStore.shared.currentConfiguration {
                        Group {
                            LabeledContent(L10n.QR.shareServerUrl, value: config.url)
                            LabeledContent(L10n.QR.shareDeviceId, value: String(APIClient.getDeviceId().prefix(8)) + "...")
                            if !config.alternativeURLs.isEmpty {
                                LabeledContent(L10n.QR.shareAltUrls, value: L10n.QR.shareAltUrlsCount(config.alternativeURLs.count))
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                Spacer()
            }
            .padding()
            .navigationTitle(L10n.QR.shareTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func generateQRCode() -> UIImage? {
        guard let config = ServerConfigurationStore.shared.currentConfiguration else {
            return nil
        }

        // 共有データを作成
        let shareData = SettingsShareData(
            serverURL: config.url,
            apiKey: config.apiKey,
            deviceId: APIClient.getDeviceId(),
            alternativeURLs: config.alternativeURLs,
            autoFallback: config.autoFallback,
            certificateFingerprint: config.certificateFingerprint
        )

        guard let jsonData = try? JSONEncoder().encode(shareData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        // QRコード生成
        qrCodeGenerator.setValue(jsonString.data(using: .utf8), forKey: "inputMessage")
        qrCodeGenerator.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = qrCodeGenerator.outputImage else {
            return nil
        }

        // スケールアップ
        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

/// 設定共有用データ構造
struct SettingsShareData: Codable {
    let serverURL: String
    let apiKey: String
    let deviceId: String
    let alternativeURLs: [String]
    let autoFallback: Bool
    let certificateFingerprint: String?

    // スキーム識別子
    static let scheme = "remoteprompt"

    enum CodingKeys: String, CodingKey {
        case serverURL = "server_url"
        case apiKey = "api_key"
        case deviceId = "device_id"
        case alternativeURLs = "alternative_urls"
        case autoFallback = "auto_fallback"
        case certificateFingerprint = "certificate_fingerprint"
    }
}

#Preview {
    SettingsQRCodeView()
}
