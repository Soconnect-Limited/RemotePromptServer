//
//  RoomBasedArchitectureTests.swift
//  RemotePromptTests
//
//  Phase 2.6 Tests for Room-Based Architecture
//

import XCTest
@testable import RemotePrompt

final class RoomBasedArchitectureTests: XCTestCase {

    // MARK: - Helpers

    final class MockAPIClient: APIClientProtocol {
        var rooms: [Room] = []
        var jobsById: [String: Job] = [:]
        var fetchMessagesResponses: [Int: [Job]] = [:]
        var lastCreateJob: CreateJobRequest?

        func fetchJob(id: String) async throws -> Job {
            guard let job = jobsById[id] else { throw APIError.invalidURL }
            return job
        }

        func createJob(runner: String, prompt: String, deviceId: String, roomId: String, threadId: String? = nil) async throws -> CreateJobResponse {
            let job = Job(
                id: UUID().uuidString,
                runner: runner,
                inputText: prompt,
                deviceId: deviceId,
                roomId: roomId,
                status: "success",
                stdout: "ok",
                stderr: nil,
                exitCode: 0,
                createdAt: Date(),
                startedAt: Date(),
                finishedAt: Date()
            )
            jobsById[job.id] = job
            lastCreateJob = CreateJobRequest(runner: runner, inputText: prompt, deviceId: deviceId, roomId: roomId, notifyToken: nil, threadId: threadId)
            return CreateJobResponse(id: job.id, runner: runner, status: job.status)
        }

        func fetchRooms(deviceId: String) async throws -> [Room] {
            rooms
        }

        func createRoom(name: String, workspacePath: String, deviceId: String, icon: String) async throws -> Room {
            let room = Room(
                id: UUID().uuidString,
                name: name,
                workspacePath: workspacePath,
                icon: icon,
                deviceId: deviceId,
                createdAt: Date(),
                updatedAt: Date()
            )
            rooms.append(room)
            return room
        }

        func updateRoom(roomId: String, name: String, workspacePath: String, deviceId: String, icon: String) async throws -> Room {
            guard let idx = rooms.firstIndex(where: { $0.id == roomId }) else { throw APIError.invalidURL }
            var room = rooms[idx]
            room.name = name
            room.workspacePath = workspacePath
            room.icon = icon
            rooms[idx] = room
            return room
        }

        func deleteRoom(roomId: String, deviceId: String) async throws {
            rooms.removeAll { $0.id == roomId }
        }

        func fetchMessages(
            deviceId: String,
            roomId: String,
            runner: String,
            threadId: String?,
            limit: Int,
            offset: Int
        ) async throws -> [Job] {
            let page = fetchMessagesResponses[offset] ?? []
            return page.filter { $0.roomId == roomId && $0.runner == runner }
        }

        func getRoomSettings(roomId: String, deviceId: String) async throws -> RoomSettings? {
            nil
        }

        func updateRoomSettings(roomId: String, deviceId: String, settings: RoomSettings?) async throws -> RoomSettings? {
            settings
        }

        func fetchThreads(roomId: String, deviceId: String) async throws -> [RemotePrompt.Thread] {
            []
        }

        func createThread(roomId: String, name: String, deviceId: String) async throws -> RemotePrompt.Thread {
            RemotePrompt.Thread(
                id: UUID().uuidString,
                roomId: roomId,
                name: name,
                deviceId: deviceId,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        func updateThread(threadId: String, name: String, deviceId: String) async throws -> RemotePrompt.Thread {
            RemotePrompt.Thread(
                id: threadId,
                roomId: "test-room",
                name: name,
                deviceId: deviceId,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        func deleteThread(threadId: String, deviceId: String) async throws {
            // No-op
        }

        func reorderRooms(deviceId: String, roomIds: [String]) async throws {
            // No-op
        }

        func markThreadAsRead(threadId: String, deviceId: String, runner: String?) async throws -> RemotePrompt.Thread {
            RemotePrompt.Thread(
                id: threadId,
                roomId: "test-room",
                name: "Test Thread",
                deviceId: deviceId,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        func getUnreadCount(deviceId: String) async throws -> Int {
            0
        }
    }

    private func makeJob(index: Int, roomId: String, runner: String = "claude") -> Job {
        Job(
            id: "job-\(index)",
            runner: runner,
            inputText: "Input #\(index)",
            deviceId: "device",
            roomId: roomId,
            status: "success",
            stdout: "Output #\(index)",
            stderr: nil,
            exitCode: 0,
            createdAt: Date(),
            startedAt: Date(),
            finishedAt: Date()
        )
    }

    // MARK: - Phase 2.6.1: UI Tests (Unit Level)

    func testRoomModelCodable() throws {
        let room = Room(
            id: "test-room-id",
            name: "Test Room",
            workspacePath: "/Users/test/workspace",
            icon: "folder",
            deviceId: "test-device",
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(room)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Room.self, from: data)

        XCTAssertEqual(decoded.id, room.id)
        XCTAssertEqual(decoded.name, room.name)
        XCTAssertEqual(decoded.workspacePath, room.workspacePath)
        XCTAssertEqual(decoded.icon, room.icon)
        XCTAssertEqual(decoded.deviceId, room.deviceId)
    }

    func testJobModelWithRoomId() throws {
        let job = makeJob(index: 1, roomId: "room-123")
        XCTAssertEqual(job.roomId, "room-123")
        XCTAssertFalse(job.isRunning)
    }

    func testMessageWithRoomId() {
        let message = Message(
            id: "msg-123",
            jobId: "job-123",
            roomId: "room-123",
            type: .user,
            content: "Test message",
            status: .completed,
            createdAt: Date()
        )

        XCTAssertEqual(message.roomId, "room-123")
        XCTAssertEqual(message.type, .user)
        XCTAssertEqual(message.status, .completed)
    }

    // MARK: - Phase 2.6.2: Pagination Tests

    @MainActor
    func testChatViewModelPaginationState() async {
        let mock = MockAPIClient()
        let viewModel = ChatViewModel(
            runner: "claude",
            roomId: "room-1",
            apiClient: mock,
            messageStore: MessageStore(),
            deviceIdProvider: { "device" },
            autoLoadMessages: false,
            enableStreaming: false,
            validateAPIKey: false
        )

        XCTAssertTrue(viewModel.canLoadMoreHistory)
        XCTAssertFalse(viewModel.isLoadingMoreHistory)
        XCTAssertFalse(viewModel.isHistoryLoading)
        XCTAssertEqual(viewModel.messages.count, 0)
    }

    @MainActor
    func testMessageConversionProducesUserAndAssistantMessages() async {
        let mock = MockAPIClient()
        let viewModel = ChatViewModel(
            runner: "claude",
            roomId: "room-1",
            apiClient: mock,
            messageStore: MessageStore(),
            deviceIdProvider: { "device" },
            autoLoadMessages: false,
            enableStreaming: false,
            validateAPIKey: false
        )

        let jobs = [makeJob(index: 1, roomId: "room-1")]
        let messages = viewModel.convertJobsToMessages(jobs)

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].type, .user)
        XCTAssertEqual(messages[1].type, .assistant)
    }

    @MainActor
    func testPaginationOffsetCalculation() async {
        let mock = MockAPIClient()
        let roomId = "room-1"
        // historyPageSize = 10 なので、10件未満だとcanLoadMoreHistory = false
        let firstPage = [makeJob(index: 1, roomId: roomId), makeJob(index: 2, roomId: roomId)]
        mock.fetchMessagesResponses = [0: firstPage]

        let viewModel = ChatViewModel(
            runner: "claude",
            roomId: roomId,
            apiClient: mock,
            messageStore: MessageStore(),
            deviceIdProvider: { "device" },
            autoLoadMessages: false,
            enableStreaming: false,
            validateAPIKey: false
        )

        await viewModel.loadLatestMessages()
        // 2 Jobs × 2 (user + assistant) = 4 messages
        XCTAssertEqual(viewModel.messages.count, 4)
        XCTAssertEqual(viewModel.historyOffsetSnapshot, 2)
        // historyPageSize(10)未満のため、もうロードするものがない
        XCTAssertFalse(viewModel.canLoadMoreHistory)
    }

    // MARK: - Phase 2.6.3: Consistency Tests

    @MainActor
    func testRoomsViewModelInitialState() async {
        let mock = MockAPIClient()
        let initialRooms = [
            Room(
                id: "room-1",
                name: "RemotePrompt",
                workspacePath: "/Users/test/RemotePrompt",
                icon: "📁",
                deviceId: "device",
                sortOrder: 0,
                unreadCount: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        let viewModel = RoomsViewModel(
            apiClient: mock,
            deviceIdProvider: { "device" },
            skipAPIKeyCheck: true,
            initialRooms: initialRooms
        )

        XCTAssertEqual(viewModel.rooms.count, 1)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.rooms.first?.name, "RemotePrompt")
    }

    @MainActor
    func testMessageStoreContextSwitching() async {
        let store = MessageStore()
        store.setActiveContext(roomId: "room-1", runner: "claude", threadId: "thread-1")

        let message1 = Message(
            roomId: "room-1",
            type: .user,
            content: "Test 1",
            status: .completed
        )
        store.addMessage(message1)
        XCTAssertEqual(store.messages.count, 1)

        store.setActiveContext(roomId: "room-2", runner: "codex", threadId: "thread-2")
        XCTAssertEqual(store.messages.count, 0)

        store.setActiveContext(roomId: "room-1", runner: "claude", threadId: "thread-1")
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages.first?.content, "Test 1")
    }

    @MainActor
    func testMessageStoreReplaceAll() async {
        let store = MessageStore()
        store.setActiveContext(roomId: "room-1", runner: "claude", threadId: "thread-1")

        let oldMessage = Message(
            roomId: "room-1",
            type: .user,
            content: "Old message",
            status: .completed
        )
        store.addMessage(oldMessage)
        XCTAssertEqual(store.messages.count, 1)

        let newMessages = [
            Message(roomId: "room-1", type: .user, content: "New message 1", status: .completed),
            Message(roomId: "room-1", type: .user, content: "New message 2", status: .completed)
        ]
        store.replaceAll(newMessages)

        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages[0].content, "New message 1")
        XCTAssertEqual(store.messages[1].content, "New message 2")
    }

    @MainActor
    func testMessageStoreClear() async {
        let store = MessageStore()
        store.setActiveContext(roomId: "room-1", runner: "claude", threadId: "thread-1")

        let message = Message(
            roomId: "room-1",
            type: .user,
            content: "Test",
            status: .completed
        )
        store.addMessage(message)
        XCTAssertEqual(store.messages.count, 1)

        store.clear()
        XCTAssertEqual(store.messages.count, 0)
    }

    func testDeviceIdPersistence() {
        let deviceId1 = APIClient.getDeviceId()
        let deviceId2 = APIClient.getDeviceId()

        XCTAssertEqual(deviceId1, deviceId2)
        XCTAssertFalse(deviceId1.isEmpty)
    }
}
