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
        Group {
            if let thread = selectedThread {
                chatViewContainer(for: thread)
            } else {
                threadListLayer
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selectedThread != nil)
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showFileBrowser) {
            FileBrowserView(room: room)
        }
        .sheet(isPresented: $showRoomSettings) {
            if selectedThread != nil {
                RoomSettingsView(room: room, runner: selectedRunner.rawValue)
            }
        }
    }

    // MARK: - View Components

    private var threadListLayer: some View {
        ThreadListView(
            room: room,
            runner: "claude",
            onThreadSelected: { thread in
                withAnimation(.easeInOut) {
                    selectedThread = thread
                    selectedRunner = RunnerTab(rawValue: thread.runner) ?? .claude
                }
            },
            viewModel: threadListViewModel
        )
        .navigationTitle(room.name)
    }

    private func chatViewContainer(for thread: Thread) -> some View {
        VStack(spacing: 0) {
            runnerPicker

            ChatView(
                viewModel: ChatViewModel(
                    runner: selectedRunner.rawValue,
                    roomId: room.id,
                    threadId: thread.id,
                    apiClient: apiClient,
                    enableStreaming: enableStreaming,
                    validateAPIKey: !AppEnvironment.isUITesting
                )
            )
            .background(Color(.systemBackground))
        }
        .navigationTitle(thread.name)
        .transition(.move(edge: .trailing))
    }

    private var runnerPicker: some View {
        Picker("Runner", selection: $selectedRunner) {
            ForEach(RunnerTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectedThread != nil {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation(.easeInOut) {
                        selectedThread = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
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

        if selectedThread != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRoomSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
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
