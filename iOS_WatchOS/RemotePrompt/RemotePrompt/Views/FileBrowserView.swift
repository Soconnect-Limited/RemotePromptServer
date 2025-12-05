import SwiftUI
import Foundation

struct FileBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: FileBrowserViewModel
    private let room: Room
    private let initialPath: String
    private let isRoot: Bool

    /// iPad: 選択中のファイル（Markdown or PDF）
    @State private var selectedFile: FileItem?
    /// iPad: SplitViewのサイドバー表示状態
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 画像アップロード関連
    @State private var showingImageSourceSheet = false
    @State private var selectedImageSource: ImagePickerSource?
    @State private var showingImagePicker = false

    /// サイズ超過画像のアラート用
    @State private var showingOversizedAlert = false
    @State private var pendingOversizedImages: [OversizedImage] = []

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
        Group {
            if horizontalSizeClass == .regular && isRoot {
                // iPad: SplitViewでファイル一覧とエディタを左右に表示
                iPadSplitView
            } else {
                // iPhone または サブディレクトリ: 従来のナビゲーション
                iPhoneContentView
            }
        }
        // 画像選択ダイアログ（共通）
        .confirmationDialog("画像を追加", isPresented: $showingImageSourceSheet, titleVisibility: .visible) {
            Button("フォトライブラリから選択") {
                selectedImageSource = .photoLibrary
                showingImagePicker = true
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("カメラで撮影") {
                    selectedImageSource = .camera
                    showingImagePicker = true
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        // 画像ピッカー（共通）
        .sheet(isPresented: $showingImagePicker, onDismiss: {
            // シートが閉じたら状態をリセット
            selectedImageSource = nil
        }) {
            if let source = selectedImageSource {
                ImagePickerView(
                    source: source,
                    onImagesSelected: { selectedImages in
                        showingImagePicker = false
                        Task {
                            await viewModel.uploadImages(selectedImages)
                        }
                    },
                    onOversizedImages: { oversizedImages in
                        // シートは既に閉じているはず（onImagesSelected or onCancelで閉じる）
                        pendingOversizedImages = oversizedImages
                        showingOversizedAlert = true
                    },
                    onCancel: {
                        showingImagePicker = false
                    }
                )
            }
        }
        // サイズ超過アラート（共通）
        .alert("ファイルサイズが100MBを超えています", isPresented: $showingOversizedAlert) {
            Button("オリジナル") {
                let images = pendingOversizedImages.map { oversized in
                    SelectedImage(data: oversized.originalData, filename: oversized.filename)
                }
                Task {
                    await viewModel.uploadImages(images)
                }
                pendingOversizedImages = []
            }
            Button("圧縮") {
                let images = pendingOversizedImages.compactMap { oversized -> SelectedImage? in
                    guard let compressedData = compressImageToFitSize(oversized.image, maxSize: 100_000_000) else {
                        return nil
                    }
                    let newFilename = (oversized.filename as NSString).deletingPathExtension + ".jpg"
                    return SelectedImage(data: compressedData, filename: newFilename)
                }
                Task {
                    await viewModel.uploadImages(images)
                }
                pendingOversizedImages = []
            }
            Button("キャンセル", role: .cancel) {
                pendingOversizedImages = []
            }
        } message: {
            let count = pendingOversizedImages.count
            let totalSize = pendingOversizedImages.reduce(0) { $0 + $1.originalSize }
            let sizeMB = Double(totalSize) / 1_000_000
            Text("\(count)件の画像（合計\(String(format: "%.1f", sizeMB))MB）が100MBを超えています。\nオリジナルをそのままアップロードしますか？圧縮しますか？")
        }
    }

    // MARK: - iPad SplitView

    private var iPadSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            fileListView
                .navigationTitle(displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // サイドバーには常に❌を表示（サイドバーが見える時に使う）
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
                    }
                }
        } detail: {
            if let file = selectedFile {
                fileDetailView(for: file)
                    .toolbar {
                        // サイドバーが非表示の時のみdetail側に閉じるボタンを表示
                        ToolbarItem(placement: .cancellationAction) {
                            if columnVisibility == .detailOnly {
                                Button(L10n.Common.close, action: { dismiss() })
                            }
                        }
                    }
            } else {
                ContentUnavailableView(
                    "ファイルを選択",
                    systemImage: "doc.text",
                    description: Text("左のリストからファイルを選択してください")
                )
                .toolbar {
                    // サイドバーが非表示の時のみdetail側に閉じるボタンを表示
                    ToolbarItem(placement: .cancellationAction) {
                        if columnVisibility == .detailOnly {
                            Button(L10n.Common.close, action: { dismiss() })
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await viewModel.loadFiles(path: initialPath)
        }
    }

    // MARK: - iPhone Navigation

    private var iPhoneContentView: some View {
        contentView
            .navigationDestination(for: FileItem.self) { item in
                if item.type == .directory {
                    FileBrowserView(room: room, path: item.path, isRoot: false)
                }
            }
    }

    // MARK: - iPad用ファイルリスト（SplitViewサイドバー用）

    private var fileListView: some View {
        Group {
            if viewModel.isLoading {
                ProgressView(L10n.Common.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.fileItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(L10n.Files.empty)
                        .foregroundColor(.secondary)
                    if viewModel.showRetry {
                        retryButton
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.fileItems, selection: $selectedFile) { item in
                    if item.type == .directory {
                        // ディレクトリ: タップでそのディレクトリに移動
                        Button {
                            Task {
                                await viewModel.loadFiles(path: item.path)
                            }
                        } label: {
                            FileRow(item: item)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = item.path
                            } label: {
                                Label(L10n.Files.copyPath, systemImage: "doc.on.doc")
                            }
                        }
                    } else {
                        // ファイル: タップで右側のエディタに表示
                        FileRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedFile = item
                            }
                            .listRowBackground(selectedFile == item ? Color.accentColor.opacity(0.2) : nil)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = item.path
                                } label: {
                                    Label(L10n.Files.copyPath, systemImage: "doc.on.doc")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .alert(isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Alert(title: Text(L10n.Common.error), message: Text(viewModel.errorMessage ?? L10n.Files.unknownError), dismissButton: .default(Text(L10n.Common.ok)))
        }
        // 下部: 画像アップロードバー
        .safeAreaInset(edge: .bottom) {
            imageUploadBar
        }
        // パンくずナビゲーション
        .safeAreaInset(edge: .top) {
            if !viewModel.currentPath.isEmpty {
                HStack {
                    Button {
                        Task {
                            let parentPath = viewModel.currentPath
                                .split(separator: "/")
                                .dropLast()
                                .joined(separator: "/")
                            await viewModel.loadFiles(path: parentPath)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("戻る")
                        }
                        .font(.subheadline)
                    }
                    Spacer()
                    Text(viewModel.currentPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    // MARK: - iPhone用コンテンツ

    private var contentView: some View {
        Group {
                if viewModel.isLoading {
                    ProgressView(L10n.Common.loading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.fileItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(L10n.Files.empty)
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
                                    Label(L10n.Files.copyPath, systemImage: "doc.on.doc")
                                }
                            }
                        } else if item.type == .markdownFile {
                            NavigationLink {
                                MarkdownEditorView(room: room, fileItem: item)
                            } label: {
                                FileRow(item: item)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = item.path
                                } label: {
                                    Label(L10n.Files.copyPath, systemImage: "doc.on.doc")
                                }
                            }
                        } else if item.type == .pdfFile {
                            NavigationLink {
                                PDFViewerView(room: room, fileItem: item)
                            } label: {
                                FileRow(item: item)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = item.path
                                } label: {
                                    Label(L10n.Files.copyPath, systemImage: "doc.on.doc")
                                }
                            }
                        } else if item.type == .imageFile {
                            NavigationLink {
                                ImageViewerView(room: room, fileItem: item)
                            } label: {
                                FileRow(item: item)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = item.path
                                } label: {
                                    Label(L10n.Files.copyPath, systemImage: "doc.on.doc")
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
                Alert(title: Text(L10n.Common.error), message: Text(viewModel.errorMessage ?? L10n.Files.unknownError), dismissButton: .default(Text(L10n.Common.ok)))
            }
            // 下部: 画像アップロードバー
            .safeAreaInset(edge: .bottom) {
                imageUploadBar
            }
            .task {
                await viewModel.loadFiles(path: initialPath)
            }
    }

    private var retryButton: some View {
        Button {
            Task { await viewModel.loadFiles(path: viewModel.currentPath) }
        } label: {
            Label(L10n.Files.retry, systemImage: "arrow.clockwise")
        }
    }

    /// iPad SplitView: ファイルタイプに応じた詳細ビュー
    @ViewBuilder
    private func fileDetailView(for file: FileItem) -> some View {
        switch file.type {
        case .markdownFile:
            MarkdownEditorView(room: room, fileItem: file, isEmbeddedInSplitView: true)
        case .pdfFile:
            PDFViewerView(room: room, fileItem: file, isEmbeddedInSplitView: true)
        case .imageFile:
            ImageViewerView(room: room, fileItem: file)
        case .directory:
            // ディレクトリは詳細ビューに表示しない
            EmptyView()
        }
    }

    // MARK: - 画像アップロードバー

    private var imageUploadBar: some View {
        HStack {
            if viewModel.isUploading {
                ProgressView()
                    .padding(.trailing, 8)
                Text(viewModel.uploadProgress ?? "アップロード中...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Button {
                    showingImageSourceSheet = true
                } label: {
                    Label("画像を追加", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
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
