import Combine
import Foundation

@MainActor
final class JobDetailViewModel: ObservableObject {
    @Published var job: Job?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSSEConnected = false

    private let apiClient = APIClient.shared
    private let sseManager = SSEManager()
    private let jobId: String
    private var cancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?
    private var isStreaming = false

    init(jobId: String) {
        self.jobId = jobId
    }

    func loadJob() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let fetchedJob = try await apiClient.fetchJob(id: jobId)
            job = fetchedJob
            if fetchedJob.isRunning {
                startSSEStreaming()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await loadJob()
    }

    func stopSSEStreaming() {
        sseManager.disconnect()
        cancellables.removeAll()
        isSSEConnected = false
        isStreaming = false
    }

    func startPollingFallback() {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.loadJob()
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func startSSEStreaming() {
        if isStreaming {
            return
        }
        isStreaming = true
        stopPolling()
        sseManager.connect(jobId: jobId)

        sseManager.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                guard let self else { return }
                self.isSSEConnected = connected
                if !connected && self.job?.isRunning == true && self.isStreaming {
                    self.startPollingFallback()
                }
            }
            .store(in: &cancellables)

        sseManager.$jobStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.job?.status = status
                if status == "success" || status == "failed" {
                    self.stopSSEStreaming()
                    Task {
                        await self.loadJob()
                    }
                }
            }
            .store(in: &cancellables)

        sseManager.$errorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let self else { return }
                self.errorMessage = message
                self.isStreaming = false
                if self.job?.isRunning == true {
                    self.startPollingFallback()
                }
            }
            .store(in: &cancellables)
    }
}
