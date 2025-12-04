import SwiftUI

/// Room詳細画面（Thread一覧 → Chat表示）
/// iPad: NavigationSplitViewで左側にスレッド一覧、右側にチャット表示
/// iPhone: 従来通りの画面遷移
struct RoomDetailView: View {
    let room: Room
    private let apiClient: APIClientProtocol
    private let enableStreaming: Bool
    @StateObject private var threadListViewModel: ThreadListViewModel
    @State private var selectedThread: Thread?
    @State private var selectedRunner: AIProvider = .claude
    @State private var showFileBrowser = false
    @State private var showRoomSettings = false
    @State private var chatViewModels: [String: ChatViewModel] = [:]  // v4.4: runner別に独立したViewModel

    /// iPad判定用（regular = iPad, compact = iPhone）
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

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
            if horizontalSizeClass == .regular {
                // iPad: SplitView（左にスレッド一覧、右にチャット）
                iPadSplitView
            } else {
                // iPhone: 従来通りの画面遷移
                iPhoneNavigationView
            }
        }
        .fullScreenCover(isPresented: $showFileBrowser) {
            // iPadでは全画面でSplitView表示
            FileBrowserView(room: room, path: "", isRoot: true)
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

    // MARK: - iPad SplitView

    private var iPadSplitView: some View {
        NavigationSplitView {
            // サイドバー: スレッド一覧
            ThreadListView(
                room: room,
                runner: "claude",
                onThreadSelected: { thread in
                    selectedThread = thread
                    // v4.4: スレッド切り替え時は全runner用ViewModelをクリア
                    chatViewModels.removeAll()
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
            .toolbar {
                if horizontalSizeClass == .regular {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Label("Rooms", systemImage: "chevron.left")
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
        } detail: {
            // 詳細: チャット画面
            if let thread = selectedThread {
                VStack(spacing: 0) {
                    runnerPicker

                    if let viewModel = chatViewModels[selectedRunner.rawValue] {
                        ChatView(viewModel: viewModel)
                            .background(Color(.systemBackground))
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                    }
                }
                .navigationTitle(thread.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showRoomSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .onAppear {
                    ensureViewModel(for: thread, runner: selectedRunner.rawValue)
                    Task { @MainActor in
                        await threadListViewModel.markRunnerAsRead(
                            threadId: thread.id,
                            runner: selectedRunner.rawValue
                        )
                        updateSelectedThreadUnread(removeRunner: selectedRunner.rawValue)
                    }
                }
                .onChange(of: selectedRunner) { _, newRunner in
                    if let thread = selectedThread {
                        ensureViewModel(for: thread, runner: newRunner.rawValue)
                    }
                    Task { @MainActor in
                        if let thread = selectedThread {
                            await threadListViewModel.markRunnerAsRead(
                                threadId: thread.id,
                                runner: newRunner.rawValue
                            )
                            updateSelectedThreadUnread(removeRunner: newRunner.rawValue)
                        }
                    }
                }
            } else {
                // スレッド未選択時のプレースホルダー
                ContentUnavailableView(
                    "スレッドを選択",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("左のリストからスレッドを選択してください")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - iPhone Navigation

    private var iPhoneNavigationView: some View {
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
                    // v4.4: スレッド切り替え時は全runner用ViewModelをクリア
                    chatViewModels.removeAll()
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

            // v4.4: runner別に独立したChatViewModelを使用（入力欄の分離）
            // 既存のViewModelがある場合はそれを使用、なければプレースホルダー表示
            if let viewModel = chatViewModels[selectedRunner.rawValue] {
                ChatView(viewModel: viewModel)
                    .background(Color(.systemBackground))
            } else {
                // ViewModelがまだ作成されていない場合のプレースホルダー
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
        .navigationTitle(thread.name)
        .transition(.move(edge: .trailing))
        // v4.3.2: チャット画面表示時に既読にする & ViewModelを遅延生成
        .onAppear {
            // View描画後にViewModelを生成（state更新を遅延）
            ensureViewModel(for: thread, runner: selectedRunner.rawValue)

            Task { @MainActor in
                await threadListViewModel.markRunnerAsRead(
                    threadId: thread.id,
                    runner: selectedRunner.rawValue
                )
                updateSelectedThreadUnread(removeRunner: selectedRunner.rawValue)
            }
        }
        .onChange(of: selectedRunner) { _, newRunner in
            // v4.4: runner切り替え時は別のViewModelを遅延生成
            if let thread = selectedThread {
                ensureViewModel(for: thread, runner: newRunner.rawValue)
            }

            Task { @MainActor in
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

    /// v4.4: runner別のChatViewModelを遅延生成（View描画後に呼び出す）
    /// - Note: View描画中にstateを変更するとSwiftUIの警告が出るため、onAppear/onChangeから呼び出す
    private func ensureViewModel(for thread: Thread, runner: String) {
        guard chatViewModels[runner] == nil else { return }
        let newViewModel = ChatViewModel(
            runner: runner,
            roomId: room.id,
            threadId: thread.id,
            apiClient: apiClient,
            enableStreaming: enableStreaming,
            validateAPIKey: !AppEnvironment.isUITesting
        )
        chatViewModels[runner] = newViewModel
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
