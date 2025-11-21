import SwiftUI

/// Room詳細画面（Thread一覧 → Chat表示）
struct RoomDetailView: View {
    private enum RunnerTab: String, CaseIterable, Identifiable {
        case claude
        case codex

        var id: String { rawValue }
        var title: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            }
        }
        var systemImage: String {
            switch self {
            case .claude: return "bubble.left"
            case .codex: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    let room: Room
    private let apiClient: APIClientProtocol
    private let enableStreaming: Bool
    @StateObject private var threadListViewModel: ThreadListViewModel
    @State private var selectedThread: Thread?
    @State private var selectedRunner: RunnerTab = .claude
    @State private var showFileBrowser = false
    @State private var showRoomSettings = false

    init(
        room: Room,
        apiClient: APIClientProtocol = APIClient.shared,
        enableStreaming: Bool = !AppEnvironment.isUITesting
    ) {
        self.room = room
        self.apiClient = apiClient
        self.enableStreaming = enableStreaming
        _threadListViewModel = StateObject(
            wrappedValue: ThreadListViewModel(
                roomId: room.id,
                runner: nil,  // 全runner表示
                apiClient: apiClient
            )
        )
    }

    var body: some View {
        ZStack {
            ThreadListView(
                room: room,
                runner: "claude", // ラベル用。全runnerを表示。
                onThreadSelected: { thread in
                    withAnimation(.easeInOut) {
                        selectedThread = thread
                        selectedRunner = RunnerTab(rawValue: thread.runner) ?? .claude
                    }
                },
                viewModel: threadListViewModel
            )
            .opacity(selectedThread == nil ? 1 : 0)

            if let thread = selectedThread {
                VStack(spacing: 0) {
                    Picker("Runner", selection: $selectedRunner) {
                        ForEach(RunnerTab.allCases) { tab in
                            Label(tab.title, systemImage: tab.systemImage).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .onChange(of: selectedRunner) { _, newValue in
                        withAnimation(.easeInOut) {
                            if let target = threadListViewModel.threads.first(where: { $0.runner == newValue.rawValue }) {
                                selectedThread = target
                            }
                        }
                    }

                    ThreadChatView(
                        room: room,
                        thread: thread,
                        apiClient: apiClient,
                        enableStreaming: enableStreaming,
                        onBack: {
                            withAnimation(.easeInOut) {
                                selectedThread = nil
                            }
                        },
                        onSettings: {
                            showRoomSettings = true
                        }
                    )
                }
                .transition(.move(edge: .trailing))
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selectedThread != nil)
        .toolbar {
            if selectedThread != nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut) {
                            selectedThread = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("スレッド一覧")
                        }
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFileBrowser = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showFileBrowser) {
            FileBrowserView(room: room)
        }
        .sheet(isPresented: $showRoomSettings) {
            RoomSettingsView(room: room, runner: selectedThread?.runner ?? "claude")
        }
    }
}

/// Thread専用のChat画面
private struct ThreadChatView: View {
    let room: Room
    let thread: Thread
    let apiClient: APIClientProtocol
    let enableStreaming: Bool
    let onBack: () -> Void
    let onSettings: () -> Void

    @StateObject private var viewModel: ChatViewModel

    init(
        room: Room,
        thread: Thread,
        apiClient: APIClientProtocol,
        enableStreaming: Bool,
        onBack: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.room = room
        self.thread = thread
        self.apiClient = apiClient
        self.enableStreaming = enableStreaming
        self.onBack = onBack
        self.onSettings = onSettings

        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                runner: thread.runner,
                roomId: room.id,
                threadId: thread.id,
                apiClient: apiClient,
                enableStreaming: enableStreaming,
                validateAPIKey: !AppEnvironment.isUITesting
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thread名表示バー
            HStack {
                Text(thread.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Label {
                    Text(thread.runner == "claude" ? "Claude" : "Codex")
                        .font(.caption)
                } icon: {
                    Image(systemName: thread.runner == "claude" ? "bubble.left" : "chevron.left.forwardslash.chevron.right")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            // Chat画面
            ChatView(viewModel: viewModel, onSettingsTapped: onSettings)
                .background(Color(.systemBackground))
        }
    }
}

#Preview {
    NavigationStack {
        RoomDetailView(
            room: Room(
                id: UUID().uuidString,
                name: "RemotePrompt",
                workspacePath: "/Users/macstudio/Projects/RemotePrompt",
                icon: "📁",
                deviceId: "device",
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
}
