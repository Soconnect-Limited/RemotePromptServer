import SwiftUI
import PDFKit

struct PDFViewerView: View {
    let room: Room
    let fileItem: FileItem
    /// SplitViewのdetailとして表示されている場合はtrue（閉じるボタンを非表示にする）
    var isEmbeddedInSplitView: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PDFViewerViewModel

    init(room: Room, fileItem: FileItem, isEmbeddedInSplitView: Bool = false) {
        self.room = room
        self.fileItem = fileItem
        self.isEmbeddedInSplitView = isEmbeddedInSplitView
        _viewModel = StateObject(wrappedValue: PDFViewerViewModel(roomId: room.id))
    }

    var body: some View {
        Group {
            if isEmbeddedInSplitView {
                // SplitView埋め込み時: ナビゲーションバーなし（親が管理）
                pdfContentView
            } else {
                // 通常表示: ナビゲーションバーあり
                pdfContentView
                    .navigationTitle(fileItem.name)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(L10n.Common.close) { dismiss() }
                        }
                    }
            }
        }
        .alert(isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Alert(
                title: Text(L10n.Common.error),
                message: Text(viewModel.errorMessage ?? ""),
                dismissButton: .default(Text(L10n.Common.ok))
            )
        }
        .task {
            await viewModel.loadPDF(path: fileItem.path)
        }
    }

    @ViewBuilder
    private var pdfContentView: some View {
        if viewModel.isLoading {
            ProgressView(L10n.Common.loading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let document = viewModel.pdfDocument {
            PDFKitView(document: document)
        } else if viewModel.errorMessage != nil {
            ContentUnavailableView(
                "PDF読み込みエラー",
                systemImage: "exclamationmark.triangle",
                description: Text(viewModel.errorMessage ?? "")
            )
        } else {
            ContentUnavailableView(
                "PDFを読み込み中",
                systemImage: "doc.text",
                description: Text("しばらくお待ちください")
            )
        }
    }
}

/// PDFKitのPDFViewをSwiftUIでラップ
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}

#Preview {
    NavigationStack {
        PDFViewerView(
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
                id: "Docs/sample.pdf",
                name: "sample.pdf",
                type: .pdfFile,
                path: "Docs/sample.pdf",
                size: 1234,
                modifiedAt: Date()
            )
        )
    }
}
