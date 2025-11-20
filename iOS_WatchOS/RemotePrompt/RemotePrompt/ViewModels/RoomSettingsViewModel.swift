import Foundation
import SwiftUI
import Combine

@MainActor
final class RoomSettingsViewModel: ObservableObject {
    @Published var settings: RoomSettings = .default
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let room: Room
    private let apiClient: APIClientProtocol
    private let deviceId: String

    init(room: Room, apiClient: APIClientProtocol = APIClient.shared, deviceId: String = APIClient.getDeviceId()) {
        self.room = room
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
            _ = try await apiClient.updateRoomSettings(roomId: room.id, deviceId: deviceId, settings: settings)
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
