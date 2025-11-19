import Foundation

/// UIテスト/プレビュー用のインメモリAPIクライアント。
actor PreviewAPIClient: APIClientProtocol {
    private var roomsStorage: [Room]
    private var jobsStorage: [String: Job]
    private var roomRunnerIndex: [String: [Job]]

    init(date: Date = Date()) {
        let defaultRoom = Room(
            id: UUID().uuidString,
            name: "RemotePrompt",
            workspacePath: "/Users/preview/RemotePrompt",
            icon: "📁",
            deviceId: "preview-device",
            createdAt: date,
            updatedAt: date
        )
        roomsStorage = [defaultRoom]

        let sampleJob = Job(
            id: UUID().uuidString,
            runner: "claude",
            inputText: "Summarize project status",
            deviceId: defaultRoom.deviceId,
            roomId: defaultRoom.id,
            status: "success",
            stdout: "Phase 2 UI is complete.",
            stderr: nil,
            exitCode: 0,
            createdAt: date,
            startedAt: date,
            finishedAt: date
        )
        jobsStorage = [sampleJob.id: sampleJob]
        roomRunnerIndex = ["\(sampleJob.roomId)#\(sampleJob.runner)": [sampleJob]]
    }

    func fetchJob(id: String) async throws -> Job {
        guard let job = jobsStorage[id] else {
            throw APIError.invalidURL
        }
        return job
    }

    func createJob(runner: String, prompt: String, deviceId: String, roomId: String) async throws -> CreateJobResponse {
        let job = Job(
            id: UUID().uuidString,
            runner: runner,
            inputText: prompt,
            deviceId: deviceId,
            roomId: roomId,
            status: "success",
            stdout: "Preview response for \(prompt)",
            stderr: nil,
            exitCode: 0,
            createdAt: Date(),
            startedAt: Date(),
            finishedAt: Date()
        )
        jobsStorage[job.id] = job
        roomRunnerIndex[key(for: roomId, runner: runner), default: []].append(job)
        return CreateJobResponse(id: job.id, runner: runner, status: job.status)
    }

    func fetchRooms(deviceId: String) async throws -> [Room] {
        roomsStorage
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
        roomsStorage.append(room)
        return room
    }

    func updateRoom(roomId: String, name: String, workspacePath: String, deviceId: String, icon: String) async throws -> Room {
        guard let index = roomsStorage.firstIndex(where: { $0.id == roomId }) else {
            throw APIError.invalidURL
        }
        var room = roomsStorage[index]
        room.name = name
        room.workspacePath = workspacePath
        room.icon = icon
        roomsStorage[index] = room
        return room
    }

    func deleteRoom(roomId: String, deviceId: String) async throws {
        roomsStorage.removeAll { $0.id == roomId }
        roomRunnerIndex = roomRunnerIndex.filter { !$0.key.hasPrefix(roomId) }
    }

    func fetchMessages(
        deviceId: String,
        roomId: String,
        runner: String,
        limit: Int,
        offset: Int
    ) async throws -> [Job] {
        let jobs = roomRunnerIndex[key(for: roomId, runner: runner)] ?? []
        guard offset < jobs.count else { return [] }
        return Array(jobs.dropFirst(offset).prefix(limit))
    }

    private func key(for roomId: String, runner: String) -> String {
        "\(roomId)#\(runner)"
    }
}
