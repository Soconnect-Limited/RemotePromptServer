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
    @State private var roomToEdit: Room?
    @State private var roomToDelete: Room?
    @State private var showingDeleteConfirmation = false
    // SSE証明書イベント用のダイアログ状態
    @State private var showingSSECertificateChangedAlert = false
    @State private var sseCertificateChangedEvent: CertificateChangedEvent?
    @State private var showingSSECertificateRevokedAlert = false
    @State private var sseCertificateRevokedEvent: CertificateRevokedEvent?
    @State private var showingSSECertificateModeChangedAlert = false
    @State private var sseCertificateModeChangedEvent: CertificateModeChangedEvent?
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
        let _ = print("[RoomsListView] body evaluated @ \(Date()), rooms.count=\(viewModel.rooms.count), hasLoadedOnce=\(hasLoadedOnce)")

        NavigationStack {
            roomsList
                .accessibilityIdentifier("rooms.list")
                .listStyle(.plain)
                .navigationTitle("Rooms")
                .navigationDestination(for: Room.self) { room in
                    RoomDetailView(room: room, apiClient: detailAPIClient)
                }
                .toolbar { toolbarContent }
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
                .sheet(item: $roomToEdit) { room in
                    EditRoomView(viewModel: viewModel, room: room)
                        .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showingServerSettings) {
                    ServerSettingsView()
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .alert(
                    "ルームを削除",
                    isPresented: $showingDeleteConfirmation
                ) {
                    deleteConfirmationButtons
                } message: {
                    deleteConfirmationMessage
                }
                .alert("エラー", isPresented: errorAlertBinding) {
                    Button("OK", role: .cancel) { viewModel.errorMessage = nil }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
                .modifier(CertificateAlertsModifier(
                    showingCertificateError: $showingCertificateError,
                    certificateErrorMessage: certificateErrorMessage,
                    pendingCertificateFingerprint: $pendingCertificateFingerprint,
                    showingServerSettings: $showingServerSettings,
                    showingSSECertificateChangedAlert: $showingSSECertificateChangedAlert,
                    sseCertificateChangedEvent: $sseCertificateChangedEvent,
                    showingSSECertificateRevokedAlert: $showingSSECertificateRevokedAlert,
                    sseCertificateRevokedEvent: $sseCertificateRevokedEvent,
                    showingSSECertificateModeChangedAlert: $showingSSECertificateModeChangedAlert,
                    sseCertificateModeChangedEvent: $sseCertificateModeChangedEvent,
                    viewModel: viewModel,
                    trustNewCertificate: trustNewCertificate
                ))
                .onReceive(NotificationCenter.default.publisher(for: CertificatePinningDelegate.certificateMismatchNotification)) { notification in
                    handleCertificateMismatch(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: SSEManager.certificateChangedNotification)) { notification in
                    if let event = notification.object as? CertificateChangedEvent {
                        sseCertificateChangedEvent = event
                        showingSSECertificateChangedAlert = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: SSEManager.certificateRevokedNotification)) { notification in
                    if let event = notification.object as? CertificateRevokedEvent {
                        sseCertificateRevokedEvent = event
                        showingSSECertificateRevokedAlert = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: SSEManager.certificateModeChangedNotification)) { notification in
                    if let event = notification.object as? CertificateModeChangedEvent {
                        sseCertificateModeChangedEvent = event
                        showingSSECertificateModeChangedAlert = true
                    }
                }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var roomsList: some View {
        if !hasLoadedOnce || (viewModel.rooms.isEmpty && viewModel.isLoading) {
            loadingView
        } else {
            List {
                if viewModel.rooms.isEmpty {
                    emptyStateView
                } else {
                    roomsForEach
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("読み込み中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
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
    }

    @ViewBuilder
    private var roomsForEach: some View {
        if isEditMode {
            ForEach(viewModel.rooms) { room in
                editableRoomRow(for: room)
            }
            .onMove { source, destination in
                moveRooms(from: source, to: destination)
            }
            .onAppear {
                print("[RoomsListView] ✅ ROOMS VISIBLE (edit mode) @ \(Date())")
            }
        } else {
            ForEach(viewModel.rooms) { room in
                NavigationLink(value: room) {
                    RoomRowView(room: room)
                }
            }
            .onAppear {
                print("[RoomsListView] ✅ ROOMS VISIBLE @ \(Date())")
            }
        }
    }

    private func editableRoomRow(for room: Room) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .padding(.trailing, 4)
            RoomRowView(room: room)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                roomToDelete = room
                showingDeleteConfirmation = true
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                roomToEdit = room
            } label: {
                Label("編集", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
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

    @ViewBuilder
    private var deleteConfirmationButtons: some View {
        Button("削除", role: .destructive) {
            if let room = roomToDelete {
                Task {
                    _ = await viewModel.deleteRoom(room)
                    roomToDelete = nil
                }
            }
        }
        Button("キャンセル", role: .cancel) {
            roomToDelete = nil
        }
    }

    @ViewBuilder
    private var deleteConfirmationMessage: some View {
        if let room = roomToDelete {
            Text("「\(room.name)」を削除すると、関連するスレッドとメッセージも削除されます。")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    // MARK: - Actions

    private func handleCertificateMismatch(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let storedFingerprint = userInfo["storedFingerprint"] as? String,
              let receivedFingerprint = userInfo["receivedFingerprint"] as? String else {
            return
        }

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

        Task {
            await viewModel.loadRooms()
        }
    }

    private func moveRooms(from source: IndexSet, to destination: Int) {
        viewModel.moveRoom(from: source, to: destination)
    }
}

// MARK: - Certificate Alerts Modifier

private struct CertificateAlertsModifier: ViewModifier {
    @Binding var showingCertificateError: Bool
    let certificateErrorMessage: String
    @Binding var pendingCertificateFingerprint: String?
    @Binding var showingServerSettings: Bool
    @Binding var showingSSECertificateChangedAlert: Bool
    @Binding var sseCertificateChangedEvent: CertificateChangedEvent?
    @Binding var showingSSECertificateRevokedAlert: Bool
    @Binding var sseCertificateRevokedEvent: CertificateRevokedEvent?
    @Binding var showingSSECertificateModeChangedAlert: Bool
    @Binding var sseCertificateModeChangedEvent: CertificateModeChangedEvent?
    let viewModel: RoomsViewModel
    let trustNewCertificate: (String) -> Void

    func body(content: Content) -> some View {
        content
            .alert("証明書エラー", isPresented: $showingCertificateError) {
                certificateErrorButtons
            } message: {
                Text(certificateErrorMessage)
            }
            .alert("証明書が変更されます", isPresented: $showingSSECertificateChangedAlert) {
                certificateChangedButtons
            } message: {
                certificateChangedMessage
            }
            .alert("証明書が失効しました", isPresented: $showingSSECertificateRevokedAlert) {
                certificateRevokedButtons
            } message: {
                certificateRevokedMessage
            }
            .alert("証明書モードが変更されました", isPresented: $showingSSECertificateModeChangedAlert) {
                certificateModeChangedButtons
            } message: {
                certificateModeChangedMessage
            }
    }

    @ViewBuilder
    private var certificateErrorButtons: some View {
        if let fingerprint = pendingCertificateFingerprint {
            Button("新しい証明書を信頼する") {
                trustNewCertificate(fingerprint)
            }
        }
        Button("設定を開く") {
            viewModel.errorMessage = nil
            pendingCertificateFingerprint = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingServerSettings = true
            }
        }
        Button("キャンセル", role: .cancel) {
            showingCertificateError = false
            pendingCertificateFingerprint = nil
        }
    }

    @ViewBuilder
    private var certificateChangedButtons: some View {
        if let event = sseCertificateChangedEvent {
            if event.effectiveAfterRestart {
                Button("OK") {
                    sseCertificateChangedEvent = nil
                }
            } else {
                Button("新しい証明書で再接続") {
                    sseCertificateChangedEvent = nil
                    Task {
                        await viewModel.loadRooms()
                    }
                }
                Button("キャンセル", role: .cancel) {
                    sseCertificateChangedEvent = nil
                }
            }
        }
    }

    @ViewBuilder
    private var certificateChangedMessage: some View {
        if let event = sseCertificateChangedEvent {
            if event.effectiveAfterRestart {
                Text("サーバー証明書が更新されました。\n\nサーバー再起動後に再接続してください。\n\n理由: \(event.reason)")
            } else {
                Text("サーバー証明書が更新されました。\n\n新しい証明書で再接続しますか？\n\n理由: \(event.reason)")
            }
        }
    }

    @ViewBuilder
    private var certificateRevokedButtons: some View {
        Button("設定を開く") {
            sseCertificateRevokedEvent = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingServerSettings = true
            }
        }
        Button("OK", role: .cancel) {
            sseCertificateRevokedEvent = nil
        }
    }

    @ViewBuilder
    private var certificateRevokedMessage: some View {
        if let event = sseCertificateRevokedEvent {
            Text("サーバー証明書が失効しました。\n\nサーバー再起動後に設定画面から再接続してください。\n\n理由: \(event.reason)")
        }
    }

    @ViewBuilder
    private var certificateModeChangedButtons: some View {
        Button("設定を開く") {
            sseCertificateModeChangedEvent = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingServerSettings = true
            }
        }
        Button("OK", role: .cancel) {
            sseCertificateModeChangedEvent = nil
        }
    }

    @ViewBuilder
    private var certificateModeChangedMessage: some View {
        if let event = sseCertificateModeChangedEvent {
            Text("証明書モードが「\(event.modeBefore)」から「\(event.modeAfter)」に変更されました。\n\n設定画面から証明書を再確認してください。\n\n理由: \(event.reason)")
        }
    }
}

#Preview {
    RoomsListView()
}
