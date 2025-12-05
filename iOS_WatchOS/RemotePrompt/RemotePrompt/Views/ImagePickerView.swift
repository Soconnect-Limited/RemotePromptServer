import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 画像選択のソース
enum ImagePickerSource {
    case photoLibrary
    case camera
}

/// 選択された画像データ
struct SelectedImage: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
}

/// サイズ超過時の画像情報
struct OversizedImage {
    let image: UIImage
    let originalData: Data
    let filename: String
    let originalSize: Int
}

/// PHPicker（カメラロール）とカメラの両方をサポートするImagePicker
struct ImagePickerView: UIViewControllerRepresentable {
    let source: ImagePickerSource
    let onImagesSelected: ([SelectedImage]) -> Void
    let onOversizedImages: ([OversizedImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .photoLibrary:
            // PHPhotoLibraryを使用してassetIdentifierを取得可能にする
            var config = PHPickerConfiguration(photoLibrary: .shared())
            config.filter = .images
            config.selectionLimit = 0  // 0 = 無制限
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        case .camera:
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImagesSelected: onImagesSelected,
            onOversizedImages: onOversizedImages,
            onCancel: onCancel
        )
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagesSelected: ([SelectedImage]) -> Void
        let onOversizedImages: ([OversizedImage]) -> Void
        let onCancel: () -> Void

        /// 最大ファイルサイズ（100MB）
        static let maxFileSize = 100_000_000

        init(
            onImagesSelected: @escaping ([SelectedImage]) -> Void,
            onOversizedImages: @escaping ([OversizedImage]) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onImagesSelected = onImagesSelected
            self.onOversizedImages = onOversizedImages
            self.onCancel = onCancel
        }

        // MARK: - PHPickerViewControllerDelegate

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Note: SwiftUIのsheet経由で表示されているため、picker.dismiss()は呼ばない
            // SwiftUIのshowingImagePicker = falseでシートが閉じる

            guard !results.isEmpty else {
                onCancel()
                return
            }

            // 複数画像を処理
            let group = DispatchGroup()
            var selectedImages: [SelectedImage] = []
            var oversizedImages: [OversizedImage] = []
            let lock = NSLock()

            for (index, result) in results.enumerated() {
                // アセットからファイル名を取得
                let identifier = result.assetIdentifier
                var filename = "image_\(Int(Date().timeIntervalSince1970))_\(index).jpg"

                if let identifier = identifier {
                    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                    if let asset = fetchResult.firstObject {
                        let resources = PHAssetResource.assetResources(for: asset)
                        if let resource = resources.first {
                            filename = resource.originalFilename
                        }
                    }
                }

                // 元のファイルデータをそのまま取得（変換なし）
                group.enter()
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
                    defer { group.leave() }
                    guard let self = self, let url = url else {
                        return
                    }

                    do {
                        let data = try Data(contentsOf: url)
                        let ext = (filename as NSString).pathExtension.lowercased()

                        // 拡張子がない場合はURLから取得
                        var finalFilename = filename
                        if ext.isEmpty {
                            let urlExt = url.pathExtension.lowercased()
                            if !urlExt.isEmpty {
                                finalFilename = filename + "." + urlExt
                            } else {
                                finalFilename = filename + ".jpg"
                            }
                        }

                        lock.lock()
                        if data.count > Self.maxFileSize {
                            // 100MB超過 - UIImageが必要なのでここで読み込む
                            if let image = UIImage(data: data) {
                                oversizedImages.append(OversizedImage(
                                    image: image,
                                    originalData: data,
                                    filename: finalFilename,
                                    originalSize: data.count
                                ))
                            }
                        } else {
                            // サイズOK
                            selectedImages.append(SelectedImage(data: data, filename: finalFilename))
                        }
                        lock.unlock()
                    } catch {
                        print("[ImagePickerView] Failed to load file data: \(error)")
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }

                // サイズOKの画像があれば先にアップロード
                if !selectedImages.isEmpty {
                    self.onImagesSelected(selectedImages)
                }

                // サイズ超過の画像があればアラート表示（サイズOKの画像処理後）
                if !oversizedImages.isEmpty {
                    // 少し遅延させてシート閉じを待つ
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.onOversizedImages(oversizedImages)
                    }
                }

                // 何も処理できなかった場合のみキャンセル
                if selectedImages.isEmpty && oversizedImages.isEmpty {
                    self.onCancel()
                }
            }
        }

        // MARK: - UIImagePickerControllerDelegate

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Note: SwiftUIのsheet経由で表示されているため、picker.dismiss()は呼ばない
            // SwiftUIのshowingImagePicker = falseでシートが閉じる

            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }

            // カメラで撮影した画像はJPEGで保存
            let filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"

            guard let data = image.jpegData(compressionQuality: 0.9) else {
                onCancel()
                return
            }

            // サイズチェック
            if data.count > Self.maxFileSize {
                // 100MB超過 → ユーザーに選択させる
                onOversizedImages([OversizedImage(
                    image: image,
                    originalData: data,
                    filename: filename,
                    originalSize: data.count
                )])
            } else {
                // サイズOK → そのままアップロード
                onImagesSelected([SelectedImage(data: data, filename: filename)])
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            // Note: SwiftUIのsheet経由で表示されているため、picker.dismiss()は呼ばない
            // SwiftUIのshowingImagePicker = falseでシートが閉じる
            onCancel()
        }
    }
}

/// 画像を100MB以内に圧縮するユーティリティ
func compressImageToFitSize(_ image: UIImage, maxSize: Int) -> Data? {
    var quality: CGFloat = 0.8
    var data = image.jpegData(compressionQuality: quality)

    // サイズが制限内になるまで圧縮率を下げる
    while let imageData = data, imageData.count > maxSize, quality > 0.1 {
        quality -= 0.1
        data = image.jpegData(compressionQuality: quality)
    }

    return data
}

/// 画像ソース選択用のActionSheet表示
struct ImageSourceActionSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedSource: ImagePickerSource?
    @State private var showingPicker = false

    var body: some View {
        EmptyView()
            .confirmationDialog("画像を追加", isPresented: $isPresented, titleVisibility: .visible) {
                Button("フォトライブラリから選択") {
                    selectedSource = .photoLibrary
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("カメラで撮影") {
                        selectedSource = .camera
                    }
                }
                Button("キャンセル", role: .cancel) {
                    selectedSource = nil
                }
            }
    }
}
