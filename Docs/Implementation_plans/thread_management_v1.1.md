# スレッド管理機能 実装計画 v1.1

## 概要

**目的**: Room → Thread List → Conversation の階層構造を実装し、各Roomで複数のスレッドを管理可能にする

**現在の構造**:
- Room → Conversation (直接)

**新しい構造**:
- Room → Thread List → Conversation (Thread選択で直接Conversationへ遷移)

---

## フェーズ1: データモデル設計

### 1.1 バックエンド - Thread モデル作成

#### 1.1.1 SQLAlchemy モデル定義
- [ ] `remote-job-server/models.py` にThreadクラスを追加
  - [ ] id: String (UUID, Primary Key)
  - [ ] room_id: String (Foreign Key to rooms.id)
  - [ ] name: String (デフォルト: "無題")
  - [ ] runner: String ("claude" or "codex")
  - [ ] device_id: String
  - [ ] created_at: DateTime
  - [ ] updated_at: DateTime
  - [ ] リレーション: room = relationship("Room", back_populates="threads")

#### 1.1.2 Room モデル更新
- [ ] `remote-job-server/models.py` の Room クラスを更新
  - [ ] threads = relationship("Thread", back_populates="room", cascade="all, delete-orphan")

#### 1.1.3 マイグレーション
- [ ] データベースマイグレーション実行
  - [ ] `remote-job-server/database.py` の init_db() でThreadテーブル作成確認
  - [ ] 既存データの移行計画 (既存会話を自動的にデフォルトスレッドに移行)

### 1.2 バックエンド - Thread API エンドポイント

#### 1.2.1 GET /api/rooms/{room_id}/threads
- [ ] `remote-job-server/main.py` にエンドポイント追加
  - [ ] パラメータ: room_id (path), device_id (query)
  - [ ] レスポンス: List[ThreadResponse]
  - [ ] ThreadResponse型定義 (id, room_id, name, runner, created_at, updated_at)
  - [ ] 認証チェック (device_id)
  - [ ] ソート順: updated_at DESC

#### 1.2.2 POST /api/rooms/{room_id}/threads
- [ ] `remote-job-server/main.py` にエンドポイント追加
  - [ ] パラメータ: room_id (path), device_id (query)
  - [ ] リクエストボディ: CreateThreadRequest (name, runner)
  - [ ] CreateThreadRequest型定義
  - [ ] バリデーション: runner in ["claude", "codex"]
  - [ ] デフォルト名: "無題"
  - [ ] レスポンス: ThreadResponse

#### 1.2.3 PATCH /api/threads/{thread_id}
- [ ] `remote-job-server/main.py` にエンドポイント追加
  - [ ] パラメータ: thread_id (path), device_id (query)
  - [ ] リクエストボディ: UpdateThreadRequest (name)
  - [ ] UpdateThreadRequest型定義
  - [ ] 認証チェック (device_id)
  - [ ] updated_at自動更新
  - [ ] レスポンス: ThreadResponse

#### 1.2.4 DELETE /api/threads/{thread_id}
- [ ] `remote-job-server/main.py` にエンドポイント追加
  - [ ] パラメータ: thread_id (path), device_id (query)
  - [ ] 認証チェック (device_id)
  - [ ] カスケード削除確認
  - [ ] レスポンス: 204 No Content

### 1.3 iOS - Thread モデル作成

#### 1.3.1 Thread struct 定義
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Models/Thread.swift` 作成
  - [ ] id: String
  - [ ] roomId: String
  - [ ] name: String
  - [ ] runner: String
  - [ ] createdAt: Date
  - [ ] updatedAt: Date
  - [ ] Identifiable, Codable, Hashable 準拠
  - [ ] CodingKeys (snake_case → camelCase)

---

## フェーズ2: バックエンドサービス実装

### 2.1 ThreadService 作成

#### 2.1.1 ThreadService.swift 作成
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/ThreadService.swift` 作成
  - [ ] listThreads(roomId: String, deviceId: String) async throws -> [Thread]
  - [ ] createThread(roomId: String, name: String, runner: String, deviceId: String) async throws -> Thread
  - [ ] updateThread(threadId: String, name: String, deviceId: String) async throws -> Thread
  - [ ] deleteThread(threadId: String, deviceId: String) async throws
  - [ ] エラーハンドリング (NetworkError型)

#### 2.1.2 APIClient 拡張
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/APIClient.swift` 更新
  - [ ] GET /api/rooms/{roomId}/threads メソッド追加
  - [ ] POST /api/rooms/{roomId}/threads メソッド追加
  - [ ] PATCH /api/threads/{threadId} メソッド追加
  - [ ] DELETE /api/threads/{threadId} メソッド追加

---

## フェーズ3: UI実装 - ThreadListView

### 3.1 ThreadListViewModel 作成

#### 3.1.1 ViewModel 基本実装
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ThreadListViewModel.swift` 作成
  - [ ] @Published var threads: [Thread] = []
  - [ ] @Published var isLoading = false
  - [ ] @Published var errorMessage: String?
  - [ ] private let roomId: String
  - [ ] private let deviceId: String
  - [ ] private let threadService: ThreadService

#### 3.1.2 ViewModel メソッド実装
- [ ] loadThreads() async
  - [ ] isLoading = true
  - [ ] threadService.listThreads() 呼び出し
  - [ ] threads 更新
  - [ ] エラーハンドリング
  - [ ] isLoading = false

- [ ] createThread(name: String, runner: String) async -> Thread?
  - [ ] threadService.createThread() 呼び出し
  - [ ] threads配列に追加
  - [ ] updated_at でソート
  - [ ] エラーハンドリング

- [ ] deleteThread(_ thread: Thread) async -> Bool
  - [ ] threadService.deleteThread() 呼び出し
  - [ ] threads配列から削除
  - [ ] エラーハンドリング

- [ ] updateThreadName(threadId: String, name: String) async -> Bool
  - [ ] threadService.updateThread() 呼び出し
  - [ ] threads配列内の該当スレッドを更新
  - [ ] エラーハンドリング

### 3.2 ThreadListView 作成

#### 3.2.1 基本レイアウト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/ThreadListView.swift` 作成
  - [ ] let room: Room
  - [ ] @StateObject private var viewModel: ThreadListViewModel
  - [ ] NavigationStack (RoomDetailViewから埋め込み、独自スタック不要)
  - [ ] List(threads) { thread in }
  - [ ] NavigationLink to ChatView
  - [ ] .navigationTitle(room.name)

#### 3.2.2 スレッドリスト表示
- [ ] ThreadRowView 作成 (private view)
  - [ ] HStack
  - [ ] VStack(alignment: .leading) - name + timestamp
  - [ ] Text(thread.name) - .font(.headline)
  - [ ] Text(formattedDate) - .font(.caption) + .foregroundColor(.secondary)
  - [ ] Spacer()
  - [ ] runner badge (Image + Text)
  - [ ] NavigationLink chevron 自動表示

- [ ] contextMenu でスレッド名編集
  - [ ] Button("名前を変更") { showEditSheet(thread) }
  - [ ] .sheet(isPresented: $editingThread)

- [ ] Swipe to delete
  - [ ] .onDelete(perform: deleteThreads)

#### 3.2.3 空状態表示
- [ ] Empty state view
  - [ ] Image(systemName: "bubble.left.and.bubble.right")
  - [ ] Text("スレッドがありません")
  - [ ] Text("右上のボタンから新しいスレッドを作成してください")
  - [ ] .frame(maxWidth: .infinity, maxHeight: .infinity)

#### 3.2.4 ローディング状態
- [ ] @State private var hasLoadedOnce = false
  - [ ] if !hasLoadedOnce || (threads.isEmpty && isLoading): ProgressView
  - [ ] .task { await loadThreads(); hasLoadedOnce = true }
  - [ ] .refreshable { await loadThreads() }

---

## フェーズ4: UI実装 - CreateThreadView

### 4.1 CreateThreadView 作成

#### 4.1.1 基本レイアウト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/CreateThreadView.swift` 作成
  - [ ] let room: Room
  - [ ] @ObservedObject var viewModel: ThreadListViewModel
  - [ ] @Environment(\.dismiss) private var dismiss
  - [ ] NavigationStack (sheet presentation)
  - [ ] Form with sections
  - [ ] .navigationTitle("新しいスレッド")
  - [ ] .navigationBarTitleDisplayMode(.inline)

#### 4.1.2 フォーム項目
- [ ] @State private var threadName = "無題"
  - [ ] Section(header: Text("スレッド名"))
  - [ ] TextField("スレッド名", text: $threadName)
  - [ ] .textFieldStyle(.roundedBorder)

- [ ] @State private var selectedRunner: String = "claude"
  - [ ] Section(header: Text("実行環境"))
  - [ ] Picker("", selection: $selectedRunner)
  - [ ] .pickerStyle(.segmented)
  - [ ] ForEach(["claude", "codex"], id: \.self)
  - [ ] Label with SF Symbol (claude: "bubble.left", codex: "chevron.left.forwardslash.chevron.right")

#### 4.1.3 ツールバー
- [ ] Leading: キャンセルボタン
  - [ ] Button("キャンセル") { dismiss() }

- [ ] Trailing: 作成ボタン
  - [ ] Button("作成") { Task { await createThread() } }
  - [ ] @State private var isCreating = false
  - [ ] if isCreating: ProgressView()
  - [ ] .disabled(!isValid || isCreating)

#### 4.1.4 バリデーション
- [ ] var isValid: Bool { computed }
  - [ ] let trimmed = threadName.trimmingCharacters(in: .whitespaces)
  - [ ] return !trimmed.isEmpty && trimmed.count <= 100

#### 4.1.5 作成処理
- [ ] createThread() async
  - [ ] isCreating = true
  - [ ] guard let newThread = await viewModel.createThread(name: threadName, runner: selectedRunner)
  - [ ] if success: dismiss()
  - [ ] if error: errorMessage設定, showError = true
  - [ ] isCreating = false

- [ ] @State private var showError = false
  - [ ] .alert("エラー", isPresented: $showError) { message }

---

## フェーズ5: UI実装 - EditThreadNameView

### 5.1 EditThreadNameView 作成

#### 5.1.1 基本レイアウト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/EditThreadNameView.swift` 作成
  - [ ] let thread: Thread
  - [ ] @ObservedObject var viewModel: ThreadListViewModel
  - [ ] @Environment(\.dismiss) private var dismiss
  - [ ] NavigationStack (sheet presentation)
  - [ ] Form

#### 5.1.2 フォーム項目
- [ ] @State private var editedName: String
  - [ ] init時に thread.name で初期化
  - [ ] TextField("スレッド名", text: $editedName)
  - [ ] .textFieldStyle(.roundedBorder)
  - [ ] .focused($isFocused)
  - [ ] @FocusState private var isFocused: Bool = true

#### 5.1.3 ツールバー
- [ ] Leading: キャンセルボタン
- [ ] Trailing: 保存ボタン
  - [ ] Task { await saveName() }
  - [ ] .disabled(!isValid || isSaving)

#### 5.1.4 保存処理
- [ ] saveName() async
  - [ ] guard editedName != thread.name
  - [ ] isSaving = true
  - [ ] success = await viewModel.updateThreadName(threadId: thread.id, name: editedName)
  - [ ] if success: dismiss()
  - [ ] isSaving = false

---

## フェーズ6: RoomDetailView リファクタリング

### 6.1 RoomDetailView 更新

#### 6.1.1 タブ削除とThreadListView埋め込み
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/RoomDetailView.swift` 更新
  - [ ] RunnerTab enum 削除
  - [ ] @State private var selectedTab 削除
  - [ ] claudeViewModel, codexViewModel 削除
  - [ ] Picker UI 削除

- [ ] ThreadListView 埋め込み
  - [ ] body: ThreadListView(room: room)
  - [ ] .navigationTitle(room.name) - ThreadListViewで設定
  - [ ] シンプルなコンテナビューに変更

#### 6.1.2 ツールバー再配置
- [ ] ドキュメントボタン移動
  - [ ] @State private var showFileBrowser = false
  - [ ] ToolbarItem(placement: .navigationBarLeading)
  - [ ] Button { showFileBrowser = true }
  - [ ] Image(systemName: "doc.text.magnifyingglass")

- [ ] スレッド作成ボタン追加
  - [ ] @State private var showCreateThread = false
  - [ ] ToolbarItem(placement: .primaryAction)
  - [ ] Button { showCreateThread = true }
  - [ ] Image(systemName: "plus")

#### 6.1.3 Sheet presentation
- [ ] .sheet(isPresented: $showFileBrowser)
  - [ ] FileBrowserView(room: room)

- [ ] .sheet(isPresented: $showCreateThread)
  - [ ] CreateThreadView(room: room, viewModel: threadListViewModel)
  - [ ] .presentationDetents([.medium])

---

## フェーズ7: ChatView 統合

### 7.1 ChatView への Thread 渡し

#### 7.1.1 ChatViewModel 更新
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ChatViewModel.swift` 更新
  - [ ] let thread: Thread
  - [ ] init に thread パラメータ追加
  - [ ] runner = thread.runner (固定)
  - [ ] roomId = thread.roomId

#### 7.1.2 NavigationLink from ThreadListView
- [ ] ThreadListView に NavigationLink 追加
  - [ ] NavigationLink(value: thread)
  - [ ] .navigationDestination(for: Thread.self) { thread in }
  - [ ] ChatView(viewModel: ChatViewModel(thread: thread))

#### 7.1.3 ナビゲーションバー
- [ ] ChatView のタイトル
  - [ ] .navigationTitle(thread.name)
  - [ ] タイトルタップで EditThreadNameView 表示
  - [ ] @State private var showEditName = false
  - [ ] .toolbar { ToolbarItem { Button { showEditName = true } } }
  - [ ] またはタイトル部分に .onTapGesture

---

## フェーズ8: ChatViewModel API連携更新

### 8.1 threadId パラメータ追加

#### 8.1.1 POST /api/chat 更新
- [ ] `remote-job-server/main.py` の /api/chat エンドポイント更新
  - [ ] リクエストボディに thread_id 追加
  - [ ] SendMessageRequest に thread_id: str フィールド追加
  - [ ] バリデーション: thread存在チェック

#### 8.1.2 ChatViewModel sendMessage 更新
- [ ] sendMessage() メソッド更新
  - [ ] リクエストに thread.id 含める
  - [ ] エラーハンドリング

---

## フェーズ9: データマイグレーション

### 9.1 既存データ移行

#### 9.1.1 マイグレーションスクリプト作成
- [ ] `remote-job-server/migrations/migrate_to_threads.py` 作成
  - [ ] 各 Room に対してループ
  - [ ] runner "claude" の デフォルトスレッド作成 ("Claude Code")
  - [ ] runner "codex" の デフォルトスレッド作成 ("Codex")
  - [ ] 既存メッセージを runner ベースで適切なスレッドに関連付け
  - [ ] messages テーブルに thread_id カラム追加
  - [ ] ログ出力 (進捗、エラー)

#### 9.1.2 ロールバック計画
- [ ] ロールバックスクリプト作成
  - [ ] threads テーブル削除
  - [ ] messages.thread_id カラム削除
  - [ ] 元の構造に戻す

#### 9.1.3 実行手順
- [ ] バックアップ作成
- [ ] マイグレーション実行
- [ ] データ整合性確認
- [ ] テスト

---

## フェーズ10: テスト実装

### 10.1 バックエンドテスト

#### 10.1.1 Thread API テスト
- [ ] `remote-job-server/tests/test_threads.py` 作成
  - [ ] test_list_threads_empty
  - [ ] test_list_threads_with_data
  - [ ] test_list_threads_sorted_by_updated_at
  - [ ] test_create_thread_success
  - [ ] test_create_thread_default_name
  - [ ] test_create_thread_invalid_runner
  - [ ] test_update_thread_name
  - [ ] test_delete_thread
  - [ ] test_thread_cascade_delete_with_room
  - [ ] test_unauthorized_access

### 10.2 iOS単体テスト

#### 10.2.1 ThreadService テスト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePromptTests/ThreadServiceTests.swift` 作成
  - [ ] testListThreads_success
  - [ ] testCreateThread_success
  - [ ] testUpdateThread_success
  - [ ] testDeleteThread_success
  - [ ] testNetworkError_handling

#### 10.2.2 ThreadListViewModel テスト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePromptTests/ThreadListViewModelTests.swift` 作成
  - [ ] testLoadThreads_updatesThreadsArray
  - [ ] testCreateThread_addsToList
  - [ ] testDeleteThread_removesFromList
  - [ ] testUpdateThreadName_updatesInList
  - [ ] testErrorHandling

### 10.3 UIテスト

#### 10.3.1 ThreadListView UIテスト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePromptUITests/ThreadListUITests.swift` 作成
  - [ ] testCreateThread_opensSheet
  - [ ] testThreadRow_tap_navigatesToChat
  - [ ] testSwipeToDelete
  - [ ] testEmptyState_display
  - [ ] testPullToRefresh

#### 10.3.2 Thread Name Edit UIテスト
- [ ] testContextMenu_showsEditOption
- [ ] testEditSheet_saveUpdatesName
- [ ] testChatViewTitle_showsThreadName

---

## フェーズ11: 統合とデバッグ

### 11.1 エンドツーエンドテスト

#### 11.1.1 フロー確認
- [ ] Room作成 → ThreadList自動表示
- [ ] Thread作成 → 即座にリストに追加、ソート
- [ ] Thread選択 → ChatView遷移
- [ ] メッセージ送信 → Thread内で保存
- [ ] Thread名編集 (ChatViewタイトルから) → 即座に反映
- [ ] Thread削除 (スワイプ) → リストから削除

#### 11.1.2 エッジケース
- [ ] 空文字列のスレッド名 (バリデーションエラー)
- [ ] 非常に長いスレッド名 (100文字制限)
- [ ] 同じ名前のスレッド複数作成 (許可)
- [ ] ネットワークエラー時の挙動
- [ ] 並行リクエスト処理
- [ ] 削除中のスレッドをタップ

### 11.2 パフォーマンス確認

#### 11.2.1 負荷テスト
- [ ] 100スレッド存在時のリスト表示速度
- [ ] スレッド作成時のレスポンスタイム
- [ ] スクロール時のメモリ使用量
- [ ] 大量メッセージ含むスレッドの遷移速度

---

## フェーズ12: ドキュメント更新

### 12.1 技術ドキュメント

#### 12.1.1 MASTER_SPECIFICATION.md 更新
- [ ] Thread管理の章追加
  - [ ] データモデル図 (Room - Thread - Message)
  - [ ] API仕様 (全エンドポイント)
  - [ ] 画面遷移図 (Room → ThreadList → ChatView)
  - [ ] データフロー図

#### 12.1.2 API ドキュメント
- [ ] OpenAPI/Swagger スキーマ更新
  - [ ] Thread エンドポイント定義
  - [ ] リクエスト/レスポンス例
  - [ ] エラーレスポンス定義

### 12.2 ユーザードキュメント

#### 12.2.1 README 更新
- [ ] スレッド機能の説明追加
- [ ] スクリーンショット更新
- [ ] 使い方ガイド

---

## チェックリスト完了基準

### 各フェーズの完了条件
- [ ] 全てのサブタスクが完了
- [ ] ユニットテスト全てパス
- [ ] UIテスト全てパス
- [ ] コードレビュー完了
- [ ] ドキュメント更新完了

### 全体完了条件
- [ ] 全フェーズ完了
- [ ] エンドツーエンドテスト成功
- [ ] パフォーマンス基準クリア
- [ ] ユーザー受け入れテスト完了
- [ ] 本番環境デプロイ可能

---

## リスクと対策

### リスク1: データマイグレーション失敗
- **対策**: ロールバックスクリプト事前準備、バックアップ必須、段階的実行

### リスク2: 既存会話との互換性
- **対策**: 既存メッセージを自動的にデフォルトスレッドに移行

### リスク3: UIパフォーマンス低下
- **対策**: LazyVStack使用、必要に応じてページネーション実装

### リスク4: API変更による既存クライアント影響
- **対策**: thread_id をオプショナルにして下位互換性維持

---

## 見積もり

### 各フェーズの工数目安
- フェーズ1: データモデル設計 - 4時間
- フェーズ2: バックエンドサービス - 4時間
- フェーズ3: ThreadListView - 4時間
- フェーズ4: CreateThreadView - 3時間
- フェーズ5: EditThreadNameView - 2時間
- フェーズ6: RoomDetailView リファクタリング - 2時間
- フェーズ7: ChatView 統合 - 3時間
- フェーズ8: ChatViewModel API連携更新 - 2時間
- フェーズ9: データマイグレーション - 3時間
- フェーズ10: テスト実装 - 6時間
- フェーズ11: 統合とデバッグ - 4時間
- フェーズ12: ドキュメント更新 - 2時間

**合計**: 約39時間

---

## 画面遷移図

```
RoomsList
    ↓ (Room選択)
RoomDetail (= ThreadList埋め込み)
    ├─ [＋ボタン] → CreateThreadView (Sheet)
    ├─ [ドキュメントボタン] → FileBrowserView (Sheet)
    └─ Thread選択
        ↓
    ChatView (NavigationLink)
        ├─ タイトルタップ → EditThreadNameView (Sheet)
        └─ メッセージ送受信
```

---

## データフロー

```
1. Thread作成
   CreateThreadView → ThreadListViewModel.createThread()
   → ThreadService.createThread() → POST /api/rooms/{id}/threads
   → DB: INSERT threads → Response: Thread
   → ThreadListViewModel: threads.append() → UI更新

2. Thread選択
   ThreadListView NavigationLink → ChatView(thread)
   → ChatViewModel.init(thread) → runner固定
   → loadMessages() → GET /api/chat?thread_id=xxx

3. メッセージ送信
   ChatView → ChatViewModel.sendMessage()
   → POST /api/chat { thread_id, message, ... }
   → DB: INSERT messages(thread_id) → Response

4. Thread名編集
   ChatView タイトルタップ → EditThreadNameView
   → ThreadListViewModel.updateThreadName()
   → ThreadService.updateThread() → PATCH /api/threads/{id}
   → DB: UPDATE threads → threads配列更新 → ChatView title更新
```

---

## 次のステップ

1. この計画v1.1をレビュー
2. 不明点の確認
3. フェーズ1から順次実装開始
4. 各フェーズ完了時にチェックマーク更新
5. 問題発生時は本ドキュメントに記録

---

**作成日**: 2025-01-20
**バージョン**: 1.1 (修正版: Thread Detail削除、直接Conversation遷移)
**作成者**: Claude Code
