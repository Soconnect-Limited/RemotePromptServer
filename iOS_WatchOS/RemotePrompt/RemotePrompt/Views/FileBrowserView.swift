import SwiftUI
import Foundation

struct FileBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FileBrowserViewModel
    private let room: Room
    private let initialPath: String
    private let isRoot: Bool

    init(room: Room, path: String = "", isRoot: Bool = true) {
        self.room = room
        self.initialPath = path
        self.isRoot = isRoot
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(room: room))

#if DEBUG
        if !isRoot {
            // 前提: 親階層のNavigationStackにぶら下がっていること。
            // NavigationStack外で使われた場合は遷移できないため開発時に検知。
            assert(Foundation.Thread.isMainThread, "FileBrowserView must be created on main thread")
        }
#endif
    }

    private var displayTitle: String {
        if initialPath.isEmpty {
            return "Workspace"
        }
        let components = initialPath.split(separator: "/")
        if let lastComponent = components.last {
            return String(lastComponent)
        }
        return "Workspace"
    }

    var body: some View {
        contentView
            .navigationDestination(for: FileItem.self) { item in
                if item.type == .directory {
                    FileBrowserView(room: room, path: item.path, isRoot: false)
                }
            }
    }

    private var contentView: some View {
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
                        if item.type == .directory {
                            NavigationLink(value: item) {
                                FileRow(item: item)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = item.path
                                } label: {
                                    Label("パスをコピー", systemImage: "doc.on.doc")
                                }
                            }
                        } else {
                            NavigationLink {
                                MarkdownEditorView(room: room, fileItem: item)
                            } label: {
                                FileRow(item: item)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = item.path
                                } label: {
                                    Label("パスをコピー", systemImage: "doc.on.doc")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isRoot {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
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
                await viewModel.loadFiles(path: initialPath)
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
