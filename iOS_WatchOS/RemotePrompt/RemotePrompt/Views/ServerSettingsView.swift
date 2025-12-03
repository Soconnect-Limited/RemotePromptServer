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

    /// iPad向けの最大フォーム幅
    private let maxFormWidth: CGFloat = 600

    var body: some View {
        NavigationStack {
            Form {
                bonjourSection
                serverURLSection
                alternativeURLsSection
                apiKeySection
                aiProvidersSection
                connectionStatusSection
                certificateSection
                advancedSection
            }
            .navigationTitle("サーバー設定")
            .navigationBarTitleDisplayMode(horizontalSizeClass == .regular ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        viewModel.saveConfiguration()
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .alert("証明書の確認", isPresented: $viewModel.showCertificateAlert) {
                certificateAlertButtons
            } message: {
                certificateAlertMessage
            }
            .alert("証明書が変更されました", isPresented: $viewModel.showCertificateChangedAlert) {
                certificateChangedAlertButtons
            } message: {
                certificateChangedAlertMessage
            }
            .alert("証明書信頼をリセット", isPresented: $showResetConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("リセット", role: .destructive) {
                    viewModel.resetCertificateTrust()
                }
            } message: {
                Text("次回接続時に証明書の再確認が必要になります。")
            }
            .alert("すべての設定をリセット", isPresented: $showResetAllConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("すべてリセット", role: .destructive) {
                    viewModel.resetAllSettings()
                }
            } message: {
                Text("サーバー接続情報がすべて削除されます。")
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
                    Text("サーバーを検索中...")
                        .foregroundColor(.secondary)
                }
            }

            if bonjourDiscovery.discoveredServers.isEmpty && !bonjourDiscovery.isSearching {
                Text("ローカルネットワーク上にサーバーが見つかりません")
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
                                Text(sslMode == "self_signed" ? "自己署名証明書" : "商用証明書")
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
                    Text(bonjourDiscovery.isSearching ? "検索を停止" : "サーバーを検索")
                }
            }
        } header: {
            HStack {
                Text("自動検出")
                Spacer()
                Button {
                    showBonjourSection.toggle()
                } label: {
                    Image(systemName: showBonjourSection ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
        } footer: {
            Text("同じネットワーク上のRemotePromptサーバーを自動検出します。")
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
            TextField("例: My Server", text: $viewModel.serverName)

            VStack(alignment: .leading, spacing: 4) {
                TextField("例: https://192.168.1.100:8443", text: $viewModel.serverURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                if !viewModel.serverURL.isEmpty && !viewModel.isValidMainURL {
                    Text("https:// で始まるURLを入力してください")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        } header: {
            Text("サーバー情報")
        } footer: {
            Text("RemotePromptサーバーのURLを入力してください。ポート番号も含めてください。")
        }
    }

    // MARK: - Alternative URLs Section

    private var alternativeURLsSection: some View {
        Section {
            ForEach(viewModel.alternativeURLs.indices, id: \.self) { index in
                HStack {
                    Text(viewModel.alternativeURLs[index])
                        .foregroundColor(.primary) // 入力済みは白（ライトモードでは黒）
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
                TextField("例: https://100.64.0.1:8443", text: $newAlternativeURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

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

            Toggle("自動フォールバック", isOn: $viewModel.autoFallback)
        } header: {
            Text("代替URL")
        } footer: {
            Text("メインURLに接続できない場合、代替URLを順番に試行します。Tailscale等の別ネットワーク用URLを追加できます。")
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        Section {
            SecureField("例: your-secret-api-key", text: $viewModel.apiKey)
                .textContentType(.password)
                .autocapitalization(.none)
                .autocorrectionDisabled()
        } header: {
            Text("認証")
        } footer: {
            Text("サーバーの.envファイルに設定されているAPI_KEYを入力してください。")
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
                    },
                    onBashPathChange: { newPath in
                        viewModel.updateAIProviderBashPath(config.provider, path: newPath)
                    }
                )
            }
            .onMove { source, destination in
                viewModel.moveAIProvider(from: source, to: destination)
            }
        } header: {
            HStack {
                Text("AI設定")
                Spacer()
                EditButton()
                    .font(.caption)
            }
        } footer: {
            Text("ドラッグで表示順を変更できます。チャット画面のタブ順序に反映されます。")
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
                    Text("接続テスト")
                }
            }
            .disabled(viewModel.serverURL.isEmpty || viewModel.connectionStatus == .connecting)
        } header: {
            Text("接続状態")
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
            return "未接続"
        case .connecting:
            return "接続中..."
        case .success:
            return "接続成功"
        case .failed(let error):
            return error.localizedDescription
        }
    }

    // MARK: - Certificate Section

    private var certificateSection: some View {
        Group {
            if let info = viewModel.certificateInfo {
                Section {
                    LabeledContent("フィンガープリント") {
                        Text(info.shortFingerprint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if let cn = info.commonName {
                        LabeledContent("コモンネーム", value: cn)
                    }

                    if let validUntil = info.validUntil {
                        LabeledContent("有効期限") {
                            Text(validUntil, style: .date)
                        }
                    }

                    if info.isSelfSigned {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.orange)
                            Text("自己署名証明書")
                                .foregroundColor(.orange)
                        }
                    }

                    // ペンディングリスタートの警告
                    if info.pendingRestart == true, let pending = info.pendingFingerprint {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading) {
                                Text("新しい証明書が生成されました")
                                    .font(.caption)
                                Text("サーバー再起動後に有効になります")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("証明書情報")
                }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section {
            Button("証明書信頼をリセット") {
                showResetConfirmation = true
            }
            .foregroundColor(.orange)

            Button("すべての設定をリセット") {
                showResetAllConfirmation = true
            }
            .foregroundColor(.red)
        } header: {
            Text("詳細設定")
        }
    }

    // MARK: - Certificate Alert

    private var certificateAlertButtons: some View {
        Group {
            Button("キャンセル", role: .cancel) {
                viewModel.rejectCertificate()
            }
            Button("信頼して接続") {
                viewModel.trustCertificate()
            }
        }
    }

    private var certificateAlertMessage: some View {
        VStack {
            if let info = viewModel.pendingCertificateInfo ?? viewModel.certificateInfo {
                Text("このサーバーは自己署名証明書を使用しています。\n\nフィンガープリント:\n\(info.fingerprint)\n\nサーバー側の表示と一致していますか？")
            } else {
                Text("サーバーの証明書を検証できません。")
            }
        }
    }

    // MARK: - Certificate Changed Alert

    private var certificateChangedAlertButtons: some View {
        Group {
            Button("接続を中止", role: .cancel) {
                viewModel.rejectCertificate()
            }
            Button("新しい証明書を信頼", role: .destructive) {
                viewModel.trustCertificate()
            }
        }
    }

    private var certificateChangedAlertMessage: some View {
        VStack {
            Text("サーバーの証明書が変更されました。\nこれは中間者攻撃の可能性があります。\n\nサーバー管理者に確認してください。")

            if let old = ServerConfigurationStore.shared.currentConfiguration?.certificateFingerprint,
               let new = viewModel.pendingCertificateInfo?.fingerprint {
                Text("\n旧: \(String(old.prefix(20)))...\n新: \(String(new.prefix(20)))...")
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
    let onBashPathChange: (String) -> Void

    @State private var bashPath: String = ""
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: config.provider.systemImage)
                    .foregroundColor(config.isEnabled ? .accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.provider.displayName)
                        .foregroundColor(config.isEnabled ? .primary : .secondary)

                    if config.provider == .gemini && config.isEnabled {
                        Text(config.bashPath ?? "パス未設定")
                            .font(.caption)
                            .foregroundColor(config.hasValidBashPath ? .secondary : .orange)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
            }

            // Gemini用のBashパス設定（展開時のみ）
            if config.provider == .gemini && config.isEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bashパス")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("例: /usr/local/bin/gemini", text: $bashPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: bashPath) { _, newValue in
                            onBashPathChange(newValue)
                        }
                }
                .padding(.leading, 32)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            bashPath = config.bashPath ?? ""
        }
        .animation(.easeInOut(duration: 0.2), value: config.isEnabled)
    }
}

// MARK: - Preview

#Preview {
    ServerSettingsView()
}
