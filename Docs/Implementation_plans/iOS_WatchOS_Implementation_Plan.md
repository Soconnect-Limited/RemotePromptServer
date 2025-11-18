# iOS/watchOS クライアント実装計画（RemotePrompt）

作成日: 2025-11-18
最終更新: 2025-11-18
バージョン: 1.2
対象: Phase 1 〜 Phase 5（iOS基本実装 → watchOS連携 → プッシュ通知 + SSE）

**変更履歴**:
- v1.0 (2025-11-18): 初版作成
- v1.1 (2025-11-18): Master Specification v2.0との整合性修正
  - 修正1: `deleteSession(runner:deviceId:)` に `deviceId` 引数追加（サーバー必須パラメータ対応）
  - 修正2: `navigationDestination(item:)` を `navigationDestination(isPresented:)` に変更（String非Identifiable対応）
  - 修正3: Watch プリセット action 名を `log_check` → `check_logs` に統一（Master Specification準拠）
- v1.2 (2025-11-18): SSEストリーミング実装追加
  - Phase 3にSSE関連セクション追加（3.8, 3.9, 3.10）
  - リアルタイムジョブ状態更新機能追加

---

## 実装フロー概要

```
Phase 1: データモデル + API Client基盤（2-3日）
  ↓
Phase 2: iOS 基本UI実装（3-4日）
  ↓
Phase 3: プッシュ通知実装（2-3日）
  ↓
Phase 4: Apple Watch 連携（2-3日）
  ↓
Phase 5: 統合テスト・UI/UX改善（2-3日）
```

---

## プロジェクト情報

**Xcodeプロジェクト名**: RemotePrompt
**プロジェクトパス**: `/Users/macstudio/Projects/RemotePrompt/iOS_WatchOS/RemotePrompt`
**サーバーURL**: `http://100.100.30.35:35000` (Tailscale VPN)
**対応プラットフォーム**: iOS 16.0+, watchOS 9.0+
**言語**: Swift 5.9+
**フレームワーク**: SwiftUI

---

## Phase 1: データモデル + API Client基盤（2-3日）

### 目標
サーバーAPIと通信するための基盤を構築し、データモデルとネットワークレイヤーを実装する

### 1.1 プロジェクト構造作成

**ディレクトリ構成**:
```
RemotePrompt/
├── RemotePrompt/
│   ├── App/
│   │   ├── RemotePromptApp.swift（既存）
│   │   └── AppDelegate.swift
│   ├── Models/
│   │   ├── Job.swift
│   │   ├── Device.swift
│   │   └── Session.swift
│   ├── Services/
│   │   ├── APIClient.swift
│   │   ├── APIEndpoints.swift
│   │   └── PushNotificationManager.swift
│   ├── Views/
│   │   ├── JobsListView.swift
│   │   ├── JobDetailView.swift
│   │   ├── NewJobView.swift
│   │   └── Components/
│   │       ├── JobRowView.swift
│   │       └── RunnerPicker.swift
│   ├── ViewModels/
│   │   ├── JobsViewModel.swift
│   │   └── JobDetailViewModel.swift
│   └── Utils/
│       ├── Constants.swift
│       └── Extensions.swift
├── RemotePromptTests/
└── RemotePromptUITests/
```

- [ ] Xcodeでグループ作成
  - [ ] App グループ
  - [ ] Models グループ
  - [ ] Services グループ
  - [ ] Views グループ
  - [ ] ViewModels グループ
  - [ ] Utils グループ

---

### 1.2 データモデル実装

**ファイル**: `Models/Job.swift`

- [ ] Job構造体定義
  - [ ] Identifiable適合
  - [ ] Codable適合
  - [ ] プロパティ定義
    - [ ] id: String
    - [ ] runner: String
    - [ ] inputText: String
    - [ ] deviceId: String
    - [ ] status: String
    - [ ] exitCode: Int?
    - [ ] stdout: String?
    - [ ] stderr: String?
    - [ ] createdAt: Date?
    - [ ] startedAt: Date?
    - [ ] finishedAt: Date?
  - [ ] CodingKeys定義（snake_case → camelCase変換）
    ```swift
    enum CodingKeys: String, CodingKey {
        case id, runner, status, stdout, stderr
        case inputText = "input_text"
        case deviceId = "device_id"
        case exitCode = "exit_code"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
    ```
  - [ ] 計算プロパティ追加
    - [ ] statusColor: Color
    - [ ] runnerColor: Color
    - [ ] isCompleted: Bool
    - [ ] isRunning: Bool

- [ ] CreateJobRequest構造体定義
  ```swift
  struct CreateJobRequest: Codable {
      let runner: String
      let inputText: String
      let deviceId: String

      enum CodingKeys: String, CodingKey {
          case runner
          case inputText = "input_text"
          case deviceId = "device_id"
      }
  }
  ```

- [ ] CreateJobResponse構造体定義
  ```swift
  struct CreateJobResponse: Codable {
      let id: String
      let status: String
  }
  ```

**ファイル**: `Models/Device.swift`

- [ ] Device構造体定義
  - [ ] Codable適合
  - [ ] プロパティ定義
    - [ ] deviceId: String
    - [ ] deviceToken: String
  - [ ] CodingKeys定義
    ```swift
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceToken = "device_token"
    }
    ```

**ファイル**: `Models/Session.swift`

- [ ] SessionStatus構造体定義
  ```swift
  struct SessionStatus: Codable {
      let exists: Bool
      let sessionId: String?

      enum CodingKeys: String, CodingKey {
          case exists
          case sessionId = "session_id"
      }
  }

  struct SessionsResponse: Codable {
      let claude: SessionStatus
      let codex: SessionStatus
  }
  ```

---

### 1.3 定数管理

**ファイル**: `Utils/Constants.swift`

- [ ] Constants定義
  ```swift
  enum Constants {
      static let baseURL = "http://100.100.30.35:35000"
      static let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "iphone-unknown"

      enum Runners {
          static let claude = "claude"
          static let codex = "codex"
          static let all = [claude, codex]
      }

      enum JobStatus {
          static let queued = "queued"
          static let running = "running"
          static let success = "success"
          static let failed = "failed"
      }
  }
  ```

---

### 1.4 API Endpoints定義

**ファイル**: `Services/APIEndpoints.swift`

- [ ] APIEndpoint列挙型定義
  ```swift
  enum APIEndpoint {
      case health
      case registerDevice
      case createJob
      case listJobs(limit: Int?, status: String?)
      case getJob(id: String)
      case getSessions(deviceId: String)
      case deleteSession(runner: String, deviceId: String)

      var path: String {
          // パス文字列を返却
      }

      var method: String {
          // HTTPメソッドを返却
      }
  }
  ```

---

### 1.5 API Client実装

**ファイル**: `Services/APIClient.swift`

- [ ] APIClientクラス定義
  ```swift
  @MainActor
  class APIClient: ObservableObject {
      static let shared = APIClient()
      private let baseURL: String
      private let deviceId: String
      private let apiKey: String

      private init() {
          self.baseURL = Constants.baseURL
          self.deviceId = Constants.deviceId
          self.apiKey = "YOUR_API_KEY"  // TODO: 環境変数 or Keychain
      }
  }
  ```

- [ ] 基本ネットワークメソッド実装
  - [ ] `request<T: Decodable>(_ endpoint: APIEndpoint, body: Encodable?) async throws -> T`
    - [ ] URL生成
    - [ ] URLRequest生成
    - [ ] HTTPヘッダー設定
      - [ ] `Content-Type: application/json`
      - [ ] `x-api-key: <apiKey>` （サーバー認証用）
    - [ ] HTTPメソッド設定
    - [ ] ボディ設定（POST/PUT/DELETE）
    - [ ] URLSession.data(for:)実行
    - [ ] HTTPステータスコードチェック
    - [ ] JSONDecoder.decode()
    - [ ] エラーハンドリング

- [ ] エンドポイント別メソッド実装
  - [ ] `healthCheck() async throws -> HealthResponse`
  - [ ] `registerDevice(deviceToken: String) async throws`
  - [ ] `createJob(runner: String, inputText: String) async throws -> CreateJobResponse`
  - [ ] `fetchJobs(limit: Int?, status: String?) async throws -> [Job]`
  - [ ] `fetchJob(id: String) async throws -> Job`
  - [ ] `fetchSessions() async throws -> SessionsResponse`
  - [ ] `deleteSession(runner: String, deviceId: String) async throws`
    - [ ] ⚠️ **重要**: `device_id` はサーバー側必須クエリパラメータ（Master Specification line 1120-1125）

- [ ] エラー型定義
  ```swift
  enum APIError: Error, LocalizedError {
      case invalidURL
      case requestFailed(statusCode: Int)
      case decodingFailed(Error)
      case serverError(String)

      var errorDescription: String? {
          // エラーメッセージ返却
      }
  }
  ```

---

### 1.6 Info.plist設定

**ファイル**: `RemotePrompt/Info.plist`

- [ ] ATS（App Transport Security）設定追加
  ```xml
  <key>NSAppTransportSecurity</key>
  <dict>
      <key>NSAllowsArbitraryLoads</key>
      <false/>
      <key>NSExceptionDomains</key>
      <dict>
          <key>100.100.30.35</key>
          <dict>
              <key>NSExceptionAllowsInsecureHTTPLoads</key>
              <true/>
              <key>NSIncludesSubdomains</key>
              <true/>
          </dict>
      </dict>
  </dict>
  ```

---

### 1.7 APIテスト実装

**ファイル**: `RemotePromptTests/APIClientTests.swift`

- [ ] テストクラス作成
  ```swift
  import XCTest
  @testable import RemotePrompt

  final class APIClientTests: XCTestCase {
      var apiClient: APIClient!

      override func setUp() {
          super.setUp()
          apiClient = APIClient.shared
      }
  }
  ```

- [ ] テストケース実装
  - [ ] `testHealthCheck()`
    - [ ] ヘルスチェックAPI呼び出し
    - [ ] レスポンス検証
  - [ ] `testFetchJobs()`
    - [ ] ジョブ一覧取得
    - [ ] デコード成功確認
  - [ ] `testCreateJob()`
    - [ ] ジョブ作成
    - [ ] レスポンス検証
  - [ ] `testFetchSessions()`
    - [ ] セッション取得
    - [ ] デコード成功確認

---

### Phase 1 完了条件

- [ ] 全データモデル実装完了
- [ ] APIClient実装完了
- [ ] Info.plist ATS設定完了
- [ ] ユニットテストすべて成功
- [ ] サーバーとの疎通確認（ヘルスチェック成功）

---

## Phase 2: iOS 基本UI実装（3-4日）

### 目標
SwiftUIでジョブ一覧・詳細・新規作成画面を実装し、基本的なジョブ管理機能を提供する

### 2.1 ViewModel実装

**ファイル**: `ViewModels/JobsViewModel.swift`

- [ ] JobsViewModelクラス定義
  ```swift
  @MainActor
  class JobsViewModel: ObservableObject {
      @Published var jobs: [Job] = []
      @Published var isLoading = false
      @Published var errorMessage: String?

      private let apiClient = APIClient.shared
  }
  ```

- [ ] メソッド実装
  - [ ] `loadJobs() async`
    - [ ] isLoading = true設定
    - [ ] APIClient.fetchJobs()呼び出し
    - [ ] jobs更新
    - [ ] エラーハンドリング
    - [ ] isLoading = false設定
  - [ ] `refresh() async`
    - [ ] loadJobs()呼び出し
  - [ ] `createJob(runner: String, inputText: String) async throws`
    - [ ] APIClient.createJob()呼び出し
    - [ ] loadJobs()で再取得

**ファイル**: `ViewModels/JobDetailViewModel.swift`

- [ ] JobDetailViewModelクラス定義
  ```swift
  @MainActor
  class JobDetailViewModel: ObservableObject {
      @Published var job: Job?
      @Published var isLoading = false
      @Published var errorMessage: String?

      private let apiClient = APIClient.shared
      private let jobId: String

      init(jobId: String) {
          self.jobId = jobId
      }
  }
  ```

- [ ] メソッド実装
  - [ ] `loadJob() async`
    - [ ] APIClient.fetchJob(id:)呼び出し
    - [ ] job更新
  - [ ] `refresh() async`
    - [ ] loadJob()呼び出し
  - [ ] `startPolling()`（実行中ジョブの定期更新）
    - [ ] Timer設定（5秒間隔）
    - [ ] loadJob()定期呼び出し
    - [ ] 完了時にポーリング停止

---

### 2.2 ジョブ一覧画面実装

**ファイル**: `Views/JobsListView.swift`

- [ ] JobsListView定義
  ```swift
  struct JobsListView: View {
      @StateObject private var viewModel = JobsViewModel()
      @State private var showingNewJobSheet = false

      var body: some View {
          // UI実装
      }
  }
  ```

- [ ] UI要素実装
  - [ ] NavigationStack
  - [ ] List(viewModel.jobs)
    - [ ] ForEachでJobRowView表示
    - [ ] NavigationLinkでJobDetailViewへ遷移
  - [ ] toolbar
    - [ ] 右上に"+"ボタン（新規ジョブ）
    - [ ] タップでshowingNewJobSheet = true
  - [ ] .refreshable修飾子
    - [ ] await viewModel.refresh()
  - [ ] .task修飾子
    - [ ] await viewModel.loadJobs()
  - [ ] .sheet修飾子
    - [ ] NewJobView表示
  - [ ] エラー表示
    - [ ] viewModel.errorMessageがnilでない場合にアラート表示

**ファイル**: `Views/Components/JobRowView.swift`

- [ ] JobRowView定義
  ```swift
  struct JobRowView: View {
      let job: Job

      var body: some View {
          // UI実装
      }
  }
  ```

- [ ] UI要素実装
  - [ ] VStack(alignment: .leading)
    - [ ] HStack
      - [ ] runnerバッジ（Text + background + cornerRadius）
      - [ ] statusバッジ（Text + foregroundColor）
      - [ ] Spacer()
      - [ ] 相対時刻表示（job.createdAt）
    - [ ] inputTextプレビュー（2行制限）
  - [ ] 計算プロパティ
    - [ ] runnerColor: Color
      - [ ] claude: .blue
      - [ ] codex: .green
    - [ ] statusColor: Color
      - [ ] success: .green
      - [ ] failed: .red
      - [ ] running: .orange
      - [ ] queued: .gray

---

### 2.3 ジョブ詳細画面実装

**ファイル**: `Views/JobDetailView.swift`

- [ ] JobDetailView定義
  ```swift
  struct JobDetailView: View {
      let jobId: String
      @StateObject private var viewModel: JobDetailViewModel

      init(jobId: String) {
          self.jobId = jobId
          _viewModel = StateObject(wrappedValue: JobDetailViewModel(jobId: jobId))
      }

      var body: some View {
          // UI実装
      }
  }
  ```

- [ ] UI要素実装
  - [ ] ScrollView
    - [ ] VStack(alignment: .leading, spacing: 16)
      - [ ] セクション: 基本情報
        - [ ] runner表示
        - [ ] status表示
        - [ ] created_at表示
        - [ ] started_at表示（オプショナル）
        - [ ] finished_at表示（オプショナル）
      - [ ] セクション: 入力
        - [ ] inputText表示（Text + background）
      - [ ] セクション: 出力（statusがsuccessの場合）
        - [ ] stdout表示（Text + background + ScrollView）
        - [ ] コピーボタン
      - [ ] セクション: エラー（statusがfailedの場合）
        - [ ] stderr表示（Text + background + foregroundColor: .red）
  - [ ] .navigationTitle("ジョブ詳細")
  - [ ] .toolbar
    - [ ] 右上に更新ボタン
    - [ ] タップでviewModel.refresh()
  - [ ] .task修飾子
    - [ ] await viewModel.loadJob()
    - [ ] statusがrunningの場合はポーリング開始
  - [ ] .onDisappear修飾子
    - [ ] ポーリング停止

---

### 2.4 新規ジョブ作成画面実装

**ファイル**: `Views/NewJobView.swift`

- [ ] NewJobView定義
  ```swift
  struct NewJobView: View {
      @Environment(\.dismiss) var dismiss
      @EnvironmentObject var jobsViewModel: JobsViewModel

      @State private var inputText = ""
      @State private var selectedRunner = Constants.Runners.claude
      @State private var isSubmitting = false
      @State private var errorMessage: String?

      var body: some View {
          // UI実装
      }
  }
  ```

- [ ] UI要素実装
  - [ ] NavigationStack
    - [ ] Form
      - [ ] Section(header: "Runner")
        - [ ] Picker("CLI Tool", selection: $selectedRunner)
          - [ ] ForEach(Constants.Runners.all)
          - [ ] .pickerStyle(.segmented)
      - [ ] Section(header: "Input")
        - [ ] TextEditor(text: $inputText)
          - [ ] .frame(minHeight: 200)
      - [ ] Section
        - [ ] Button("実行")
          - [ ] action: submitJob()
          - [ ] disabled: inputText.isEmpty || isSubmitting
          - [ ] ProgressView表示（isSubmitting時）
    - [ ] .navigationTitle("新規ジョブ")
    - [ ] .navigationBarTitleDisplayMode(.inline)
    - [ ] .toolbar
      - [ ] 右上に"閉じる"ボタン
      - [ ] タップでdismiss()
    - [ ] .alert(エラー表示用)

- [ ] メソッド実装
  - [ ] `submitJob()`
    ```swift
    func submitJob() {
        Task {
            isSubmitting = true
            defer { isSubmitting = false }

            do {
                try await jobsViewModel.createJob(
                    runner: selectedRunner,
                    inputText: inputText
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    ```

---

### 2.5 アプリエントリポイント更新

**ファイル**: `App/RemotePromptApp.swift`

- [ ] RemotePromptApp更新
  ```swift
  @main
  struct RemotePromptApp: App {
      var body: some Scene {
          WindowGroup {
              JobsListView()
          }
      }
  }
  ```

---

### 2.6 UI動作確認

- [ ] シミュレータ起動テスト
  - [ ] iPhone 15 Pro シミュレータ
  - [ ] iOS 17.0+
- [ ] ジョブ一覧画面表示確認
  - [ ] ナビゲーションタイトル表示
  - [ ] ツールバーボタン表示
  - [ ] 空リストメッセージ表示（初回）
- [ ] 新規ジョブ作成テスト
  - [ ] モーダル表示確認
  - [ ] Runner選択確認
  - [ ] TextEditor入力確認
  - [ ] 実行ボタン動作確認
  - [ ] サーバーへのPOST成功確認
- [ ] ジョブ一覧更新確認
  - [ ] 作成したジョブが一覧に表示
  - [ ] Pull-to-Refresh動作確認
- [ ] ジョブ詳細画面遷移確認
  - [ ] タップで詳細画面表示
  - [ ] 基本情報表示確認
  - [ ] 出力表示確認（完了ジョブ）

---

### Phase 2 完了条件

- [ ] 全ViewModel実装完了
- [ ] 全View実装完了
- [ ] シミュレータでUI動作確認
- [ ] サーバーとの連携確認（ジョブCRUD成功）
- [ ] エラーハンドリング動作確認

---

## Phase 3: プッシュ通知実装（2-3日）

### 目標
APNsプッシュ通知を実装し、ジョブ完了時にiPhoneへ通知を送信する

### 3.1 APNs設定（Apple Developer Portal）

- [ ] App ID設定
  - [ ] Capabilities: Push Notificationsを有効化
  - [ ] Bundle ID確認: `com.example.remoteprompt`（適宜変更）
- [ ] APNs認証キー作成
  - [ ] .p8ファイルダウンロード
  - [ ] Key IDメモ
  - [ ] Team IDメモ
- [ ] Provisioning Profile作成
  - [ ] Development / Distribution
  - [ ] Push Notifications含む

---

### 3.2 Xcodeプロジェクト設定

- [ ] Signing & Capabilities設定
  - [ ] Team選択
  - [ ] Bundle Identifier設定
  - [ ] Capabilityタブで"Push Notifications"追加
  - [ ] Background Modes追加
    - [ ] "Remote notifications"チェック

---

### 3.3 AppDelegate実装

**ファイル**: `App/AppDelegate.swift`

- [ ] AppDelegateクラス定義
  ```swift
  import UIKit
  import UserNotifications

  class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
      func application(_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
          UNUserNotificationCenter.current().delegate = self
          registerForPushNotifications()
          return true
      }
  }
  ```

- [ ] プッシュ通知登録メソッド実装
  ```swift
  func registerForPushNotifications() {
      UNUserNotificationCenter.current()
          .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
              guard granted else { return }
              DispatchQueue.main.async {
                  UIApplication.shared.registerForRemoteNotifications()
              }
          }
  }
  ```

- [ ] デバイストークン取得メソッド実装
  ```swift
  func application(_ application: UIApplication,
                  didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
      let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
      print("Device Token: \(tokenString)")

      Task {
          do {
              try await APIClient.shared.registerDevice(deviceToken: tokenString)
              print("Device registered successfully")
          } catch {
              print("Failed to register device: \(error)")
          }
      }
  }

  func application(_ application: UIApplication,
                  didFailToRegisterForRemoteNotificationsWithError error: Error) {
      print("Failed to register for remote notifications: \(error)")
  }
  ```

- [ ] 通知受信ハンドラ実装
  ```swift
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
      let userInfo = response.notification.request.content.userInfo

      if let jobId = userInfo["job_id"] as? String {
          print("Notification tapped for job: \(jobId)")
          // JobDetailViewへ遷移するための通知を送信
          NotificationCenter.default.post(
              name: .openJobDetail,
              object: nil,
              userInfo: ["jobId": jobId]
          )
      }

      completionHandler()
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                            willPresent notification: UNNotification,
                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
      // アプリがフォアグラウンドでも通知を表示
      completionHandler([.banner, .sound, .badge])
  }
  ```

- [ ] Notification.Name拡張定義
  ```swift
  extension Notification.Name {
      static let openJobDetail = Notification.Name("openJobDetail")
  }
  ```

---

### 3.4 RemotePromptApp更新

**ファイル**: `App/RemotePromptApp.swift`

- [ ] AppDelegate統合
  ```swift
  @main
  struct RemotePromptApp: App {
      @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

      var body: some Scene {
          WindowGroup {
              JobsListView()
          }
      }
  }
  ```

---

### 3.5 通知タップ時の画面遷移実装

**ファイル**: `Views/JobsListView.swift`（更新）

- [ ] JobsListView更新
  ```swift
  struct JobsListView: View {
      @StateObject private var viewModel = JobsViewModel()
      @State private var showingNewJobSheet = false
      @State private var selectedJobId: String?
      @State private var showJobDetail = false

      var body: some View {
          NavigationStack {
              // 既存のUI...

              .navigationDestination(isPresented: $showJobDetail) {
                  if let jobId = selectedJobId {
                      JobDetailView(jobId: jobId)
                  }
              }
              .onReceive(NotificationCenter.default.publisher(for: .openJobDetail)) { notification in
                  if let jobId = notification.userInfo?["jobId"] as? String {
                      selectedJobId = jobId
                      showJobDetail = true
                  }
              }
          }
      }
  }
  ```
  - [ ] ⚠️ **修正理由**: `navigationDestination(item:)` は `Identifiable` な型が必要。`String?` は非準拠のため `isPresented:` オーバーロードに変更

---

### 3.6 サーバー側APNs設定（確認のみ）

- [ ] サーバー側.env確認
  ```bash
  APNS_KEY_PATH=/path/to/AuthKey_XXXXXXXX.p8
  APNS_KEY_ID=XXXXXXXXXX
  APNS_TEAM_ID=YYYYYYYYYY
  APNS_BUNDLE_ID=com.example.remoteprompt
  APNS_USE_SANDBOX=true  # 開発環境
  ```

- [ ] notify.py実装確認（サーバー側で実装済みを想定）

---

### 3.7 プッシュ通知テスト

- [ ] 実機テスト準備
  - [ ] 実機デバイス接続
  - [ ] Development Provisioning Profileインストール
  - [ ] アプリビルド・インストール
- [ ] デバイストークン登録確認
  - [ ] アプリ起動
  - [ ] 通知許可ダイアログで"許可"タップ
  - [ ] Xcodeコンソールでデバイストークン出力確認
  - [ ] サーバーログで/register_device呼び出し確認
- [ ] プッシュ通知受信テスト
  - [ ] 新規ジョブ作成
  - [ ] ジョブ完了待機（サーバー側でAPNs送信）
  - [ ] 通知バナー表示確認
  - [ ] 通知タップ→ジョブ詳細画面遷移確認
- [ ] フォアグラウンド通知テスト
  - [ ] アプリ起動中にジョブ完了
  - [ ] バナー表示確認

---

### 3.8 SSE（Server-Sent Events）Manager実装

**ファイル**: `Services/SSEManager.swift`

- [ ] SSEManagerクラス定義
  ```swift
  import Foundation
  import Combine

  class SSEManager: NSObject, ObservableObject, URLSessionDataDelegate {
      @Published var jobStatus: String = "queued"
      @Published var isConnected = false
      @Published var errorMessage: String?

      private var urlSession: URLSession?
      private var dataTask: URLSessionDataTask?
      private var buffer = Data()
      private var jobId: String?

      override init() {
          super.init()
          let config = URLSessionConfiguration.default
          config.timeoutIntervalForRequest = 300  // 5分タイムアウト
          config.httpAdditionalHeaders = ["Accept": "text/event-stream"]
          urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
      }
  }
  ```

- [ ] SSE接続メソッド実装
  ```swift
  extension SSEManager {
      func connect(jobId: String) {
          self.jobId = jobId
          disconnect()  // 既存接続をクローズ

          guard let url = URL(string: "\(Constants.baseURL)/jobs/\(jobId)/stream") else {
              errorMessage = "Invalid URL"
              return
          }

          var request = URLRequest(url: url)
          request.httpMethod = "GET"
          request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
          request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")

          dataTask = urlSession?.dataTask(with: request)
          dataTask?.resume()
          isConnected = true
      }

      func disconnect() {
          dataTask?.cancel()
          dataTask = nil
          buffer.removeAll()
          isConnected = false
      }
  }
  ```

- [ ] URLSessionDataDelegate実装
  ```swift
  extension SSEManager {
      func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
          buffer.append(data)

          // SSEメッセージをパース（"data: {...}\n\n" 形式）
          guard let message = String(data: buffer, encoding: .utf8) else { return }

          let lines = message.components(separatedBy: "\n\n")
          for i in 0..<(lines.count - 1) {  // 最後の不完全な行は次回処理
              let line = lines[i]
              if line.hasPrefix("data: ") {
                  let jsonString = String(line.dropFirst(6))  // "data: " を削除
                  if let jsonData = jsonString.data(using: .utf8),
                     let event = try? JSONDecoder().decode(JobStatusEvent.self, from: jsonData) {
                      DispatchQueue.main.async {
                          self.jobStatus = event.status
                      }
                  }
              }
          }

          // 最後の不完全な行をバッファに保持
          if let lastLine = lines.last, !lastLine.isEmpty {
              buffer = lastLine.data(using: .utf8) ?? Data()
          } else {
              buffer.removeAll()
          }
      }

      func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
          DispatchQueue.main.async {
              self.isConnected = false
              if let error = error {
                  self.errorMessage = error.localizedDescription
              }
          }
      }
  }
  ```

- [ ] JobStatusEvent構造体定義
  ```swift
  struct JobStatusEvent: Codable {
      let status: String
      let timestamp: String?
  }
  ```

---

### 3.9 JobDetailViewModel SSE対応

**ファイル**: `ViewModels/JobDetailViewModel.swift`（更新）

- [ ] SSEManager統合
  ```swift
  @MainActor
  class JobDetailViewModel: ObservableObject {
      @Published var job: Job?
      @Published var isLoading = false
      @Published var errorMessage: String?
      @Published var isSSEConnected = false  // ✅ ビュー公開用プロパティ

      private let apiClient = APIClient.shared
      private let sseManager = SSEManager()
      private let jobId: String
      private var pollingTimer: Timer?
      private var cancellables = Set<AnyCancellable>()  // ✅ Combine購読保持用

      init(jobId: String) {
          self.jobId = jobId
      }
  }
  ```

- [ ] SSE接続ロジック実装
  ```swift
  extension JobDetailViewModel {
      func loadJob() async {
          isLoading = true
          defer { isLoading = false }

          do {
              let fetchedJob = try await apiClient.fetchJob(id: jobId)
              job = fetchedJob

              // ✅ SSE接続開始（実行中ジョブのみ）
              if fetchedJob.isRunning {
                  startSSEStreaming()
              }
          } catch {
              errorMessage = error.localizedDescription
          }
      }

      private func startSSEStreaming() {
          sseManager.connect(jobId: jobId)

          // ✅ SSE接続状態を監視
          sseManager.$isConnected
              .assign(to: \.isSSEConnected, on: self)
              .store(in: &cancellables)

          // ✅ SSE status変更を監視（AnyCancellableを保持）
          sseManager.$jobStatus
              .sink { [weak self] newStatus in
                  guard let self = self else { return }
                  self.job?.status = newStatus

                  // 完了したらSSE切断
                  if newStatus == "success" || newStatus == "failed" {
                      self.stopSSEStreaming()
                      Task {
                          await self.loadJob()  // 最終結果を取得
                      }
                  }
              }
              .store(in: &cancellables)  // ✅ メモリリーク防止
      }

      func stopSSEStreaming() {  // ✅ public: ビューから呼び出すため
          sseManager.disconnect()
          cancellables.removeAll()  // ✅ 購読解除
      }

      // ✅ フォールバック: SSE失敗時はポーリング
      func startPollingFallback() {
          pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
              guard let self = self else { return }
              Task {
                  await self.loadJob()
              }
          }
      }

      func stopPolling() {
          pollingTimer?.invalidate()
          pollingTimer = nil
      }
  }
  ```

---

### 3.10 JobDetailView SSE対応

**ファイル**: `Views/JobDetailView.swift`（更新）

- [ ] UI要素更新
  ```swift
  struct JobDetailView: View {
      let jobId: String
      @StateObject private var viewModel: JobDetailViewModel

      init(jobId: String) {
          self.jobId = jobId
          _viewModel = StateObject(wrappedValue: JobDetailViewModel(jobId: jobId))
      }

      var body: some View {
          ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                  // ✅ SSE接続状態表示（isSSEConnected公開プロパティ使用）
                  if viewModel.isSSEConnected {
                      HStack {
                          Circle()
                              .fill(Color.green)
                              .frame(width: 8, height: 8)
                          Text("リアルタイム更新中")
                              .font(.caption)
                              .foregroundColor(.secondary)
                      }
                  }

                  // 既存のUI...
              }
          }
          .task {
              await viewModel.loadJob()

              // ✅ SSE失敗時のフォールバック（isSSEConnected使用）
              DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                  if !viewModel.isSSEConnected && viewModel.job?.isRunning == true {
                      viewModel.startPollingFallback()
                  }
              }
          }
          .onDisappear {
              viewModel.stopSSEStreaming()
              viewModel.stopPolling()
          }
      }
  }
  ```

---

### Phase 3 完了条件

- [ ] APNs設定完了（Apple Developer Portal）
- [ ] AppDelegate実装完了
- [ ] 実機でデバイストークン取得成功
- [ ] サーバーへのデバイス登録成功
- [ ] プッシュ通知受信成功
- [ ] 通知タップ時の画面遷移成功
- [ ] SSEManager実装完了（3.8）
- [ ] JobDetailViewModel SSE対応完了（3.9）
- [ ] JobDetailView リアルタイム更新確認（3.10）
- [ ] SSE接続失敗時のポーリングフォールバック動作確認

---

## Phase 4: Apple Watch 連携（2-3日）

### 目標
Apple Watchからプリセットボタンでジョブを実行できるようにする

### 4.1 watchOSターゲット追加

- [ ] Xcodeでwatchアプリターゲット作成
  - [ ] File > New > Target
  - [ ] "Watch App" 選択
  - [ ] Product Name: "RemotePrompt Watch"
  - [ ] Organization Identifier設定
  - [ ] Language: Swift
  - [ ] User Interface: SwiftUI
- [ ] Bundle Identifier確認
  - [ ] `com.example.remoteprompt.watchkitapp`

---

### 4.2 Watch Connectivity設定（iPhone側）

**ファイル**: `Services/WatchConnectivityManager.swift`

- [ ] WatchConnectivityManagerクラス定義
  ```swift
  import WatchConnectivity

  class WatchConnectivityManager: NSObject, ObservableObject {
      static let shared = WatchConnectivityManager()
      var session: WCSession?

      override private init() {
          super.init()
          if WCSession.isSupported() {
              session = WCSession.default
              session?.delegate = self
              session?.activate()
          }
      }
  }
  ```

- [ ] WCSessionDelegate実装
  ```swift
  extension WatchConnectivityManager: WCSessionDelegate {
      func session(_ session: WCSession,
                  activationDidCompleteWith activationState: WCSessionActivationState,
                  error: Error?) {
          print("WCSession activated: \(activationState.rawValue)")
      }

      func sessionDidBecomeInactive(_ session: WCSession) {
          print("WCSession inactive")
      }

      func sessionDidDeactivate(_ session: WCSession) {
          print("WCSession deactivated")
          session.activate()
      }
  }
  ```

- [ ] メッセージ受信ハンドラ実装
  ```swift
  extension WatchConnectivityManager {
      func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
          guard message["type"] as? String == "preset" else { return }

          let action = message["action"] as? String ?? ""
          let runner = message["runner"] as? String ?? Constants.Runners.claude

          let inputText = presetTextForAction(action)

          Task {
              do {
                  _ = try await APIClient.shared.createJob(
                      runner: runner,
                      inputText: inputText
                  )
                  print("Job created from Watch: \(action)")
              } catch {
                  print("Failed to create job from Watch: \(error)")
              }
          }
      }

      private func presetTextForAction(_ action: String) -> String {
          switch action {
          case "daily_batch":
              return "今日のバッチ処理を開始してください"
          case "status_check":
              return "現在のシステムステータスを確認してください"
          case "check_logs":
              return "最新のログを確認してください"
          default:
              return action
          }
      }
  }
  ```

---

### 4.3 RemotePromptApp更新（iPhone側）

**ファイル**: `App/RemotePromptApp.swift`

- [ ] WatchConnectivityManager初期化
  ```swift
  @main
  struct RemotePromptApp: App {
      @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

      init() {
          // Watch Connectivity初期化
          _ = WatchConnectivityManager.shared
      }

      var body: some Scene {
          WindowGroup {
              JobsListView()
          }
      }
  }
  ```

---

### 4.4 Watch Connectivity設定（Watch側）

**ファイル**: `RemotePrompt Watch/Services/WatchViewModel.swift`

- [ ] WatchViewModelクラス定義
  ```swift
  import WatchKit
  import WatchConnectivity

  class WatchViewModel: NSObject, ObservableObject {
      var session: WCSession?
      @Published var lastError: String?

      override init() {
          super.init()
          if WCSession.isSupported() {
              session = WCSession.default
              session?.delegate = self
              session?.activate()
          }
      }
  }
  ```

- [ ] WCSessionDelegate実装
  ```swift
  extension WatchViewModel: WCSessionDelegate {
      func session(_ session: WCSession,
                  activationDidCompleteWith activationState: WCSessionActivationState,
                  error: Error?) {
          print("Watch WCSession activated: \(activationState.rawValue)")
      }
  }
  ```

- [ ] プリセット送信メソッド実装
  ```swift
  extension WatchViewModel {
      func sendPreset(action: String, runner: String) {
          guard let session = session, session.isReachable else {
              lastError = "iPhone not reachable"
              return
          }

          let message: [String: Any] = [
              "type": "preset",
              "action": action,
              "runner": runner
          ]

          session.sendMessage(message, replyHandler: nil) { error in
              DispatchQueue.main.async {
                  self.lastError = error.localizedDescription
              }
          }
      }
  }
  ```

---

### 4.5 Watch画面実装

**ファイル**: `RemotePrompt Watch/Views/PresetButtonsView.swift`

- [ ] PresetButtonsView定義
  ```swift
  import SwiftUI

  struct PresetButtonsView: View {
      @StateObject private var viewModel = WatchViewModel()

      let presets: [(title: String, action: String, runner: String)] = [
          ("今日のバッチ", "daily_batch", "claude"),
          ("ステータス確認", "status_check", "codex"),
          ("ログ確認", "check_logs", "claude")
      ]

      var body: some View {
          // UI実装
      }
  }
  ```

- [ ] UI要素実装
  - [ ] NavigationStack
    - [ ] List(presets, id: \.action)
      - [ ] Button(action: sendPreset)
        - [ ] VStack(alignment: .leading)
          - [ ] Text(preset.title)
            - [ ] .font(.headline)
          - [ ] Text(preset.runner)
            - [ ] .font(.caption)
            - [ ] .foregroundColor(.secondary)
    - [ ] .navigationTitle("プリセット")
    - [ ] .alert(エラー表示用)

- [ ] メソッド実装
  ```swift
  private func sendPreset(_ preset: (title: String, action: String, runner: String)) {
      viewModel.sendPreset(action: preset.action, runner: preset.runner)
      WKInterfaceDevice.current().play(.success)  // ハプティックフィードバック
  }
  ```

---

### 4.6 Watch App エントリポイント

**ファイル**: `RemotePrompt Watch/RemotePromptWatchApp.swift`

- [ ] RemotePromptWatchApp定義
  ```swift
  import SwiftUI

  @main
  struct RemotePromptWatchApp: App {
      var body: some Scene {
          WindowGroup {
              PresetButtonsView()
          }
      }
  }
  ```

---

### 4.7 Watch連携テスト

- [ ] シミュレータテスト
  - [ ] iPhone + Apple Watchペアシミュレータ起動
  - [ ] 両方のアプリ起動
  - [ ] WCSession接続確認
- [ ] メッセージ送信テスト
  - [ ] Watchでプリセットボタンタップ
  - [ ] iPhone側でメッセージ受信確認
  - [ ] サーバーへのジョブ投稿確認
- [ ] 実機テスト
  - [ ] 実機iPhone + 実機Apple Watchでテスト
  - [ ] プリセット実行成功確認
  - [ ] プッシュ通知受信確認（Watchでも）

---

### Phase 4 完了条件

- [ ] watchOSターゲット作成完了
- [ ] WatchConnectivity実装完了（iPhone/Watch両方）
- [ ] Watch画面実装完了
- [ ] シミュレータで連携確認
- [ ] 実機でプリセット実行成功
- [ ] Watch→iPhone→サーバーの全経路動作確認

---

## Phase 5: 統合テスト・UI/UX改善（2-3日）

### 目標
全機能の統合テストを実施し、UI/UXを最適化する

### 5.1 統合テストシナリオ

- [ ] エンドツーエンドテスト
  - [ ] シナリオ1: iPhone新規ジョブ作成→完了通知受信
    - [ ] 新規ジョブ作成
    - [ ] ジョブ詳細画面でポーリング確認
    - [ ] 完了時にプッシュ通知受信
    - [ ] 通知タップで詳細画面表示
  - [ ] シナリオ2: Watch プリセット実行→iPhone通知受信
    - [ ] Watchプリセットボタンタップ
    - [ ] iPhoneでジョブ作成確認
    - [ ] 完了時にiPhone/Watch両方で通知受信
  - [ ] シナリオ3: セッション継続確認
    - [ ] 同じrunnerで連続ジョブ実行
    - [ ] サーバー側でセッションID同一確認
    - [ ] 会話履歴継続確認（実際の応答内容で検証）

---

### 5.2 エラーケーステスト

- [ ] ネットワークエラー
  - [ ] サーバー停止状態でジョブ作成
  - [ ] エラーメッセージ表示確認
- [ ] タイムアウトエラー
  - [ ] 長時間実行ジョブ（5分超）
  - [ ] タイムアウト処理確認
- [ ] Watch非接続時
  - [ ] iPhone単独でWatch機能無効確認
  - [ ] クラッシュしないことを確認

---

### 5.3 UI/UX改善

**ジョブ一覧画面**:
- [ ] 空リスト時のメッセージ追加
  ```swift
  if viewModel.jobs.isEmpty && !viewModel.isLoading {
      ContentUnavailableView(
          "ジョブがありません",
          systemImage: "tray",
          description: Text("右上の+ボタンから新規ジョブを作成できます")
      )
  }
  ```
- [ ] Pull-to-Refresh実装（既存）
- [ ] ローディングインジケーター追加
  ```swift
  if viewModel.isLoading {
      ProgressView()
  }
  ```

**ジョブ詳細画面**:
- [ ] 出力コピー機能追加
  ```swift
  Button(action: {
      UIPasteboard.general.string = job.stdout
  }) {
      Label("コピー", systemImage: "doc.on.doc")
  }
  ```
- [ ] 実行中ジョブのリアルタイム更新UI
  - [ ] ProgressView表示
  - [ ] "実行中..."メッセージ

**新規ジョブ作成画面**:
- [ ] プリセット入力候補追加
  - [ ] よく使うプロンプトのテンプレート
  - [ ] タップで入力フィールドに挿入
- [ ] Runner選択のヘルプテキスト
  - [ ] "Claude: 汎用タスク向け"
  - [ ] "Codex: コード生成向け"

---

### 5.4 パフォーマンス最適化

- [ ] ジョブ一覧のページネーション実装
  - [ ] 初回20件取得
  - [ ] スクロール最下部でさらに20件取得
- [ ] 画像キャッシュ（該当する場合）
- [ ] メモリリークチェック
  - [ ] Instruments実行
  - [ ] メモリグラフ確認

---

### 5.5 アクセシビリティ対応

- [ ] VoiceOver対応
  - [ ] すべてのUI要素にaccessibilityLabel設定
  - [ ] 画像にaccessibilityHint設定
- [ ] Dynamic Type対応
  - [ ] .font(.body) 等のシステムフォント使用
  - [ ] カスタムフォントサイズ対応
- [ ] Color Contrast確認
  - [ ] WCAG AAレベル準拠確認

---

### 5.6 ローカライゼーション準備

- [ ] Localizable.stringsファイル作成
  - [ ] 日本語（ja）
  - [ ] 英語（en）
- [ ] すべてのUI文字列を`NSLocalizedString`化
  ```swift
  Text(NSLocalizedString("job_list_title", comment: "Jobs list title"))
  ```

---

### 5.7 最終動作確認

- [ ] 実機テスト（iPhone）
  - [ ] iOS 16.0
  - [ ] iOS 17.0+
- [ ] 実機テスト（Apple Watch）
  - [ ] watchOS 9.0
  - [ ] watchOS 10.0+
- [ ] 全機能動作確認
  - [ ] ジョブCRUD
  - [ ] プッシュ通知
  - [ ] Watch連携
  - [ ] セッション管理

---

### Phase 5 完了条件

- [ ] 全統合テスト成功
- [ ] エラーケース正常処理
- [ ] UI/UX改善完了
- [ ] パフォーマンス最適化完了
- [ ] アクセシビリティ対応完了
- [ ] 実機で全機能動作確認

---

## 実装完了チェックリスト

### 最終確認項目

- [ ] Phase 1完了（データモデル + API Client基盤）
- [ ] Phase 2完了（iOS 基本UI実装）
- [ ] Phase 3完了（プッシュ通知実装）
- [ ] Phase 4完了（Apple Watch 連携）
- [ ] Phase 5完了（統合テスト・UI/UX改善）

### App Store申請準備（オプション）

- [ ] アプリアイコン作成（1024x1024px）
- [ ] スクリーンショット作成（iPhone/Watch）
- [ ] App Store説明文作成
- [ ] プライバシーポリシー作成
- [ ] 利用規約作成
- [ ] TestFlight配布テスト
- [ ] App Store Connect設定
- [ ] 審査申請

---

## トラブルシューティング

### よくある問題

1. **プッシュ通知が届かない**
   - 対処: Provisioning Profileの再作成
   - デバイストークン再取得
   - サーバー側.p8ファイル確認

2. **Watch Connectivity接続失敗**
   - 対処: 両方のアプリを再起動
   - WCSession.activate()呼び出し確認
   - ペアリング確認

3. **API通信エラー**
   - 対処: Info.plist ATS設定確認
   - サーバーURL確認（Tailscale IP）
   - ネットワーク接続確認

4. **ジョブ詳細画面でクラッシュ**
   - 対処: オプショナルプロパティのnil処理確認
   - デコードエラーログ確認

---

## 次のステップ

iOS/watchOS実装完了後：
1. ユーザーフィードバック収集
2. 機能追加計画
   - ジョブ履歴検索
   - ジョブお気に入り機能
   - Watchコンプリケーション
3. 運用監視体制構築

---

**End of Implementation Plan**
