import SwiftUI

/// サーバー接続設定画面
struct ServerSettingsView: View {
    @StateObject private var viewModel = ServerSettingsViewModel()
    @StateObject private var bonjourDiscovery = BonjourDiscovery.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var newAlternativeURL: String = ""
    @State private var showResetConfirmation: Bool = false
    @State private var showResetAllConfirmation: Bool = false
    @State private var showBonjourSection: Bool = true
    @State private var showQRCodeSheet: Bool = false
    @State private var showQRScannerSheet: Bool = false

    /// iPad向けの最大フォーム幅
    private let maxFormWidth: CGFloat = 600

    var body: some View {
        NavigationStack {
            Form {
                // bonjourSection  // Bonjour自動検出は一時的に非表示
                serverURLSection
                alternativeURLsSection
                apiKeySection
                aiProvidersSection
                connectionStatusSection
                certificateSection
                advancedSection
            }
            .navigationTitle(L10n.Settings.serverTitle)
            .navigationBarTitleDisplayMode(horizontalSizeClass == .regular ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        viewModel.saveConfiguration()
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .alert(L10n.Certificate.title, isPresented: $viewModel.showCertificateAlert) {
                certificateAlertButtons
            } message: {
                certificateAlertMessage
            }
            .alert(L10n.Certificate.changedTitle, isPresented: $viewModel.showCertificateChangedAlert) {
                certificateChangedAlertButtons
            } message: {
                certificateChangedAlertMessage
            }
            .alert(L10n.Certificate.reset, isPresented: $showResetConfirmation) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.reset, role: .destructive) {
                    viewModel.resetCertificateTrust()
                }
            } message: {
                Text(L10n.Certificate.resetConfirm)
            }
            .alert(L10n.Settings.resetAllTitle, isPresented: $showResetAllConfirmation) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Settings.resetAll, role: .destructive) {
                    viewModel.resetAllSettings()
                }
            } message: {
                Text(L10n.Settings.resetAllConfirm)
            }
        }
    }

    // MARK: - Bonjour Section

    private var bonjourSection: some View {
        Section {
            if bonjourDiscovery.isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(L10n.Bonjour.searching)
                        .foregroundColor(.secondary)
                }
            }

            if bonjourDiscovery.discoveredServers.isEmpty && !bonjourDiscovery.isSearching {
                Text(L10n.Bonjour.notfound)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            ForEach(bonjourDiscovery.discoveredServers) { server in
                Button {
                    selectDiscoveredServer(server)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .foregroundColor(.primary)
                            if let sslMode = server.metadata.sslMode {
                                Text(sslMode == "self_signed" ? L10n.Certificate.selfSigned : L10n.Certificate.commercial)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }

            Button {
                if bonjourDiscovery.isSearching {
                    bonjourDiscovery.stopSearching()
                } else {
                    bonjourDiscovery.startSearching()
                }
            } label: {
                HStack {
                    Image(systemName: bonjourDiscovery.isSearching ? "stop.fill" : "magnifyingglass")
                    Text(bonjourDiscovery.isSearching ? L10n.Bonjour.stop : L10n.Bonjour.search)
                }
            }
        } header: {
            HStack {
                Text(L10n.Bonjour.auto)
                Spacer()
                Button {
                    showBonjourSection.toggle()
                } label: {
                    Image(systemName: showBonjourSection ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
        } footer: {
            Text(L10n.Bonjour.hint)
        }
        .onAppear {
            // 自動的に検索を開始
            if viewModel.serverURL.isEmpty {
                bonjourDiscovery.startSearching()
            }
        }
        .onDisappear {
            bonjourDiscovery.stopSearching()
        }
    }

    private func selectDiscoveredServer(_ server: DiscoveredServer) {
        Task {
            if let resolved = await bonjourDiscovery.resolveServer(server) {
                viewModel.serverURL = resolved.url
                viewModel.serverName = server.name

                // フィンガープリントがあれば設定（後で確認ダイアログで正式に信頼する）
                if let fingerprint = server.metadata.fingerprint {
                    print("[ServerSettings] Server fingerprint hint: \(fingerprint)")
                }
            }
        }
    }

    // MARK: - Server URL Section

    private var serverURLSection: some View {
        Section {
            // サーバー名入力欄は一時的に非表示
            // ZStack(alignment: .leading) {
            //     if viewModel.serverName.isEmpty {
            //         Text("例: My Server")
            //             .foregroundColor(Color(UIColor.placeholderText))
            //     }
            //     TextField("", text: $viewModel.serverName)
            // }

            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .leading) {
                    if viewModel.serverURL.isEmpty {
                        Text(L10n.Settings.serverUrlPlaceholder)
                            .foregroundColor(Color(UIColor.placeholderText))
                    }
                    TextField("", text: $viewModel.serverURL)
                        .textContentType(nil)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                if !viewModel.serverURL.isEmpty && !viewModel.isValidMainURL {
                    Text(L10n.Settings.serverUrlInvalid)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        } header: {
            Text(L10n.Settings.sectionInfo)
        } footer: {
            Text(L10n.Settings.serverUrlHint)
        }
    }

    // MARK: - Alternative URLs Section

    private var alternativeURLsSection: some View {
        Section {
            ForEach(viewModel.alternativeURLs.indices, id: \.self) { index in
                HStack {
                    Text(verbatim: viewModel.alternativeURLs[index])
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        viewModel.removeAlternativeURL(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                ZStack(alignment: .leading) {
                    if newAlternativeURL.isEmpty {
                        Text(L10n.AltUrl.placeholder)
                            .foregroundColor(Color(UIColor.placeholderText))
                    }
                    TextField("", text: $newAlternativeURL)
                        .textContentType(nil)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Button {
                    viewModel.addAlternativeURL(newAlternativeURL)
                    newAlternativeURL = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .disabled(newAlternativeURL.isEmpty)
            }

            Toggle(L10n.AltUrl.toggle, isOn: $viewModel.autoFallback)
        } header: {
            Text(L10n.AltUrl.title)
        } footer: {
            Text(L10n.AltUrl.hint)
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        Section {
            ZStack(alignment: .leading) {
                if viewModel.apiKey.isEmpty {
                    Text(L10n.Settings.apiKeyPlaceholder)
                        .foregroundColor(Color(UIColor.placeholderText))
                }
                SecureField("", text: $viewModel.apiKey)
                    .textContentType(.password)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
        } header: {
            Text(L10n.Settings.sectionAuth)
        } footer: {
            Text(L10n.Settings.apiKeyHint)
        }
    }

    // MARK: - AI Providers Section

    private var aiProvidersSection: some View {
        Section {
            ForEach(viewModel.aiProviders) { config in
                AIProviderRow(
                    config: config,
                    onToggle: {
                        viewModel.toggleAIProvider(config.provider)
                    }
                )
            }
            .onMove { source, destination in
                viewModel.moveAIProvider(from: source, to: destination)
            }
        } header: {
            HStack {
                Text(L10n.Settings.sectionAI)
                Spacer()
                EditButton()
                    .font(.caption)
            }
        } footer: {
            Text(L10n.Settings.aiSortHint)
        }
    }

    // MARK: - Connection Status Section

    private var connectionStatusSection: some View {
        Section {
            HStack {
                connectionStatusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionStatusText)
                        .font(.body)
                    if let url = viewModel.connectedURL {
                        Text(url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            Button {
                Task {
                    await viewModel.testConnection()
                }
            } label: {
                HStack {
                    if case .connecting = viewModel.connectionStatus {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(L10n.Connection.test)
                }
            }
            .disabled(viewModel.serverURL.isEmpty || viewModel.connectionStatus == .connecting)
        } header: {
            Text(L10n.Settings.sectionConnection)
        }
    }

    private var connectionStatusIcon: some View {
        Group {
            switch viewModel.connectionStatus {
            case .idle:
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            case .connecting:
                Image(systemName: "circle.dotted")
                    .foregroundColor(.blue)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.title2)
    }

    private var connectionStatusText: String {
        switch viewModel.connectionStatus {
        case .idle:
            return L10n.Connection.idle
        case .connecting:
            return L10n.Connection.testing
        case .success:
            return L10n.Connection.success
        case .failed(let error):
            return error.localizedDescription
        }
    }

    // MARK: - Certificate Section

    private var certificateSection: some View {
        Group {
            if let info = viewModel.certificateInfo {
                Section {
                    LabeledContent(L10n.Certificate.fingerprint) {
                        Text(info.shortFingerprint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if let cn = info.commonName {
                        LabeledContent(L10n.Certificate.commonName, value: cn)
                    }

                    if let validUntil = info.validUntil {
                        LabeledContent(L10n.Certificate.validUntil) {
                            Text(validUntil, style: .date)
                        }
                    }

                    if info.isSelfSigned {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.orange)
                            Text(L10n.Certificate.selfSigned)
                                .foregroundColor(.orange)
                        }
                    }

                    // ペンディングリスタートの警告
                    if info.pendingRestart == true, let pending = info.pendingFingerprint {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading) {
                                Text(L10n.Certificate.newPending)
                                    .font(.caption)
                                Text(L10n.Certificate.newPendingHint)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(L10n.Settings.sectionCertificate)
                }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section {
            // 設定共有ボタン
            Button {
                showQRCodeSheet = true
            } label: {
                HStack {
                    Image(systemName: "qrcode")
                    Text(L10n.QR.shareTitle)
                }
            }
            .disabled(viewModel.serverURL.isEmpty)

            // 設定インポートボタン
            Button {
                showQRScannerSheet = true
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text(L10n.QR.importTitle)
                }
            }

            Button(L10n.Settings.resetCertificate) {
                showResetConfirmation = true
            }
            .foregroundColor(.orange)

            Button(L10n.Settings.resetAll) {
                showResetAllConfirmation = true
            }
            .foregroundColor(.red)
        } header: {
            Text(L10n.Settings.sectionAdvanced)
        }
        .sheet(isPresented: $showQRCodeSheet) {
            SettingsQRCodeView()
        }
        .sheet(isPresented: $showQRScannerSheet) {
            SettingsQRScannerView()
        }
    }

    // MARK: - Certificate Alert

    private var certificateAlertButtons: some View {
        Group {
            Button(L10n.Common.cancel, role: .cancel) {
                viewModel.rejectCertificate()
            }
            Button(L10n.Certificate.trust) {
                viewModel.trustCertificate()
            }
        }
    }

    private var certificateAlertMessage: some View {
        VStack {
            if let info = viewModel.pendingCertificateInfo ?? viewModel.certificateInfo {
                Text("\(L10n.Certificate.verifyHint)\n\n\(L10n.Certificate.fingerprint):\n\(info.fingerprint)")
            } else {
                Text(L10n.Certificate.verifyFailed)
            }
        }
    }

    // MARK: - Certificate Changed Alert

    private var certificateChangedAlertButtons: some View {
        Group {
            Button(L10n.Common.cancel, role: .cancel) {
                viewModel.rejectCertificate()
            }
            Button(L10n.Certificate.trustNew, role: .destructive) {
                viewModel.trustCertificate()
            }
        }
    }

    private var certificateChangedAlertMessage: some View {
        VStack {
            Text(L10n.Certificate.changedWarning)

            if let old = ServerConfigurationStore.shared.currentConfiguration?.certificateFingerprint,
               let new = viewModel.pendingCertificateInfo?.fingerprint {
                Text(L10n.Certificate.changedDetail(old: String(old.prefix(20)), new: String(new.prefix(20))))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - AI Provider Row

/// AIプロバイダー設定行
private struct AIProviderRow: View {
    let config: AIProviderConfiguration
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: config.provider.systemImage)
                .foregroundColor(config.isEnabled ? .accentColor : .secondary)
                .frame(width: 24)

            Text(config.provider.displayName)
                .foregroundColor(config.isEnabled ? .primary : .secondary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
    }
}

// MARK: - Preview

#Preview {
    ServerSettingsView()
}
