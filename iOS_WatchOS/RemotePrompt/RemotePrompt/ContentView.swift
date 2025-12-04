import SwiftUI

struct ContentView: View {
    @StateObject private var configStore = ServerConfigurationStore.shared
    @State private var showingServerSettings = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if configStore.isLoaded {
                if Constants.isServerConfigured {
                    RoomsListView()
                } else {
                    // サーバー未設定時の初期設定画面
                    initialSetupView
                }
            } else {
                ProgressView(L10n.Common.loading)
            }
        }
        .task {
            print("[ContentView] .task START @ \(Date())")

            // 旧設定からの移行を試行
            if configStore.needsMigration {
                let legacyConfig = AppConfiguration()
                configStore.migrateIfNeeded(
                    from: legacyConfig.baseURL,
                    oldAPIKey: legacyConfig.apiKey
                )
            }

            // 接続のウォームアップ（TLSハンドシェイクを事前実行）
            // 非同期で実行されるため、ルーム読み込みをブロックしない
            if Constants.isServerConfigured {
                print("[ContentView] warmupConnection is disabled @ \(Date())")
                // APIClient.shared.warmupConnection()
            }

            print("[ContentView] .task END @ \(Date())")
        }
    }

    // MARK: - Initial Setup View

    private var initialSetupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: horizontalSizeClass == .regular ? 80 : 60))
                .foregroundColor(.blue)

            Text(L10n.Welcome.title)
                .font(horizontalSizeClass == .regular ? .largeTitle : .title)
                .fontWeight(.bold)

            Text(L10n.Welcome.hint)
                .font(horizontalSizeClass == .regular ? .title3 : .body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, horizontalSizeClass == .regular ? 64 : 32)

            Button {
                showingServerSettings = true
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text(L10n.Welcome.setup)
                }
                .font(.headline)
                .padding(.horizontal, horizontalSizeClass == .regular ? 48 : 32)
                .padding(.vertical, horizontalSizeClass == .regular ? 16 : 12)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 600 : .infinity)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingServerSettings) {
            NavigationStack {
                ServerSettingsView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    ContentView()
}
