# iOS/watchOS クライアント実装計画（RemotePrompt）

作成日: 2025-11-18
最終更新: 2025-11-18
バージョン: 2.1
対象: Phase 1 〜 Phase 5（チャット式UI実装 → Markdown表示 → watchOS連携 → プッシュ通知 + SSE）

**変更履歴**:
- v1.0 (2025-11-18): 初版作成
- v1.1 (2025-11-18): Master Specification v2.0との整合性修正
- v1.2 (2025-11-18): SSEストリーミング実装追加
- v2.0 (2025-11-18): UI仕様を Messenger ライクなチャット形式に全面変更
  - JobDetailView → ChatView（対話式メッセージ一覧）に変更
  - Markdown レンダリング機能追加（MarkdownUI ライブラリ使用）
  - メッセージバブル形式での入出力表示
  - サーバー保存形式は Markdown（`stdout` フィールド）
- **v2.1 (2025-11-18): 並列ジョブ対応・再起動時回復・ID管理の設計修正**
  - **重大修正1**: Message に `jobId` フィールド追加（localId と分離）
  - **重大修正2**: SSEManager をジョブ単位で個別管理（辞書方式）
  - **重大修正3**: アプリ起動時に未完了ジョブの SSE 再接続処理追加

---

## 実装フロー概要

```
Phase 1: チャットUIデータモデル + API Client拡張（2-3日）
  ↓
Phase 2: Messenger風チャットUI実装 + Markdown表示（3-4日）
  ↓
Phase 3: SSEリアルタイム更新 + プッシュ通知（2-3日）
  ↓
Phase 4: Apple Watch チャット連携（2-3日）
  ↓
Phase 5: 統合テスト・UI/UX改善（2-3日）
```

---

## UI設計コンセプト

### チャット形式の基本構造

```
┌─────────────────────────────┐
│ ← Claude Chat              │  ← ナビゲーションバー
├─────────────────────────────┤
│                             │
│  ┌─────────────────┐        │  ← ユーザー入力（右寄せ・青）
│  │ List files in   │        │
│  │ /tmp            │        │
│  └─────────────────┘        │
│           2025/11/18 10:00  │
│                             │
│        ┌─────────────────┐  │  ← AI応答（左寄せ・グレー）
│        │ # Files         │  │  ← Markdown表示
│        │ - file1.txt     │  │
│        │ - file2.log     │  │
│        │                 │  │
│        │ **Total**: 2    │  │
│        └─────────────────┘  │
│     2025/11/18 10:00 ✓     │
│                             │
│  ┌─────────────────┐        │
│  │ Thanks!         │        │
│  └─────────────────┘        │
│           2025/11/18 10:01  │
│                             │
├─────────────────────────────┤
│ ┌─────────────────────┐ [>]│  ← 入力フィールド + 送信ボタン
└─────────────────────────────┘
```

### データフロー

1. **ユーザー入力** → `POST /jobs` → ジョブID取得
2. **SSE接続** → `GET /jobs/{id}/stream` → リアルタイム状態更新
3. **完了通知** → `GET /jobs/{id}` → `stdout` を Markdown としてレンダリング
4. **メッセージ保存** → ローカルDB（Core Data / UserDefaults）でチャット履歴管理

---

## プロジェクト情報

**Xcodeプロジェクト名**: RemotePrompt
**プロジェクトパス**: `/Users/macstudio/Projects/RemotePrompt/iOS_WatchOS/RemotePrompt`
**サーバーURL**: `http://100.100.30.35:35000` (Tailscale VPN)
**対応プラットフォーム**: iOS 16.0+, watchOS 9.0+
**言語**: Swift 5.9+
**フレームワーク**: SwiftUI
**新規依存**: MarkdownUI (Swift Package Manager)

---

## Phase 1: チャットUIデータモデル + API Client拡張（2-3日）

### 目標
チャット形式に対応したデータモデルを構築し、ジョブ作成APIをクライアントに統合

### 1.1 プロジェクト構造更新

**ディレクトリ構成**:
```
RemotePrompt/
├── RemotePrompt/
│   ├── App/
│   │   ├── RemotePromptApp.swift（既存）
│   │   └── AppDelegate.swift
│   ├── Models/
│   │   ├── Message.swift          ← 新規：チャットメッセージモデル
│   │   ├── Job.swift              ← 既存
│   │   └── MessageType.swift      ← 新規：送信/受信区別
│   ├── Services/
│   │   ├── APIClient.swift        ← 拡張：ジョブ作成メソッド追加
│   │   ├── SSEManager.swift       ← 既存
│   │   └── MessageStore.swift     ← 新規：チャット履歴永続化
│   ├── Views/
│   │   ├── ChatView.swift         ← 新規：メインチャット画面
│   │   ├── MessageBubble.swift    ← 新規：メッセージ吹き出し
│   │   ├── MarkdownView.swift     ← 新規：Markdownレンダリング
│   │   └── InputBar.swift         ← 新規：入力フィールド
│   ├── ViewModels/
│   │   └── ChatViewModel.swift    ← 新規：チャット状態管理
│   └── Support/
│       └── Constants.swift        ← 既存
└── Package Dependencies:
    └── MarkdownUI (https://github.com/gonzalezreal/swift-markdown-ui)
```

- [ ] Xcodeでグループ作成・整理
  - [ ] Models に `Message.swift`, `MessageType.swift` 追加
  - [ ] Views に `ChatView.swift`, `MessageBubble.swift`, `MarkdownView.swift`, `InputBar.swift` 追加
  - [ ] Services に `MessageStore.swift` 追加
  - [ ] ViewModels に `ChatViewModel.swift` 追加

---

### 1.2 MarkdownUI 依存追加

**ファイル**: `RemotePrompt.xcodeproj/project.pbxproj`（Xcode GUI操作）

- [ ] Swift Package Manager で MarkdownUI 追加
  ```
  File → Add Package Dependencies...
  URL: https://github.com/gonzalezreal/swift-markdown-ui
  Version: 2.0.0以上
  Target: RemotePrompt (iOS)
  ```

- [ ] インポート確認
  ```swift
  import MarkdownUI
  ```

---

### 1.3 Message データモデル実装

**ファイル**: `Models/Message.swift`

- [ ] Message 構造体定義
  ```swift
  import Foundation

  enum MessageType: String, Codable {
      case user       // ユーザー入力
      case assistant  // AI応答
      case system     // システムメッセージ（エラー等）
  }

  enum MessageStatus: String, Codable {
      case sending    // 送信中
      case queued     // サーバーでキュー中
      case running    // 実行中
      case completed  // 完了
      case failed     // 失敗
  }

  struct Message: Identifiable, Codable {
      let id: String                // ✅ ローカルID（UUID、永続化用）
      let jobId: String?            // ✅ サーバージョブID（assistant のみ、SSE購読用）
      let type: MessageType
      let content: String           // ユーザー入力 or AI応答（Markdown）
      var status: MessageStatus
      let createdAt: Date
      var finishedAt: Date?
      var errorMessage: String?

      var isRunning: Bool {
          status == .sending || status == .queued || status == .running
      }

      // ✅ 初期化ヘルパー
      init(
          id: String = UUID().uuidString,
          jobId: String? = nil,
          type: MessageType,
          content: String,
          status: MessageStatus,
          createdAt: Date = Date(),
          finishedAt: Date? = nil,
          errorMessage: String? = nil
      ) {
          self.id = id
          self.jobId = jobId
          self.type = type
          self.content = content
          self.status = status
          self.createdAt = createdAt
          self.finishedAt = finishedAt
          self.errorMessage = errorMessage
      }
  }
  ```

- [ ] CodingKeys 定義（JSON互換）
- [ ] 初期化メソッド実装

---

### 1.4 APIClient 拡張（ジョブ作成）

**ファイル**: `Services/APIClient.swift`（既存ファイル更新）

- [ ] ジョブ作成メソッド追加
  ```swift
  struct CreateJobRequest: Codable {
      let runner: String
      let inputText: String
      let deviceId: String
      let notifyToken: String?

      enum CodingKeys: String, CodingKey {
          case runner
          case inputText = "input_text"
          case deviceId = "device_id"
          case notifyToken = "notify_token"
      }
  }

  struct CreateJobResponse: Codable {
      let id: String
      let runner: String
      let status: String
  }

  func createJob(runner: String, prompt: String, deviceId: String) async throws -> CreateJobResponse {
      guard let url = URL(string: "\(Constants.baseURL)/jobs") else {
          throw APIError.invalidURL
      }

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body = CreateJobRequest(
          runner: runner,
          inputText: prompt,
          deviceId: deviceId,
          notifyToken: nil
      )
      request.httpBody = try JSONEncoder().encode(body)

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
          let code = (response as? HTTPURLResponse)?.statusCode ?? -1
          throw APIError.httpError(code)
      }

      return try JSONDecoder().decode(CreateJobResponse.self, from: data)
  }
  ```

- [ ] デバイスID生成ヘルパー追加
  ```swift
  static func getDeviceId() -> String {
      if let saved = UserDefaults.standard.string(forKey: "device_id") {
          return saved
      }
      let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
      UserDefaults.standard.set(newId, forKey: "device_id")
      return newId
  }
  ```

---

### 1.5 MessageStore 実装（ローカル永続化）

**ファイル**: `Services/MessageStore.swift`

- [ ] MessageStore クラス定義
  ```swift
  import Foundation
  import Combine

  final class MessageStore: ObservableObject {
      @Published var messages: [Message] = []
      private let storageKey = "chat_messages"

      init() {
          loadMessages()
      }

      func addMessage(_ message: Message) {
          messages.append(message)
          saveMessages()
      }

      func updateMessage(_ message: Message) {
          if let index = messages.firstIndex(where: { $0.id == message.id }) {
              messages[index] = message
              saveMessages()
          }
      }

      func clearAll() {
          messages.removeAll()
          saveMessages()
      }

      private func saveMessages() {
          if let encoded = try? JSONEncoder().encode(messages) {
              UserDefaults.standard.set(encoded, forKey: storageKey)
          }
      }

      private func loadMessages() {
          guard let data = UserDefaults.standard.data(forKey: storageKey),
                let decoded = try? JSONDecoder().decode([Message].self, from: data) else {
              return
          }
          messages = decoded
      }
  }
  ```

- [ ] UserDefaults ベースの永続化実装
- [ ] メッセージ追加・更新・削除メソッド実装

---

### Phase 1 完了条件

- [ ] Message / MessageType データモデル実装完了
- [ ] APIClient に createJob メソッド追加完了
- [ ] MessageStore 永続化実装完了
- [ ] MarkdownUI 依存追加完了
- [ ] ビルド成功（シミュレータで起動確認）

---

## Phase 2: Messenger風チャットUI実装 + Markdown表示（3-4日）

### 目標
チャット画面とメッセージバブル、Markdown表示機能を実装

### 2.1 MessageBubble（メッセージ吹き出し）実装

**ファイル**: `Views/MessageBubble.swift`

- [ ] MessageBubble View 実装
  ```swift
  import SwiftUI
  import MarkdownUI

  struct MessageBubble: View {
      let message: Message

      var body: some View {
          HStack(alignment: .top, spacing: 8) {
              if message.type == .user {
                  Spacer()
              }

              VStack(alignment: message.type == .user ? .trailing : .leading, spacing: 4) {
                  // メッセージ本体
                  if message.type == .assistant {
                      // AI応答はMarkdown表示
                      Markdown(message.content)
                          .markdownTheme(.gitHub)
                          .padding(12)
                          .background(Color(.systemGray6))
                          .cornerRadius(16)
                  } else {
                      // ユーザー入力はテキスト表示
                      Text(message.content)
                          .padding(12)
                          .background(message.type == .user ? Color.blue : Color(.systemGray5))
                          .foregroundColor(message.type == .user ? .white : .primary)
                          .cornerRadius(16)
                  }

                  // ステータス・タイムスタンプ
                  HStack(spacing: 4) {
                      if message.isRunning {
                          ProgressView()
                              .scaleEffect(0.7)
                      }
                      Text(statusText)
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                      if message.status == .completed {
                          Image(systemName: "checkmark")
                              .font(.caption2)
                              .foregroundStyle(.green)
                      } else if message.status == .failed {
                          Image(systemName: "exclamationmark.triangle")
                              .font(.caption2)
                              .foregroundStyle(.red)
                      }
                  }
              }

              if message.type == .assistant {
                  Spacer()
              }
          }
          .padding(.horizontal)
      }

      private var statusText: String {
          switch message.status {
          case .sending: return "送信中..."
          case .queued: return "待機中"
          case .running: return "実行中"
          case .completed:
              if let finished = message.finishedAt {
                  return finished.formatted(date: .omitted, time: .shortened)
              }
              return "完了"
          case .failed: return "失敗"
          }
      }
  }
  ```

- [ ] ユーザー/AI の吹き出し配置切り替え
- [ ] Markdown レンダリング統合
- [ ] ステータスアイコン表示

---

### 2.2 InputBar（入力フィールド）実装

**ファイル**: `Views/InputBar.swift`

- [ ] InputBar View 実装
  ```swift
  import SwiftUI

  struct InputBar: View {
      @Binding var text: String
      let onSend: () -> Void
      let isLoading: Bool

      var body: some View {
          HStack(spacing: 12) {
              TextField("メッセージを入力...", text: $text, axis: .vertical)
                  .textFieldStyle(.roundedBorder)
                  .lineLimit(1...5)
                  .disabled(isLoading)

              Button(action: onSend) {
                  Image(systemName: "arrow.up.circle.fill")
                      .font(.title2)
                      .foregroundStyle(canSend ? .blue : .gray)
              }
              .disabled(!canSend)
          }
          .padding()
          .background(Color(.systemBackground))
      }

      private var canSend: Bool {
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
      }
  }
  ```

- [ ] 複数行入力対応（最大5行）
- [ ] 送信ボタン有効/無効切り替え
- [ ] ローディング中の入力無効化

---

### 2.3 ChatViewModel 実装

**ファイル**: `ViewModels/ChatViewModel.swift`

- [ ] ChatViewModel クラス定義
  ```swift
  import Foundation
  import Combine

  @MainActor
  final class ChatViewModel: ObservableObject {
      @Published var messages: [Message] = []
      @Published var inputText: String = ""
      @Published var isLoading: Bool = false
      @Published var errorMessage: String?

      private let apiClient = APIClient.shared
      private let messageStore = MessageStore()
      // ✅ 修正: ジョブIDをキーにしたSSE接続辞書
      private var sseConnections: [String: SSEManager] = [:]
      private var cancellables = Set<AnyCancellable>()
      private let runner: String  // "claude" or "codex"

      init(runner: String = "claude") {
          self.runner = runner
          loadMessages()
          // ✅ 修正: 起動時に未完了ジョブを回復
          Task {
              await recoverIncompleteJobs()
          }
      }

      func loadMessages() {
          messages = messageStore.messages
      }

      // ✅ 追加: 未完了ジョブの回復処理
      private func recoverIncompleteJobs() async {
          let incompleteJobs = messages.filter { $0.isRunning && $0.jobId != nil }

          for message in incompleteJobs {
              guard let jobId = message.jobId else { continue }

              // サーバーから最新状態を取得
              do {
                  let job = try await apiClient.fetchJob(id: jobId)

                  // ローカルメッセージを更新
                  if let index = messages.firstIndex(where: { $0.id == message.id }) {
                      var updated = messages[index]
                      updated.status = job.status == "success" ? .completed :
                                      job.status == "failed" ? .failed :
                                      job.status == "running" ? .running : .queued
                      updated.content = job.stdout ?? updated.content
                      updated.finishedAt = job.finishedAt
                      updated.errorMessage = job.stderr

                      messages[index] = updated
                      messageStore.updateMessage(updated)

                      // まだ実行中なら SSE 再接続
                      if updated.isRunning {
                          startSSEStreaming(jobId: jobId, messageId: message.id)
                      }
                  }
              } catch {
                  // エラー時はジョブを失敗扱い
                  if let index = messages.firstIndex(where: { $0.id == message.id }) {
                      var failed = messages[index]
                      failed.status = .failed
                      failed.errorMessage = "回復失敗: \(error.localizedDescription)"
                      messages[index] = failed
                      messageStore.updateMessage(failed)
                  }
              }
          }
      }

      func sendMessage() {
          let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !prompt.isEmpty else { return }

          inputText = ""
          isLoading = true

          // ✅ 修正: ユーザーメッセージ（jobId は nil）
          let userMessage = Message(
              type: .user,
              content: prompt,
              status: .sending
          )
          messages.append(userMessage)
          messageStore.addMessage(userMessage)

          Task {
              do {
                  // ジョブ作成
                  let response = try await apiClient.createJob(
                      runner: runner,
                      prompt: prompt,
                      deviceId: APIClient.getDeviceId()
                  )

                  // ユーザーメッセージのステータス更新
                  var updatedUserMsg = userMessage
                  updatedUserMsg.status = .queued
                  updateMessage(updatedUserMsg)

                  // ✅ 修正: AI応答メッセージ（jobId にサーバーIDを設定）
                  let assistantMessage = Message(
                      jobId: response.id,
                      type: .assistant,
                      content: "",
                      status: .queued
                  )
                  messages.append(assistantMessage)
                  messageStore.addMessage(assistantMessage)

                  // ✅ 修正: SSE接続（messageIdも渡す）
                  startSSEStreaming(jobId: response.id, messageId: assistantMessage.id)

              } catch {
                  errorMessage = error.localizedDescription
                  // エラーメッセージを表示
                  var failedMsg = userMessage
                  failedMsg.status = .failed
                  failedMsg.errorMessage = error.localizedDescription
                  updateMessage(failedMsg)
              }
              isLoading = false
          }
      }

      // ✅ 修正: ジョブごとに個別SSEManager生成・購読
      private func startSSEStreaming(jobId: String, messageId: String) {
          // 既存接続があれば切断
          if let existing = sseConnections[jobId] {
              existing.disconnect()
          }

          // 新規SSEManager生成
          let manager = SSEManager()
          sseConnections[jobId] = manager
          manager.connect(jobId: jobId)

          // ✅ messageId をクロージャでキャプチャして正しいメッセージを更新
          manager.$jobStatus
              .receive(on: RunLoop.main)
              .sink { [weak self] status in
                  guard let self else { return }
                  self.updateMessageStatus(messageId: messageId, status: status)
              }
              .store(in: &cancellables)

          manager.$isConnected
              .receive(on: RunLoop.main)
              .sink { [weak self] connected in
                  guard let self else { return }
                  if !connected {
                      // SSE切断時は最終結果を取得
                      Task {
                          await self.fetchFinalResult(jobId: jobId, messageId: messageId)
                          // 切断後はマネージャを削除
                          self.sseConnections.removeValue(forKey: jobId)
                      }
                  }
              }
              .store(in: &cancellables)
      }

      // ✅ 修正: messageId で検索
      private func updateMessageStatus(messageId: String, status: String) {
          guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
          var message = messages[index]

          switch status {
          case "running":
              message.status = .running
          case "success":
              message.status = .completed
              message.finishedAt = Date()
          case "failed":
              message.status = .failed
              message.finishedAt = Date()
          default:
              break
          }

          messages[index] = message
          messageStore.updateMessage(message)
      }

      // ✅ 修正: messageId で検索
      private func fetchFinalResult(jobId: String, messageId: String) async {
          do {
              let job = try await apiClient.fetchJob(id: jobId)
              guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

              var message = messages[index]
              message.content = job.stdout ?? ""
              message.status = job.status == "success" ? .completed : .failed
              message.finishedAt = job.finishedAt
              message.errorMessage = job.stderr

              messages[index] = message
              messageStore.updateMessage(message)
          } catch {
              errorMessage = error.localizedDescription
          }
      }

      private func updateMessage(_ message: Message) {
          if let index = messages.firstIndex(where: { $0.id == message.id }) {
              messages[index] = message
              messageStore.updateMessage(message)
          }
      }

      func clearChat() {
          // ✅ 全SSE接続を切断
          for (_, manager) in sseConnections {
              manager.disconnect()
          }
          sseConnections.removeAll()
          cancellables.removeAll()

          messages.removeAll()
          messageStore.clearAll()
      }

      // ✅ deinit時のクリーンアップ
      deinit {
          for (_, manager) in sseConnections {
              manager.disconnect()
          }
      }
  }
  ```

- [ ] メッセージ送信ロジック実装
- [ ] SSE接続によるリアルタイム更新
- [ ] 最終結果取得（Markdown形式）

---

### 2.4 ChatView（メインチャット画面）実装

**ファイル**: `Views/ChatView.swift`

- [ ] ChatView 実装
  ```swift
  import SwiftUI

  struct ChatView: View {
      @StateObject private var viewModel = ChatViewModel(runner: "claude")
      @State private var scrollProxy: ScrollViewProxy?

      var body: some View {
          NavigationStack {
              VStack(spacing: 0) {
                  // メッセージ一覧
                  ScrollViewReader { proxy in
                      ScrollView {
                          LazyVStack(spacing: 12) {
                              ForEach(viewModel.messages) { message in
                                  MessageBubble(message: message)
                                      .id(message.id)
                              }
                          }
                          .padding(.vertical)
                      }
                      .onAppear {
                          scrollProxy = proxy
                      }
                      .onChange(of: viewModel.messages.count) { _ in
                          scrollToBottom()
                      }
                  }

                  Divider()

                  // 入力バー
                  InputBar(
                      text: $viewModel.inputText,
                      onSend: {
                          viewModel.sendMessage()
                      },
                      isLoading: viewModel.isLoading
                  )
              }
              .navigationTitle("Claude Chat")
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                  ToolbarItem(placement: .navigationBarTrailing) {
                      Menu {
                          Button("履歴をクリア") {
                              viewModel.clearChat()
                          }
                          Button("Codexに切り替え") {
                              // TODO: runner切り替え
                          }
                      } label: {
                          Image(systemName: "ellipsis.circle")
                      }
                  }
              }
          }
      }

      private func scrollToBottom() {
          guard let lastMessage = viewModel.messages.last else { return }
          withAnimation {
              scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
          }
      }
  }
  ```

- [ ] ScrollView + LazyVStack でメッセージ一覧表示
- [ ] 新着メッセージ時の自動スクロール
- [ ] ツールバーメニュー（履歴クリア、runner切り替え）

---

### 2.5 ContentView 更新

**ファイル**: `ContentView.swift`

- [ ] ChatView を呼び出すように変更
  ```swift
  import SwiftUI

  struct ContentView: View {
      var body: some View {
          ChatView()
      }
  }
  ```

---

### Phase 2 完了条件

- [ ] MessageBubble 実装完了（ユーザー/AI吹き出し表示）
- [ ] InputBar 実装完了（複数行入力対応）
- [ ] ChatViewModel 実装完了（メッセージ送信・SSE更新）
- [ ] ChatView 実装完了（チャット画面表示）
- [ ] Markdown表示動作確認（MarkdownUIでレンダリング成功）
- [ ] シミュレータでチャット送受信成功

---

## Phase 3: SSEリアルタイム更新 + プッシュ通知（2-3日）

### 目標
既存のSSE実装を活用し、バックグラウンド時のプッシュ通知を統合

### 3.1 SSE統合確認

**前提**: Phase 1.2（v1.2）で実装済み

- [ ] SSEManager が ChatViewModel で正しく動作することを確認
- [ ] ジョブ状態変更イベントが Message.status に反映されることを確認
- [ ] SSE切断時のポーリングフォールバック動作確認

---

### 3.2 プッシュ通知設定

**ファイル**: `App/AppDelegate.swift`

- [ ] AppDelegate 実装（既存実装計画を流用）
  - [ ] UNUserNotificationCenter でプッシュ通知許可要求
  - [ ] デバイストークン取得
  - [ ] サーバーへデバイス登録（POST /register_device）
  - [ ] 通知タップ時のディープリンク処理

- [ ] Apple Developer Portal で APNs 設定
  - [ ] Push Notifications Capability 有効化
  - [ ] .p8 認証キー取得

---

### 3.3 通知受信時の処理

- [ ] 通知ペイロードからジョブID抽出
- [ ] ChatView でジョブIDに該当するメッセージをハイライト
- [ ] 最新結果を取得して Markdown 表示更新

---

### Phase 3 完了条件

- [ ] SSE接続でチャットメッセージがリアルタイム更新
- [ ] バックグラウンド時にプッシュ通知受信成功
- [ ] 通知タップで該当メッセージに遷移成功

---

## Phase 4: Apple Watch チャット連携（2-3日）

### 目標
Apple Watchでプリセットプロンプトを送信し、iPhoneのチャット履歴と同期

### 4.1 Watch Extension 作成

- [ ] Xcode で Watch App Target 追加
- [ ] Watch Connectivity フレームワーク追加

---

### 4.2 Watch プリセット画面実装

**ファイル**: `WatchApp/PresetListView.swift`

- [ ] プリセットボタン一覧表示
  ```swift
  struct PresetListView: View {
      let presets = [
          ("ログ確認", "check_logs"),
          ("システム状態", "system_status"),
          ("エラー解析", "analyze_error")
      ]

      var body: some View {
          List(presets, id: \.1) { preset in
              Button(preset.0) {
                  sendPreset(preset.1)
              }
          }
      }

      func sendPreset(_ action: String) {
          // iPhone に WatchConnectivity 経由で送信
      }
  }
  ```

---

### 4.3 iPhone ↔ Watch 通信

- [ ] WCSession でプリセット送信
- [ ] iPhone 側で受信→ジョブ作成→チャット履歴に追加
- [ ] Watch 側で実行結果を簡易表示（テキストのみ）

---

### Phase 4 完了条件

- [ ] Watch からプリセット送信成功
- [ ] iPhone のチャット履歴に反映成功
- [ ] Watch で実行結果受信成功

---

## Phase 5: 統合テスト・UI/UX改善（2-3日）

### 目標
E2Eテストと使いやすさの改善

### 5.1 統合テストシナリオ

- [ ] シナリオ1: チャットメッセージ送信→SSE更新→Markdown表示
- [ ] シナリオ2: バックグラウンド→プッシュ通知→フォアグラウンド復帰
- [ ] シナリオ3: Watch からプリセット送信→iPhone で結果確認
- [ ] シナリオ4: オフライン→オンライン復帰時の再送処理
- [ ] シナリオ5: 長文Markdown（コードブロック、表、リスト）の表示確認

---

### 5.2 UI/UX改善

- [ ] メッセージバブルの最大幅調整
- [ ] Markdown テーマカスタマイズ（コードブロックのシンタックスハイライト）
- [ ] 入力中インジケーター（「AI が入力中...」表示）
- [ ] エラーメッセージの再送ボタン
- [ ] チャット履歴の検索機能
- [ ] ダークモード対応確認

---

### 5.3 パフォーマンステスト

- [ ] 100件メッセージでのスクロール性能確認
- [ ] Markdown レンダリング速度測定
- [ ] SSE接続のメモリリーク確認

---

### Phase 5 完了条件

- [ ] 全統合テストシナリオ成功
- [ ] UI/UX改善項目実装完了
- [ ] パフォーマンステスト合格
- [ ] App Store 提出可能な品質到達

---

## 実装完了チェックリスト

### 最終確認項目

- [ ] Phase 1完了（チャットUIデータモデル + API Client拡張）
- [ ] Phase 2完了（Messenger風チャットUI + Markdown表示）
- [ ] Phase 3完了（SSEリアルタイム更新 + プッシュ通知）
- [ ] Phase 4完了（Apple Watch チャット連携）
- [ ] Phase 5完了（統合テスト・UI/UX改善）

### リリース準備

- [ ] TestFlight ビルドアップロード
- [ ] 実機テスト（iPhone + Apple Watch）
- [ ] スクリーンショット作成
- [ ] App Store 説明文作成

---

## 技術スタック まとめ

| レイヤー | 技術 | 用途 |
|---------|------|------|
| UI | SwiftUI | チャット画面、メッセージバブル |
| Markdown | MarkdownUI | AI応答のMarkdown表示 |
| ネットワーク | URLSession | REST API通信 |
| リアルタイム | SSE（URLSessionDataDelegate） | ジョブ状態更新 |
| 永続化 | UserDefaults | チャット履歴保存 |
| 通知 | UNUserNotificationCenter + APNs | バックグラウンド通知 |
| Watch連携 | WatchConnectivity | プリセット送信 |

---

## 参考資料

- [MarkdownUI GitHub](https://github.com/gonzalezreal/swift-markdown-ui)
- [Apple Push Notifications Guide](https://developer.apple.com/documentation/usernotifications)
- [WatchConnectivity Framework](https://developer.apple.com/documentation/watchconnectivity)
- [Server-Sent Events (SSE) Specification](https://html.spec.whatwg.org/multipage/server-sent-events.html)

---

**End of Implementation Plan**
