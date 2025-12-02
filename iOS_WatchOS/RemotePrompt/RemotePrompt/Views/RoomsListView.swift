import SwiftUI
import Combine

struct RoomsListView: View {
    @StateObject private var viewModel: RoomsViewModel
    @State private var showingCreateRoom = false
    @State private var showingServerSettings = false
    @State private var hasLoadedOnce = false
    @State private var showingCertificateError = false
    @State private var certificateErrorMessage = ""
    @State private var pendingCertificateFingerprint: String?
    @State private var isEditMode = false
    private let detailAPIClient: APIClientProtocol

    init(viewModel: RoomsViewModel? = nil) {
        if let viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
            self.detailAPIClient = viewModel.apiClient
        } else if AppEnvironment.isUITesting {
            let previewClient = PreviewAPIClient()
            let vm = RoomsViewModel(
                apiClient: previewClient,
                deviceIdProvider: { "uitest-device" },
                skipAPIKeyCheck: true
            )
            _viewModel = StateObject(wrappedValue: vm)
            self.detailAPIClient = previewClient
        } else {
            let vm = RoomsViewModel()
            _viewModel = StateObject(wrappedValue: vm)
            self.detailAPIClient = vm.apiClient
        }
    }

    var body: some View {
        // デバッグ: bodyの再評価タイミング
        let _ = print("[RoomsListView] body evaluated @ \(Date()), rooms.count=\(viewModel.rooms.count), hasLoadedOnce=\(hasLoadedOnce)")

        NavigationStack {
            List {
                if !hasLoadedOnce || (viewModel.rooms.isEmpty && viewModel.isLoading) {
                    HStack {
                        Spacer()
                        ProgressView("ルームを読み込み中...")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if viewModel.rooms.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("ルームがありません")
                            .font(.headline)
                        Text("右上のボタンから新しいルームを作成してください")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.rooms) { room in
                        NavigationLink(value: room) {
                            RoomRowView(room: room)
                        }
                    }
                    .onDelete(perform: deleteRooms)
                    .onMove(perform: moveRooms)
                    .onAppear {
                        print("[RoomsListView] ✅ ROOMS VISIBLE @ \(Date())")
                    }
                }
            }
            .accessibilityIdentifier("rooms.list")
            .listStyle(.plain)
            .navigationTitle("Rooms")
            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
            .navigationDestination(for: Room.self) { room in
                RoomDetailView(room: room, apiClient: detailAPIClient)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // カスタムEditボタン（標準EditButtonのAutoLayout警告を回避）
                    if !viewModel.rooms.isEmpty {
                        Button(isEditMode ? "完了" : "編集") {
                            withAnimation {
                                isEditMode.toggle()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingServerSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityIdentifier("rooms.settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateRoom = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("rooms.add")
                }
            }
            .task {
                print("[RoomsListView] .task START @ \(Date())")
                await viewModel.loadRooms()
                hasLoadedOnce = true
                print("[RoomsListView] hasLoadedOnce = true @ \(Date())")
            }
            .refreshable {
                await viewModel.loadRooms()
            }
            .sheet(isPresented: $showingCreateRoom) {
                CreateRoomView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingServerSettings) {
                ServerSettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .alert("エラー", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            // 証明書エラー専用ダイアログ（即時表示）
            .alert("証明書エラー", isPresented: $showingCertificateError) {
                if let fingerprint = pendingCertificateFingerprint {
                    Button("新しい証明書を信頼する") {
                        trustNewCertificate(fingerprint: fingerprint)
                    }
                }
                Button("設定を開く") {
                    // エラーメッセージもクリア（ルーム取得失敗アラートを抑制）
                    viewModel.errorMessage = nil
                    pendingCertificateFingerprint = nil
                    // アラートが自動で閉じてからシートを開く
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showingServerSettings = true
                    }
                }
                Button("キャンセル", role: .cancel) {
                    showingCertificateError = false
                    pendingCertificateFingerprint = nil
                }
            } message: {
                Text(certificateErrorMessage)
            }
            // 証明書ミスマッチ通知を購読
            .onReceive(NotificationCenter.default.publisher(for: CertificatePinningDelegate.certificateMismatchNotification)) { notification in
                handleCertificateMismatch(notification)
            }
        }
    }

    // MARK: - Certificate Error Handling

    private func handleCertificateMismatch(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let storedFingerprint = userInfo["storedFingerprint"] as? String,
              let receivedFingerprint = userInfo["receivedFingerprint"] as? String else {
            return
        }

        // ローディング中なら即座にエラーダイアログを表示
        print("[RoomsListView] Certificate mismatch detected - showing dialog immediately")

        certificateErrorMessage = """
        サーバー証明書が変更されました。

        保存済み: \(storedFingerprint.prefix(16))...
        受信: \(receivedFingerprint.prefix(16))...

        これが予期された変更であれば、新しい証明書を信頼してください。
        """
        pendingCertificateFingerprint = receivedFingerprint
        showingCertificateError = true
    }

    private func trustNewCertificate(fingerprint: String) {
        ServerConfigurationStore.shared.trustCertificate(fingerprint: fingerprint)
        CertificatePinningDelegate.shared.clearError()
        APIClient.shared.invalidateSession()
        pendingCertificateFingerprint = nil

        // リロード
        Task {
            await viewModel.loadRooms()
        }
    }

    private func deleteRooms(at offsets: IndexSet) {
        Task {
            for index in offsets {
                guard viewModel.rooms.indices.contains(index) else { continue }
                let room = viewModel.rooms[index]
                _ = await viewModel.deleteRoom(room)
            }
        }
    }

    private func moveRooms(from source: IndexSet, to destination: Int) {
        viewModel.moveRoom(from: source, to: destination)
    }
}

#Preview {
    RoomsListView()
}
