import SwiftUI

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
    @StateObject private var claudeViewModel: ChatViewModel
    @StateObject private var codexViewModel: ChatViewModel
    @State private var selectedTab: RunnerTab = .claude
    @State private var showFileBrowser = false
    @State private var showRoomSettings = false

    init(room: Room, apiClient: APIClientProtocol = APIClient.shared, enableStreaming: Bool = !AppEnvironment.isUITesting) {
        self.room = room
        self.apiClient = apiClient
        _claudeViewModel = StateObject(
            wrappedValue: ChatViewModel(
                runner: "claude",
                roomId: room.id,
                apiClient: apiClient,
                enableStreaming: enableStreaming,
                validateAPIKey: !AppEnvironment.isUITesting
            )
        )
        _codexViewModel = StateObject(
            wrappedValue: ChatViewModel(
                runner: "codex",
                roomId: room.id,
                apiClient: apiClient,
                enableStreaming: enableStreaming,
                validateAPIKey: !AppEnvironment.isUITesting
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab picker at the top
            Picker("Runner", selection: $selectedTab) {
                ForEach(RunnerTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            // Content based on selection
            Group {
                switch selectedTab {
                case .claude:
                    roomTab(viewModel: claudeViewModel)
                case .codex:
                    roomTab(viewModel: codexViewModel)
                }
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            RoomSettingsView(room: room)
        }
    }

    private func roomTab(viewModel: ChatViewModel) -> some View {
        ChatView(viewModel: viewModel) {
            showRoomSettings = true
        }
            .background(Color(.systemBackground))
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
