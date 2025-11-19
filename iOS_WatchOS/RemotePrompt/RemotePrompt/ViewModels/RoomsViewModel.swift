import Foundation

@MainActor
final class RoomsViewModel: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient = APIClient.shared
    private let deviceId = APIClient.getDeviceId()

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

    private func ensureAPIKeyConfigured() -> Bool {
        guard Constants.isAPIKeyConfigured else {
            errorMessage = Constants.missingAPIKeyMessage
            return false
        }
        return true
    }

    private func sortRooms(_ rooms: [Room]) -> [Room] {
        rooms.sorted { lhs, rhs in
            let leftDate = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
            let rightDate = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
            return leftDate > rightDate
        }
    }
}
