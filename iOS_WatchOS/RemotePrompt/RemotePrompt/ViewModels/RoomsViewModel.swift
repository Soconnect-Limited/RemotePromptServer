import Foundation
import Combine
import SwiftUI

@MainActor
final class RoomsViewModel: ObservableObject {
    @Published var rooms: [Room]
    @Published var isLoading = false
    @Published var errorMessage: String?

    let apiClient: APIClientProtocol
    private let deviceId: String
    private let shouldValidateAPIKey: Bool

    init(
        apiClient: APIClientProtocol = APIClient.shared,
        deviceIdProvider: @escaping () -> String = APIClient.getDeviceId,
        skipAPIKeyCheck: Bool = false,
        initialRooms: [Room] = []
    ) {
        self.apiClient = apiClient
        self.deviceId = deviceIdProvider()
        self.shouldValidateAPIKey = !skipAPIKeyCheck
        self.rooms = initialRooms
    }

    func loadRooms() async {
        guard ensureAPIKeyConfigured() else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await apiClient.fetchRooms(deviceId: deviceId)
            rooms = sortRooms(fetched)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createRoom(name: String, workspacePath: String, icon: String) async -> Room? {
        guard ensureAPIKeyConfigured() else { return nil }
        do {
            let room = try await apiClient.createRoom(
                name: name,
                workspacePath: workspacePath,
                deviceId: deviceId,
                icon: icon
            )
            rooms = sortRooms(rooms + [room])
            return room
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateRoom(_ room: Room, name: String, workspacePath: String, icon: String) async -> Room? {
        guard ensureAPIKeyConfigured() else { return nil }
        do {
            let updated = try await apiClient.updateRoom(
                roomId: room.id,
                name: name,
                workspacePath: workspacePath,
                deviceId: deviceId,
                icon: icon
            )
            rooms = sortRooms(rooms.map { $0.id == updated.id ? updated : $0 })
            return updated
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteRoom(_ room: Room) async -> Bool {
        guard ensureAPIKeyConfigured() else { return false }
        do {
            try await apiClient.deleteRoom(roomId: room.id, deviceId: deviceId)
            rooms.removeAll { $0.id == room.id }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// ドラッグ＆ドロップでの並べ替え
    func moveRoom(from source: IndexSet, to destination: Int) {
        rooms.move(fromOffsets: source, toOffset: destination)
        // サーバーに並び順を保存
        Task {
            await saveRoomOrder()
        }
    }

    /// 現在のrooms配列の順序をサーバーに保存
    private func saveRoomOrder() async {
        guard ensureAPIKeyConfigured() else { return }
        let roomIds = rooms.map { $0.id }
        do {
            try await apiClient.reorderRooms(deviceId: deviceId, roomIds: roomIds)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureAPIKeyConfigured() -> Bool {
        guard shouldValidateAPIKey else { return true }
        guard Constants.isAPIKeyConfigured else {
            errorMessage = Constants.missingAPIKeyMessage
            return false
        }
        return true
    }

    private func sortRooms(_ rooms: [Room]) -> [Room] {
        // sort_orderでソート（サーバーから返される順序を維持）
        rooms.sorted { $0.sortOrder < $1.sortOrder }
    }
}
