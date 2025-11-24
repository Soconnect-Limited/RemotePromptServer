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
    @State private var chatViewModel: ChatViewModel?  // v4.1: Persistent ViewModel for runner switching

    init(
        room: Room,
        apiClient: APIClientProtocol = APIClient.shared,
        enableStreaming: Bool = !AppEnvironment.isUITesting
    ) {
        self.room = room
        self.apiClient = apiClient
        self.enableStreaming = enableStreaming
        let viewModel = ThreadListViewModel(
            roomId: room.id,
            runner: nil,  // 全runner表示
            apiClient: apiClient
        )
        _threadListViewModel = StateObject(wrappedValue: viewModel)
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
            NavigationStack {
                FileBrowserView(room: room, path: "", isRoot: false)
            }
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
                    // v4.2: Thread.runner削除により、selectedRunnerは変更しない（ユーザー選択を維持）
                    // v4.1: Clear chatViewModel when switching threads
                    chatViewModel = nil
                }
            },
            viewModel: threadListViewModel
        )
        .navigationTitle(room.name)
    }

    private func chatViewContainer(for thread: Thread) -> some View {
        VStack(spacing: 0) {
            runnerPicker

            // v4.1: Use persistent ChatViewModel with dynamic runner switching
            Group {
                if let viewModel = chatViewModel {
                    ChatView(viewModel: viewModel)
                        .background(Color(.systemBackground))
                } else {
                    Color.clear
                        .onAppear {
                            chatViewModel = ChatViewModel(
                                runner: selectedRunner.rawValue,
                                roomId: room.id,
                                threadId: thread.id,
                                apiClient: apiClient,
                                enableStreaming: enableStreaming,
                                validateAPIKey: !AppEnvironment.isUITesting
                            )
                        }
                }
            }
        }
        .navigationTitle(thread.name)
        .transition(.move(edge: .trailing))
        .onChange(of: selectedRunner) { _, newRunner in
            // v4.1: Update runner dynamically without recreating ViewModel
            Task { @MainActor in
                await chatViewModel?.updateRunner(newRunner.rawValue)
            }
        }
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
