import SwiftUI

struct FileBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FileBrowserViewModel
    private let room: Room

    init(room: Room) {
        self.room = room
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(room: room))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.fileItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("このディレクトリは空です")
                            .foregroundColor(.secondary)
                        if viewModel.showRetry {
                            retryButton
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.fileItems) { item in
                        Button {
                            Task {
                                if item.type == .directory {
                                    await viewModel.navigateToDirectory(item)
                                }
                            }
                        } label: {
                            if item.type == .directory {
                                FileRow(item: item)
                            } else {
                                NavigationLink {
                                    MarkdownEditorView(room: room, fileItem: item)
                                } label: {
                                    FileRow(item: item)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.pathComponents.isEmpty {
                        Button(action: { Task { await viewModel.navigateBack() } }) {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
            .alert(isPresented: Binding<Bool>(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Alert(title: Text("エラー"), message: Text(viewModel.errorMessage ?? "不明なエラー"), dismissButton: .default(Text("OK")))
            }
            .task {
                await viewModel.loadFiles()
            }
        }
    }

    private var retryButton: some View {
        Button {
            Task { await viewModel.loadFiles(path: viewModel.currentPath) }
        } label: {
            Label("リトライ", systemImage: "arrow.clockwise")
        }
    }
}

#Preview {
    NavigationStack {
        FileBrowserView(room: Room(
            id: UUID().uuidString,
            name: "RemotePrompt",
            workspacePath: "/Users/macstudio/Projects/RemotePrompt",
            icon: "📁",
            deviceId: "device",
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
}
