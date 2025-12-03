import SwiftUI

/// Room詳細画面（Thread一覧 → Chat表示）
struct RoomDetailView: View {
    let room: Room
    private let apiClient: APIClientProtocol
    private let enableStreaming: Bool
    @StateObject private var threadListViewModel: ThreadListViewModel
    @State private var selectedThread: Thread?
    @State private var selectedRunner: AIProvider = .claude
    @State private var showFileBrowser = false
    @State private var showRoomSettings = false
    @State private var chatViewModel: ChatViewModel?  // v4.1: Persistent ViewModel for runner switching

    /// 有効なAIプロバイダー（設定順序でソート）
    private var enabledProviders: [AIProviderConfiguration] {
        ServerConfigurationStore.shared.currentConfiguration?.enabledAIProviders
            ?? AIProviderConfiguration.defaultConfigurations().filter { $0.isEnabled }
    }

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
        .onAppear {
            // 有効なプロバイダーの最初のものを選択
            if let firstEnabled = enabledProviders.first {
                selectedRunner = firstEnabled.provider
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
                // v4.3.1: スレッド選択時に現在のrunnerを既読にする
                Task { @MainActor in
                    await threadListViewModel.markRunnerAsRead(
                        threadId: thread.id,
                        runner: selectedRunner.rawValue
                    )
                    updateSelectedThreadUnread(removeRunner: selectedRunner.rawValue)
                }
            },
            viewModel: threadListViewModel
        )
        .navigationTitle(room.name)
    }

    // MARK: - Private Helpers

    /// v4.3.1: 選択中スレッドのunreadRunnersからrunnerを削除
    private func updateSelectedThreadUnread(removeRunner runner: String) {
        guard var thread = selectedThread else { return }
        thread.unreadRunners.removeAll { $0 == runner }
        thread.hasUnread = !thread.unreadRunners.isEmpty
        selectedThread = thread
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
        // v4.3.2: チャット画面表示時に既読にする
        .onAppear {
            Task { @MainActor in
                await threadListViewModel.markRunnerAsRead(
                    threadId: thread.id,
                    runner: selectedRunner.rawValue
                )
                updateSelectedThreadUnread(removeRunner: selectedRunner.rawValue)
            }
        }
        .onChange(of: selectedRunner) { _, newRunner in
            // v4.1: Update runner dynamically without recreating ViewModel
            Task { @MainActor in
                await chatViewModel?.updateRunner(newRunner.rawValue)
                // v4.3.1: 選択されたrunnerを既読にする
                if let thread = selectedThread {
                    await threadListViewModel.markRunnerAsRead(
                        threadId: thread.id,
                        runner: newRunner.rawValue
                    )
                    // ローカルの状態も更新
                    updateSelectedThreadUnread(removeRunner: newRunner.rawValue)
                }
            }
        }
    }

    private var runnerPicker: some View {
        HStack(spacing: 0) {
            ForEach(enabledProviders) { config in
                Button {
                    selectedRunner = config.provider
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: config.provider.systemImage)
                        Text(config.provider.displayName)
                        // v4.3.1: runner別未読バッジ
                        if let thread = selectedThread,
                           thread.unreadRunners.contains(config.provider.rawValue) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(selectedRunner == config.provider ? .semibold : .regular)
                    .foregroundStyle(selectedRunner == config.provider ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedRunner == config.provider
                            ? Color(.systemGray5)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
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
