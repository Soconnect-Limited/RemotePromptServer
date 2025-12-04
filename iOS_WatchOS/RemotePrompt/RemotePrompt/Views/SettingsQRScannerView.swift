import SwiftUI
import AVFoundation

/// 設定インポート用QRコードスキャナーView
struct SettingsQRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannedData: SettingsShareData?
    @State private var showImportConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerRepresentable { result in
                    handleScan(result: result)
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()

                    VStack(spacing: 16) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.white)

                        Text("別のデバイスで表示されたQRコードをスキャンしてください")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .padding()

                    Spacer()
                }
            }
            .navigationTitle("設定をインポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
            .alert("設定をインポート", isPresented: $showImportConfirmation) {
                Button("キャンセル", role: .cancel) {
                    scannedData = nil
                }
                Button("インポート") {
                    importSettings()
                }
            } message: {
                if let data = scannedData {
                    Text("以下の設定をインポートしますか？\n\nサーバー: \(data.serverURL)\nデバイスID: \(String(data.deviceId.prefix(8)))...")
                }
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "不明なエラーが発生しました")
            }
        }
    }

    private func handleScan(result: Result<String, Error>) {
        switch result {
        case .success(let code):
            guard let data = code.data(using: .utf8),
                  let shareData = try? JSONDecoder().decode(SettingsShareData.self, from: data) else {
                errorMessage = "無効なQRコードです"
                showError = true
                return
            }
            scannedData = shareData
            showImportConfirmation = true

        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func importSettings() {
        guard let data = scannedData else { return }

        // 設定を保存
        var config = ServerConfigurationStore.shared.currentConfiguration ?? ServerConfiguration(
            name: "",
            url: "",
            apiKey: ""
        )

        config.url = data.serverURL
        config.apiKey = data.apiKey
        config.alternativeURLs = data.alternativeURLs
        config.autoFallback = data.autoFallback
        config.certificateFingerprint = data.certificateFingerprint

        ServerConfigurationStore.shared.save(config)

        // デバイスIDを保存
        UserDefaults.standard.set(data.deviceId, forKey: "device_id")

        // APIClient のセッションを無効化して再接続を促す
        APIClient.shared.invalidateSession()

        dismiss()
    }
}

/// QRコードスキャナーのUIKit表現
struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

/// QRコードスキャナーViewController
class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((Result<String, Error>) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            onScan?(.failure(NSError(domain: "QRScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "カメラにアクセスできません"])))
            return
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            onScan?(.failure(error))
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            onScan?(.failure(NSError(domain: "QRScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "カメラ入力を追加できません"])))
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            onScan?(.failure(NSError(domain: "QRScanner", code: 3, userInfo: [NSLocalizedDescriptionKey: "メタデータ出力を追加できません"])))
            return
        }

        captureSession = session

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned else { return }

        if let metadataObject = metadataObjects.first,
           let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
           let stringValue = readableObject.stringValue {
            hasScanned = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onScan?(.success(stringValue))
        }
    }
}

#Preview {
    SettingsQRScannerView()
}
