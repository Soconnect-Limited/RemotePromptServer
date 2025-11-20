# スレッド管理機能 実装計画 v1.0

## 概要

**目的**: Room → Thread → Conversation の3階層構造を実装し、各Roomで複数のスレッドを管理可能にする

**現在の構造**:
- Room → Conversation (直接)

**新しい構造**:
- Room → Thread List → Thread Detail → Conversation

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
  - [ ] エラーハンドリング

- [ ] deleteThread(_ thread: Thread) async -> Bool
  - [ ] threadService.deleteThread() 呼び出し
  - [ ] threads配列から削除
  - [ ] エラーハンドリング

### 3.2 ThreadListView 作成

#### 3.2.1 基本レイアウト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/ThreadListView.swift` 作成
  - [ ] NavigationStack
  - [ ] List(threads) { thread in }
  - [ ] NavigationLink to ThreadDetailView
  - [ ] .navigationTitle("スレッド")
  - [ ] .toolbar with + button

#### 3.2.2 スレッドリスト表示
- [ ] ThreadRowView 作成
  - [ ] VStack(alignment: .leading)
  - [ ] Text(thread.name) - .font(.headline)
  - [ ] HStack - runner icon + updated_at
  - [ ] Swipe to delete

#### 3.2.3 空状態表示
- [ ] Empty state view
  - [ ] Image(systemName: "bubble.left.and.bubble.right")
  - [ ] Text("スレッドがありません")
  - [ ] Text("右上のボタンから新しいスレッドを作成してください")

#### 3.2.4 ローディング状態
- [ ] hasLoadedOnce フラグ追加
  - [ ] 初回ロード中: ProgressView表示
  - [ ] ロード完了後: リスト表示
  - [ ] .refreshable でリロード対応

---

## フェーズ4: UI実装 - CreateThreadView

### 4.1 CreateThreadView 作成

#### 4.1.1 基本レイアウト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/CreateThreadView.swift` 作成
  - [ ] NavigationStack (sheet presentation)
  - [ ] Form with sections
  - [ ] .navigationTitle("新しいスレッド")
  - [ ] .navigationBarTitleDisplayMode(.inline)

#### 4.1.2 フォーム項目
- [ ] @State private var threadName = "無題"
  - [ ] TextField("スレッド名", text: $threadName)

- [ ] @State private var selectedRunner: String = "claude"
  - [ ] Picker("実行環境", selection: $selectedRunner)
  - [ ] ForEach(["claude", "codex"])
  - [ ] Label with SF Symbol

#### 4.1.3 ツールバー
- [ ] Leading: キャンセルボタン
  - [ ] dismiss()

- [ ] Trailing: 作成ボタン
  - [ ] Task { await createThread() }
  - [ ] isCreating 時は ProgressView
  - [ ] disabled(!isValid || isCreating)

#### 4.1.4 バリデーション
- [ ] var isValid: Bool
  - [ ] !threadName.trimmingCharacters(in: .whitespaces).isEmpty
  - [ ] threadName.count <= 100

#### 4.1.5 作成処理
- [ ] createThread() async
  - [ ] viewModel.createThread() 呼び出し
  - [ ] 成功時: dismiss()
  - [ ] エラー時: errorMessage 設定
  - [ ] Alert表示

---

## フェーズ5: UI実装 - ThreadDetailView

### 5.1 ThreadDetailView 作成

#### 5.1.1 基本構造
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/ThreadDetailView.swift` 作成
  - [ ] let thread: Thread
  - [ ] @State private var isEditingTitle = false
  - [ ] @State private var editedName = ""
  - [ ] ChatView 埋め込み

#### 5.1.2 ナビゲーションバー
- [ ] タイトル部分
  - [ ] if isEditingTitle: TextField
  - [ ] else: Text(thread.name) + .onTapGesture
  - [ ] .font(.headline)

#### 5.1.3 タイトル編集機能
- [ ] onTapGesture
  - [ ] editedName = thread.name
  - [ ] isEditingTitle = true
  - [ ] Focus on TextField

- [ ] TextField
  - [ ] .textFieldStyle(.roundedBorder)
  - [ ] .onSubmit { saveTitle() }
  - [ ] .focused($isFocused)

- [ ] saveTitle() async
  - [ ] guard editedName != thread.name
  - [ ] viewModel.updateThread() 呼び出し
  - [ ] isEditingTitle = false
  - [ ] エラーハンドリング

#### 5.1.4 ChatView 統合
- [ ] ChatViewModel 初期化
  - [ ] runner: thread.runner
  - [ ] roomId: thread.roomId
  - [ ] threadId: thread.id (新規パラメータ)

---

## フェーズ6: RoomDetailView リファクタリング

### 6.1 RoomDetailView 更新

#### 6.1.1 ThreadListView への遷移
- [ ] タブ削除 (claude/codex picker 削除)
  - [ ] RunnerTab enum 削除
  - [ ] selectedTab state 削除
  - [ ] Picker UI 削除

- [ ] ThreadListView 埋め込み
  - [ ] body: ThreadListView(room: room)
  - [ ] .navigationTitle(room.name) 維持

#### 6.1.2 ツールバー再配置
- [ ] ドキュメントボタン移動
  - [ ] placement: .navigationBarLeading (キーボード隠すボタンの逆側)
  - [ ] または .secondaryAction

- [ ] スレッド作成ボタン
  - [ ] placement: .primaryAction (右上)
  - [ ] Image(systemName: "plus")
  - [ ] showCreateThread = true

#### 6.1.3 Sheet presentation
- [ ] .sheet(isPresented: $showCreateThread)
  - [ ] CreateThreadView(room: room)
  - [ ] .presentationDetents([.medium, .large])

---

## フェーズ7: ChatViewModel 更新

### 7.1 threadId パラメータ追加

#### 7.1.1 ChatViewModel 更新
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ChatViewModel.swift` 更新
  - [ ] let threadId: String?
  - [ ] init に threadId パラメータ追加
  - [ ] sendMessage API呼び出しに threadId 含める

#### 7.1.2 API 更新
- [ ] POST /api/chat エンドポイント更新
  - [ ] リクエストボディに thread_id 追加
  - [ ] データベース保存時に thread_id 関連付け

---

## フェーズ8: データマイグレーション

### 8.1 既存データ移行

#### 8.1.1 マイグレーションスクリプト作成
- [ ] `remote-job-server/migrations/migrate_to_threads.py` 作成
  - [ ] 各 Room に対して
  - [ ] runner ごとにデフォルトスレッド作成 ("Claude Code", "Codex")
  - [ ] 既存メッセージを適切なスレッドに関連付け
  - [ ] ログ出力

#### 8.1.2 ロールバック計画
- [ ] ロールバックスクリプト作成
  - [ ] Thread テーブル削除
  - [ ] messages.thread_id カラム削除
  - [ ] 元の構造に戻す

---

## フェーズ9: テスト実装

### 9.1 バックエンドテスト

#### 9.1.1 Thread API テスト
- [ ] `remote-job-server/tests/test_threads.py` 作成
  - [ ] test_list_threads_empty
  - [ ] test_list_threads_with_data
  - [ ] test_create_thread_success
  - [ ] test_create_thread_invalid_runner
  - [ ] test_update_thread_name
  - [ ] test_delete_thread
  - [ ] test_thread_cascade_delete_with_room

### 9.2 iOS単体テスト

#### 9.2.1 ThreadService テスト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePromptTests/ThreadServiceTests.swift` 作成
  - [ ] test_listThreads_success
  - [ ] test_createThread_success
  - [ ] test_updateThread_success
  - [ ] test_deleteThread_success
  - [ ] test_networkError_handling

#### 9.2.2 ThreadListViewModel テスト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePromptTests/ThreadListViewModelTests.swift` 作成
  - [ ] test_loadThreads_updatesThreads
  - [ ] test_createThread_addsToList
  - [ ] test_deleteThread_removesFromList
  - [ ] test_errorHandling

### 9.3 UIテスト

#### 9.3.1 ThreadListView UIテスト
- [ ] `iOS_WatchOS/RemotePrompt/RemotePromptUITests/ThreadListUITests.swift` 作成
  - [ ] test_createThread_navigation
  - [ ] test_threadRow_tap_navigatesToDetail
  - [ ] test_swipeToDelete
  - [ ] test_emptyState_display

#### 9.3.2 ThreadDetailView UIテスト
- [ ] test_titleTap_showsTextField
  - [ ] test_titleEdit_savesOnSubmit
  - [ ] test_chatView_integration

---

## フェーズ10: 統合とデバッグ

### 10.1 エンドツーエンドテスト

#### 10.1.1 フロー確認
- [ ] Room作成 → ThreadList表示
- [ ] Thread作成 → 詳細画面遷移
- [ ] メッセージ送信 → Thread内で保存
- [ ] Thread名編集 → 即座に反映
- [ ] Thread削除 → リストから削除

#### 10.1.2 エッジケース
- [ ] 空文字列のスレッド名
- [ ] 非常に長いスレッド名 (100文字制限)
- [ ] 同じ名前のスレッド複数作成
- [ ] ネットワークエラー時の挙動
- [ ] 並行リクエスト処理

### 10.2 パフォーマンス確認

#### 10.2.1 負荷テスト
- [ ] 100スレッド存在時のリスト表示速度
- [ ] スレッド作成時のレスポンスタイム
- [ ] スクロール時のメモリ使用量

---

## フェーズ11: ドキュメント更新

### 11.1 技術ドキュメント

#### 11.1.1 MASTER_SPECIFICATION.md 更新
- [ ] Thread管理の章追加
  - [ ] データモデル図
  - [ ] API仕様
  - [ ] 画面遷移図
  - [ ] データフロー

#### 11.1.2 API ドキュメント
- [ ] OpenAPI/Swagger スキーマ更新
  - [ ] Thread エンドポイント定義
  - [ ] リクエスト/レスポンス例

### 11.2 ユーザードキュメント

#### 11.2.1 README 更新
- [ ] スレッド機能の説明追加
- [ ] スクリーンショット更新

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
- **対策**: ロールバックスクリプト事前準備、バックアップ必須

### リスク2: 既存会話との互換性
- **対策**: 段階的ロールアウト、フィーチャーフラグ使用

### リスク3: UIパフォーマンス低下
- **対策**: LazyVStack使用、ページネーション実装検討

### リスク4: API変更による既存クライアント影響
- **対策**: API バージョニング、下位互換性維持

---

## 見積もり

### 各フェーズの工数目安
- フェーズ1: データモデル設計 - 4時間
- フェーズ2: バックエンドサービス - 4時間
- フェーズ3: ThreadListView - 4時間
- フェーズ4: CreateThreadView - 3時間
- フェーズ5: ThreadDetailView - 4時間
- フェーズ6: RoomDetailView リファクタリング - 2時間
- フェーズ7: ChatViewModel 更新 - 2時間
- フェーズ8: データマイグレーション - 3時間
- フェーズ9: テスト実装 - 6時間
- フェーズ10: 統合とデバッグ - 4時間
- フェーズ11: ドキュメント更新 - 2時間

**合計**: 約38時間

---

## 次のステップ

1. この計画をレビュー
2. 不明点の確認
3. フェーズ1から順次実装開始
4. 各フェーズ完了時にチェックマーク更新
5. 問題発生時は本ドキュメントに記録

---

**作成日**: 2025-01-20
**バージョン**: 1.0
**作成者**: Claude Code
