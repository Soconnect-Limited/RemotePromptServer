import SwiftUI

struct RoomDetailView: View {
    private enum RunnerTab: String, CaseIterable, Identifiable {
        case claude
        case codex

        var id: String { rawValue }
        var title: String {
            rawValue.capitalized
        }
        var systemImage: String {
            switch self {
            case .claude: return "bubble.left"
            case .codex: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    let room: Room
    @StateObject private var claudeViewModel: ChatViewModel
    @StateObject private var codexViewModel: ChatViewModel
    @State private var selectedTab: RunnerTab = .claude

    init(room: Room) {
        self.room = room
        _claudeViewModel = StateObject(wrappedValue: ChatViewModel(runner: "claude", roomId: room.id))
        _codexViewModel = StateObject(wrappedValue: ChatViewModel(runner: "codex", roomId: room.id))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            roomTab(viewModel: claudeViewModel)
                .tag(RunnerTab.claude)
                .tabItem { Label("Claude", systemImage: RunnerTab.claude.systemImage) }

            roomTab(viewModel: codexViewModel)
                .tag(RunnerTab.codex)
                .tabItem { Label("Codex", systemImage: RunnerTab.codex.systemImage) }
        }
        .navigationTitle(room.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Claude履歴をクリア", role: .destructive) {
                        claudeViewModel.clearChat()
                    }
                    Button("Codex履歴をクリア", role: .destructive) {
                        codexViewModel.clearChat()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func roomTab(viewModel: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            roomHeader
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))

            ChatView(viewModel: viewModel)
                .background(Color(.systemBackground))
        }
    }

    private var roomHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(room.icon.isEmpty ? "📁" : room.icon)
                    .font(.title2)
                Text(room.name)
                    .font(.headline)
            }
            Text(room.workspacePath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
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
