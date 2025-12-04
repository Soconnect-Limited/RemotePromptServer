import Foundation
import Combine
import PDFKit

@MainActor
final class PDFViewerViewModel: ObservableObject {
    @Published var pdfDocument: PDFDocument?
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

    func loadPDF(path: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let data = try await fileService.readPDFFile(roomId: roomId, path: path, deviceId: deviceId)
            await MainActor.run {
                if let document = PDFDocument(data: data) {
                    self.pdfDocument = document
                } else {
                    self.errorMessage = "PDFの読み込みに失敗しました"
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
