import Foundation
import Combine
import SwiftUI

@MainActor
final class FileBrowserViewModel: ObservableObject {
    @Published var currentPath: String = ""
    @Published var pathComponents: [String] = []
    @Published var fileItems: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showRetry = false
    @Published var isUploading = false
    @Published var uploadProgress: String?

    private let roomId: String
    private let deviceId: String
    private let fileService: FileService

    init(room: Room, fileService: FileService = FileService(), deviceId: String = APIClient.getDeviceId()) {
        self.roomId = room.id
        self.deviceId = deviceId
        self.fileService = fileService
    }

    func loadFiles(path: String = "") async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        showRetry = false
        do {
            let items = try await fileService.listFiles(roomId: roomId, path: path, deviceId: deviceId)
            // ソート: ディレクトリ優先、その後変更日時降順（最新が上）
            let sortedItems = items.sorted { lhs, rhs in
                if lhs.type == .directory && rhs.type != .directory {
                    return true
                }
                if lhs.type != .directory && rhs.type == .directory {
                    return false
                }
                return lhs.modifiedAt > rhs.modifiedAt
            }
            await MainActor.run {
                self.fileItems = sortedItems
                self.currentPath = path
                self.pathComponents = path.split(separator: "/").map(String.init)
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showRetry = true
                self.isLoading = false
            }
        }
    }

    func navigateToDirectory(_ item: FileItem) async {
        guard item.type == .directory else { return }
        await loadFiles(path: item.path)
    }

    func navigateBack() async {
        guard !pathComponents.isEmpty else { return }
        var comps = pathComponents
        comps.removeLast()
        let newPath = comps.joined(separator: "/")
        await loadFiles(path: newPath)
    }

    var navigationTitle: String {
        currentPath.isEmpty ? "Workspace" : currentPath
    }

    // MARK: - Image Upload

    func uploadImages(_ selectedImages: [SelectedImage]) async {
        guard !isUploading else { return }
        guard !selectedImages.isEmpty else { return }

        isUploading = true
        errorMessage = nil

        let total = selectedImages.count
        var successCount = 0
        var failedCount = 0

        for (index, selectedImage) in selectedImages.enumerated() {
            await MainActor.run {
                self.uploadProgress = "アップロード中 (\(index + 1)/\(total))"
            }

            do {
                _ = try await fileService.uploadImage(
                    roomId: roomId,
                    directoryPath: currentPath,
                    filename: selectedImage.filename,
                    imageData: selectedImage.data,
                    deviceId: deviceId
                )
                successCount += 1
            } catch {
                failedCount += 1
                print("[FileBrowserViewModel] uploadImage failed: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            self.uploadProgress = nil
            self.isUploading = false
            if failedCount > 0 {
                self.errorMessage = "\(successCount)件アップロード成功、\(failedCount)件失敗"
            }
        }

        // アップロード成功後、ファイルリストを更新
        await loadFiles(path: currentPath)
    }
}
