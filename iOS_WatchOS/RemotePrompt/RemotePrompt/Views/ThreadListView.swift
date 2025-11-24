import SwiftUI

/// スレッド一覧を表示するビュー
struct ThreadListView: View {
    @ObservedObject var viewModel: ThreadListViewModel
    @State private var showCreateThread = false
    @State private var threadToEdit: Thread?

    let room: Room
    let onThreadSelected: (Thread) -> Void
    let runner: String

    init(
        room: Room,
        runner: String,
        onThreadSelected: @escaping (Thread) -> Void,
        apiClient: APIClientProtocol = APIClient.shared,
        viewModel: ThreadListViewModel? = nil
    ) {
        self.room = room
        self.runner = runner
        self.onThreadSelected = onThreadSelected
        if let vm = viewModel {
            _viewModel = ObservedObject(wrappedValue: vm)
        } else {
            _viewModel = ObservedObject(
                wrappedValue: ThreadListViewModel(
                    roomId: room.id,
                    runner: runner,
                    apiClient: apiClient
                )
            )
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.threads.isEmpty {
                ProgressView("読み込み中...")
            } else if viewModel.threads.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("スレッドがありません")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button {
                        showCreateThread = true
                    } label: {
                        Label("新しいスレッド", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(viewModel.threads) { thread in
                    Button {
                        onThreadSelected(thread)
                    } label: {
                        ThreadRowView(thread: thread)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color(.systemGroupedBackground))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            threadToEdit = thread
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteThread(threadId: thread.id)
                            }
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .refreshable {
                    await viewModel.fetchThreads()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateThread = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateThread) {
            CreateThreadView(runner: runner) { threadName in
                Task {
                    await viewModel.createThread(name: threadName)
                }
            }
        }
        .sheet(item: $threadToEdit) { thread in
            EditThreadNameView(thread: thread) { newName in
                Task {
                    await viewModel.updateThreadName(threadId: thread.id, newName: newName)
                }
            }
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }
}

/// スレッド行を表示するビュー
private struct ThreadRowView: View {
    let thread: Thread

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.name)
                    .font(.headline)

                if let updatedAt = thread.updatedAt {
                    Text("最終会話: \(updatedAt, style: .date) \(updatedAt, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("会話履歴なし")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// List内のButton用のカスタムスタイル（タップ時のハイライト効果を無効化）
private struct PlainListButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        ThreadListView(
            room: Room(
                id: "test-room",
                name: "Test Room",
                workspacePath: "/path",
                icon: "📁",
                deviceId: "device1",
                createdAt: Date(),
                updatedAt: Date()
            ),
            runner: "claude",
            onThreadSelected: { _ in }
        )
    }
}
