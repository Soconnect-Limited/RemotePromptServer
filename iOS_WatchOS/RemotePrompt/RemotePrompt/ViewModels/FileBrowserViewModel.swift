import Foundation
import SwiftUI

@MainActor
final class FileBrowserViewModel: ObservableObject {
    @Published var currentPath: String = ""
    @Published var pathComponents: [String] = []
    @Published var fileItems: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showRetry = false

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
            await MainActor.run {
                self.fileItems = items
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
}
