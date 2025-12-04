import SwiftUI

struct MarkdownEditorView: View {
    let room: Room
    let fileItem: FileItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MarkdownEditorViewModel
    @State private var showSaveAlert = false
    @State private var saveSucceeded = false

    init(room: Room, fileItem: FileItem) {
        self.room = room
        self.fileItem = fileItem
        _viewModel = StateObject(wrappedValue: MarkdownEditorViewModel(roomId: room.id))
    }

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView(L10n.Common.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SyntaxHighlightedTextEditor(text: $viewModel.fileContent)
            }
        }
        .navigationTitle(fileItem.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(L10n.Common.close) { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await save() } }) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Text(L10n.Editor.save)
                    }
                }
                .disabled(!viewModel.isDirty || viewModel.isSaving)
            }
        }
        .alert(isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil || showSaveAlert },
            set: { _ in
                if showSaveAlert { showSaveAlert = false }
                viewModel.errorMessage = nil
            }
        )) {
            if let error = viewModel.errorMessage {
                return Alert(title: Text(L10n.Editor.saveError), message: Text(error), dismissButton: .default(Text(L10n.Common.ok)))
            } else {
                return Alert(title: Text(saveSucceeded ? L10n.Editor.saveSuccess : ""), dismissButton: .default(Text(L10n.Common.ok)))
            }
        }
        .task {
            await viewModel.loadFile(path: fileItem.path)
        }
    }

    private func save() async {
        let success = await viewModel.saveFile(path: fileItem.path)
        await MainActor.run {
            saveSucceeded = success
            showSaveAlert = success
        }
    }
}

#Preview {
    NavigationStack {
        MarkdownEditorView(
            room: Room(
                id: UUID().uuidString,
                name: "RemotePrompt",
                workspacePath: "/Users/macstudio/Projects/RemotePrompt",
                icon: "📁",
                deviceId: "device",
                createdAt: Date(),
                updatedAt: Date()
            ),
            fileItem: FileItem(
                id: "Docs/README.md",
                name: "README.md",
                type: .markdownFile,
                path: "Docs/README.md",
                size: 1234,
                modifiedAt: Date()
            )
        )
    }
}
