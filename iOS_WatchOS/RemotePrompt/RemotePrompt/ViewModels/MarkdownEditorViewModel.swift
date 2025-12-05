import Foundation
import Combine

@MainActor
final class MarkdownEditorViewModel: ObservableObject {
    @Published var fileContent: String = ""
    @Published var originalContent: String = ""
    @Published var isSaving = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let roomId: String
    private let deviceId: String
    private let fileService: FileService

    init(roomId: String, deviceId: String = APIClient.getDeviceId(), fileService: FileService = FileService()) {
        self.roomId = roomId
        self.deviceId = deviceId
        self.fileService = fileService
    }

    var isDirty: Bool { fileContent != originalContent }

    func loadFile(path: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let content = try await fileService.readFile(roomId: roomId, path: path, deviceId: deviceId)
            await MainActor.run {
                self.fileContent = content
                self.originalContent = content
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func saveFile(path: String) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        do {
            try await fileService.saveFile(roomId: roomId, path: path, content: fileContent, deviceId: deviceId)
            await MainActor.run {
                self.originalContent = self.fileContent
                self.isSaving = false
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isSaving = false
            }
            return false
        }
    }

    func discardChanges() {
        fileContent = originalContent
    }

    /// 状態をリセット（別のファイルに切り替える前に呼ぶ）
    func reset() {
        fileContent = ""
        originalContent = ""
        errorMessage = nil
        isLoading = false
        isSaving = false
    }
}
