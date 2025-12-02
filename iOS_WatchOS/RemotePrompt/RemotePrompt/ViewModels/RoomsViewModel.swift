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
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[RoomsViewModel] loadRooms START @ \(Date())")
        guard ensureAPIKeyConfigured() else {
            print("[RoomsViewModel] API key not configured")
            return
        }
        isLoading = true
        defer {
            isLoading = false
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("[RoomsViewModel] loadRooms TOTAL: \(String(format: "%.2f", elapsed))s")
        }

        do {
            let t1 = CFAbsoluteTimeGetCurrent()
            print("[RoomsViewModel] calling fetchRooms...")
            let fetched = try await apiClient.fetchRooms(deviceId: deviceId)
            let t2 = CFAbsoluteTimeGetCurrent()
            print("[RoomsViewModel] fetchRooms returned \(fetched.count) rooms in \(String(format: "%.2f", t2 - t1))s")

            // 明示的にMainActorで更新（objectWillChangeを強制発火）
            let sorted = sortRooms(fetched)
            objectWillChange.send()
            rooms = sorted
            print("[RoomsViewModel] rooms assigned @ \(Date()), count=\(rooms.count)")

            // 次のRunLoopで確認
            DispatchQueue.main.async {
                print("[RoomsViewModel] 🔄 Main queue callback after assignment @ \(Date())")
            }
        } catch {
            print("[RoomsViewModel] error: \(error)")
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
