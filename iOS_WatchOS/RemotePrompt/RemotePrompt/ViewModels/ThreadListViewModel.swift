import Foundation
import SwiftUI
import Combine

/// スレッド一覧の状態管理を行うViewModel
@MainActor
final class ThreadListViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let roomId: String
    private let runnerFilter: String?
    private let defaultRunner: String
    private let deviceId: String

    init(
        roomId: String,
        runner: String? = nil,
        deviceId: String = APIClient.getDeviceId(),
        apiClient: APIClientProtocol = APIClient.shared
    ) {
        self.roomId = roomId
        self.runnerFilter = runner
        self.defaultRunner = runner ?? "claude"
        self.deviceId = deviceId
        self.apiClient = apiClient
    }

    /// スレッド一覧を取得
    func fetchThreads() async {
        isLoading = true
        errorMessage = nil

        do {
            // v4.1: サーバー側runnerフィルタリングに対応
            threads = try await apiClient.fetchThreads(
                roomId: roomId,
                deviceId: deviceId,
                runner: runnerFilter
            )
        } catch {
            errorMessage = "スレッド取得失敗: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// 新しいスレッドを作成
    func createThread(name: String, runner: String? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            let newThread = try await apiClient.createThread(
                roomId: roomId,
                name: name,
                runner: runner ?? defaultRunner,
                deviceId: deviceId
            )
            threads.insert(newThread, at: 0)
        } catch {
            errorMessage = "スレッド作成失敗: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// スレッド名を更新
    func updateThreadName(threadId: String, newName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let updatedThread = try await apiClient.updateThread(
                threadId: threadId,
                name: newName,
                deviceId: deviceId
            )
            if let index = threads.firstIndex(where: { $0.id == threadId }) {
                threads[index] = updatedThread
            }
        } catch {
            errorMessage = "スレッド名更新失敗: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// スレッドを削除
    func deleteThread(threadId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await apiClient.deleteThread(threadId: threadId, deviceId: deviceId)
            threads.removeAll { $0.id == threadId }
        } catch {
            errorMessage = "スレッド削除失敗: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
