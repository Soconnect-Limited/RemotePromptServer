import Foundation
import SwiftUI
import Combine

@MainActor
final class RoomSettingsViewModel: ObservableObject {
    @Published var settings: RoomSettings = .default
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let room: Room
    let runner: String
    private let apiClient: APIClientProtocol
    private let deviceId: String

    init(room: Room, runner: String, apiClient: APIClientProtocol = APIClient.shared, deviceId: String = APIClient.getDeviceId()) {
        self.room = room
        self.runner = runner
        self.apiClient = apiClient
        self.deviceId = deviceId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if let fetched = try await apiClient.getRoomSettings(roomId: room.id, deviceId: deviceId) {
                settings = fetched
            } else {
                settings = .default
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            // サーバーから最新の全設定を取得してマージ
            let currentSettings = try await apiClient.getRoomSettings(roomId: room.id, deviceId: deviceId) ?? .default

            // 編集中のrunner設定のみ更新、他のrunnerはそのまま
            let mergedSettings: RoomSettings
            switch runner {
            case "claude":
                mergedSettings = RoomSettings(claude: settings.claude, codex: currentSettings.codex, gemini: currentSettings.gemini)
            case "codex":
                mergedSettings = RoomSettings(claude: currentSettings.claude, codex: settings.codex, gemini: currentSettings.gemini)
            case "gemini":
                mergedSettings = RoomSettings(claude: currentSettings.claude, codex: currentSettings.codex, gemini: settings.gemini)
            default:
                mergedSettings = settings
            }

            _ = try await apiClient.updateRoomSettings(roomId: room.id, deviceId: deviceId, settings: mergedSettings)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resetToDefault() {
        settings = .default
    }

    func setDefaultToServer() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await apiClient.updateRoomSettings(roomId: room.id, deviceId: deviceId, settings: nil)
            settings = .default
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
