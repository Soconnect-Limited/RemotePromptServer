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
                Text("このQRコードを別のデバイスでスキャンして設定をインポートしてください")
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
                    Text("QRコードを生成できませんでした")
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("共有される設定:")
                        .font(.headline)

                    if let config = ServerConfigurationStore.shared.currentConfiguration {
                        Group {
                            LabeledContent("サーバーURL", value: config.url)
                            LabeledContent("デバイスID", value: String(APIClient.getDeviceId().prefix(8)) + "...")
                            if !config.alternativeURLs.isEmpty {
                                LabeledContent("代替URL", value: "\(config.alternativeURLs.count)件")
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
            .navigationTitle("設定を共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
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
}

#Preview {
    SettingsQRCodeView()
}
