import Combine
import SwiftUI

struct ImageViewerView: View {
    let room: Room
    let fileItem: FileItem
    var isEmbeddedInSplitView: Bool = false

    @StateObject private var viewModel: ImageViewerViewModel

    /// ピンチズーム用
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    /// ドラッグ用
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(room: Room, fileItem: FileItem, isEmbeddedInSplitView: Bool = false) {
        self.room = room
        self.fileItem = fileItem
        self.isEmbeddedInSplitView = isEmbeddedInSplitView
        _viewModel = StateObject(wrappedValue: ImageViewerViewModel(roomId: room.id))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("読み込み中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = viewModel.image {
                GeometryReader { geometry in
                    let imageSize = image.size
                    let containerSize = geometry.size

                    // 画面に収まるサイズを計算（アスペクト比を維持）
                    let widthRatio = containerSize.width / imageSize.width
                    let heightRatio = containerSize.height / imageSize.height
                    let fitRatio = min(widthRatio, heightRatio)
                    let fittedWidth = imageSize.width * fitRatio
                    let fittedHeight = imageSize.height * fitRatio

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fittedWidth * scale, height: fittedHeight * scale)
                        .offset(offset)
                        .frame(width: containerSize.width, height: containerSize.height)
                        .contentShape(Rectangle())
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = lastScale * value
                                    scale = min(max(newScale, 1.0), 5.0) // 1〜5倍
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale == 1.0 {
                                        // ズームリセット時はオフセットもリセット
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            // ダブルタップでズームリセット
                            withAnimation(.easeOut(duration: 0.3)) {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                }
                .background(Color(.systemBackground))
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("再読み込み") {
                        Task {
                            await viewModel.loadImage(path: fileItem.path)
                        }
                    }
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "画像がありません",
                    systemImage: "photo",
                    description: Text("画像を読み込めませんでした")
                )
            }
        }
        .navigationTitle(fileItem.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: fileItem.id) {
            // fileItem.idが変わったら再読み込み
            await viewModel.loadImage(path: fileItem.path)
        }
        .onChange(of: fileItem.id) { _, newId in
            // iPad SplitView用: 選択ファイルが変わったらリセット
            viewModel.reset()
            // ズーム状態もリセット
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
}

@MainActor
final class ImageViewerViewModel: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let roomId: String
    private let deviceId: String
    private let fileService: FileService

    init(roomId: String, deviceId: String = APIClient.getDeviceId(), fileService: FileService = FileService()) {
        self.roomId = roomId
        self.deviceId = deviceId
        self.fileService = fileService
    }

    func loadImage(path: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let data = try await fileService.readImageFile(roomId: roomId, path: path, deviceId: deviceId)
            await MainActor.run {
                if let uiImage = UIImage(data: data) {
                    self.image = uiImage
                } else {
                    self.errorMessage = "画像の読み込みに失敗しました"
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// 状態をリセット（別の画像に切り替える前に呼ぶ）
    func reset() {
        image = nil
        errorMessage = nil
        isLoading = false
    }
}
