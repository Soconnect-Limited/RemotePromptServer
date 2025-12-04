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
                .navigationTitle(L10n.Rooms.title)
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: Room.self) { room in
                    RoomDetailView(room: room, apiClient: detailAPIClient)
                }
                .toolbar { toolbarContent }
                .task {
                    print("[RoomsListView] .task START @ \(Date())")
                    // サーバー設定（URL + APIキー）が未完了なら読み込みをスキップ
                    guard ServerConfigurationStore.shared.currentConfiguration?.isFullyConfigured == true else {
                        hasLoadedOnce = true
                        print("[RoomsListView] Server not fully configured, skipping loadRooms")
                        return
                    }
                    await viewModel.loadRooms()
                    hasLoadedOnce = true
                    print("[RoomsListView] hasLoadedOnce = true @ \(Date())")
                }
                .refreshable {
                    print("[RoomsListView] .refreshable triggered @ \(Date())")
                    // 最低500msのローディング表示を確保（UXのため）
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await viewModel.loadRooms() }
                        group.addTask { try? await Task.sleep(for: .milliseconds(500)) }
                        await group.waitForAll()
                    }
                    // 触覚フィードバック
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    print("[RoomsListView] .refreshable completed @ \(Date())")
                }
                .overlay {
                    if viewModel.isLoading && hasLoadedOnce {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.2)
                                .padding(16)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
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
                    L10n.Rooms.deleteTitle,
                    isPresented: $showingDeleteConfirmation
                ) {
                    deleteConfirmationButtons
                } message: {
                    deleteConfirmationMessage
                }
                .alert(L10n.Common.error, isPresented: errorAlertBinding) {
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
        List {
            if !hasLoadedOnce || (viewModel.rooms.isEmpty && viewModel.isLoading) {
                loadingView
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if viewModel.rooms.isEmpty {
                emptyStateView
            } else {
                roomsForEach
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(L10n.Common.loading)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.6)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(L10n.Rooms.empty)
                .font(.headline)
            Text(L10n.Rooms.emptyHint)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.6)
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
                Label(L10n.Common.delete, systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                roomToEdit = room
            } label: {
                Label(L10n.Common.edit, systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !viewModel.rooms.isEmpty {
                Button(isEditMode ? L10n.Common.done : L10n.Common.edit) {
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
        Button(L10n.Common.delete, role: .destructive) {
            if let room = roomToDelete {
                Task {
                    _ = await viewModel.deleteRoom(room)
                    roomToDelete = nil
                }
            }
        }
        Button(L10n.Common.cancel, role: .cancel) {
            roomToDelete = nil
        }
    }

    @ViewBuilder
    private var deleteConfirmationMessage: some View {
        if let room = roomToDelete {
            Text(L10n.Rooms.deleteMessage(room.name))
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

        certificateErrorMessage = L10n.Certificate.mismatchMessage(
            stored: String(storedFingerprint.prefix(16)),
            received: String(receivedFingerprint.prefix(16))
        )
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
            .alert(L10n.Certificate.errorTitle, isPresented: $showingCertificateError) {
                certificateErrorButtons
            } message: {
                Text(certificateErrorMessage)
            }
            .alert(L10n.Certificate.changedTitle, isPresented: $showingSSECertificateChangedAlert) {
                certificateChangedButtons
            } message: {
                certificateChangedMessage
            }
            .alert(L10n.Certificate.revokedTitle, isPresented: $showingSSECertificateRevokedAlert) {
                certificateRevokedButtons
            } message: {
                certificateRevokedMessage
            }
            .alert(L10n.Certificate.modeChangedTitle, isPresented: $showingSSECertificateModeChangedAlert) {
                certificateModeChangedButtons
            } message: {
                certificateModeChangedMessage
            }
    }

    @ViewBuilder
    private var certificateErrorButtons: some View {
        if let fingerprint = pendingCertificateFingerprint {
            Button(L10n.Certificate.trustNew) {
                trustNewCertificate(fingerprint)
            }
        }
        Button(L10n.Common.openSettings) {
            viewModel.errorMessage = nil
            pendingCertificateFingerprint = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingServerSettings = true
            }
        }
        Button(L10n.Common.cancel, role: .cancel) {
            showingCertificateError = false
            pendingCertificateFingerprint = nil
        }
    }

    @ViewBuilder
    private var certificateChangedButtons: some View {
        if let event = sseCertificateChangedEvent {
            if event.effectiveAfterRestart {
                Button(L10n.Common.ok) {
                    sseCertificateChangedEvent = nil
                }
            } else {
                Button(L10n.Certificate.reconnect) {
                    sseCertificateChangedEvent = nil
                    Task {
                        await viewModel.loadRooms()
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {
                    sseCertificateChangedEvent = nil
                }
            }
        }
    }

    @ViewBuilder
    private var certificateChangedMessage: some View {
        if let event = sseCertificateChangedEvent {
            if event.effectiveAfterRestart {
                Text(L10n.Certificate.updatedRestart(event.reason))
            } else {
                Text(L10n.Certificate.updatedReconnect(event.reason))
            }
        }
    }

    @ViewBuilder
    private var certificateRevokedButtons: some View {
        Button(L10n.Common.openSettings) {
            sseCertificateRevokedEvent = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingServerSettings = true
            }
        }
        Button(L10n.Common.ok, role: .cancel) {
            sseCertificateRevokedEvent = nil
        }
    }

    @ViewBuilder
    private var certificateRevokedMessage: some View {
        if let event = sseCertificateRevokedEvent {
            Text(L10n.Certificate.revokedMessage(event.reason))
        }
    }

    @ViewBuilder
    private var certificateModeChangedButtons: some View {
        Button(L10n.Common.openSettings) {
            sseCertificateModeChangedEvent = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingServerSettings = true
            }
        }
        Button(L10n.Common.ok, role: .cancel) {
            sseCertificateModeChangedEvent = nil
        }
    }

    @ViewBuilder
    private var certificateModeChangedMessage: some View {
        if let event = sseCertificateModeChangedEvent {
            Text(L10n.Certificate.modeChangedMessage(from: event.modeBefore, to: event.modeAfter, reason: event.reason))
        }
    }
}

#Preview {
    RoomsListView()
}
