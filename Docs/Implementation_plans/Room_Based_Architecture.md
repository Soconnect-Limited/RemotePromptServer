# 実装計画: ルームベース・アーキテクチャ

**作成日**: 2025-11-19
**バージョン**: 1.0
**目的**: メッセンジャー型のルーム機能を実装し、プロジェクトごとに会話履歴とワークスペースを分離する

---

## 概要

### 要件
1. **ルーム（部屋）機能**: プロジェクト/フォルダごとに独立した会話空間
2. **ワークスペース指定**: 各ルームで異なる作業ディレクトリを設定可能
3. **Claude/Codex分離**: 各ルーム内でClaudeタブとCodexタブを用意
4. **サーバー一元管理**: 会話履歴はサーバー側で管理し、iOS側はページングで取得
5. **整合性保証**: データの唯一の情報源（Source of Truth）をサーバー側に統一

### アーキテクチャ概念図

```
iOS App
├─ Rooms List View (部屋一覧)
│   ├─ 📁 RemotePrompt (/Users/.../RemotePrompt)
│   ├─ 📁 AI Trading System (/Users/.../AI_Trading)
│   └─ 📁 Personal Assistant (~)
│
└─ Room Detail View (選択したルーム内)
    ├─ Claude Tab
    │   └─ ChatView (runner="claude", room_id=xxx)
    └─ Codex Tab
        └─ ChatView (runner="codex", room_id=xxx)
```

---

## Phase 1: データベース設計とサーバー側API実装（✅ 完了）

### 1.1 データベーススキーマ設計

#### ✅ 1.1.1 `rooms` テーブル作成
- [x] `models.py` に `Room` モデルを追加
  ```python
  class Room(Base):
      __tablename__ = "rooms"
      id = Column(String(36), primary_key=True)  # UUID
      name = Column(String(100), nullable=False)  # "RemotePrompt"
      workspace_path = Column(String(500), nullable=False)  # "/Users/..."
      icon = Column(String(50), default="folder")  # "folder" or emoji
      device_id = Column(String(100), nullable=False)  # 所有者デバイス
      created_at = Column(DateTime, nullable=False, default=utcnow)
      updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)
  ```

#### ✅ 1.1.2 `device_sessions` テーブルに `room_id` 追加
- [x] `models.py` の `DeviceSession` に `room_id` カラム追加
  ```python
  room_id = Column(String(36), nullable=False)
  __table_args__ = (
      UniqueConstraint("device_id", "room_id", "runner", name="uq_device_room_runner"),
      Index("idx_device_room_runner", "device_id", "room_id", "runner"),
  )
  ```

#### ✅ 1.1.3 `jobs` テーブルに `room_id` 追加
- [x] `models.py` の `Job` に `room_id` カラム追加
  ```python
  room_id = Column(String(36), nullable=False)
  ```
- [x] `to_dict()` メソッドに `room_id` を追加

#### ✅ 1.1.4 マイグレーションスクリプト作成
- [x] `init_db.py` を実行して新スキーマを適用
- [x] 既存データの移行（該当する場合）
  - 既存の `device_sessions` と `jobs` にデフォルトルームIDを割り当て

#### ✅ 1.1.5 ルーム作成の実装方針
- [x] **デフォルトルームは不要**（ユーザーがUI経由でルームを作成）
- [x] `create_default_room.py` は開発/テスト用のユーティリティとして保持
- [x] ユーザーフロー: App Start → Empty RoomsListView → + Button → CreateRoomView → Enter name/path → POST /rooms

---

### 1.2 REST API実装（FastAPI）

#### ✅ 1.2.1 ルーム管理API
- [x] `GET /rooms?device_id={id}`: デバイスの全ルーム取得
  ```python
  @app.get("/rooms")
  async def get_rooms(device_id: str, api_key: str = Header(alias="x-api-key")):
      rooms = db.query(Room).filter_by(device_id=device_id).all()
      return [room.to_dict() for room in rooms]
  ```

- [x] `POST /rooms`: 新規ルーム作成
  ```python
  class CreateRoomRequest(BaseModel):
      device_id: str
      name: str
      workspace_path: str
      icon: str = "folder"

  @app.post("/rooms")
  async def create_room(req: CreateRoomRequest, api_key: str = Header(...)):
      # workspace_path のバリデーション（セキュリティチェック）
      if not is_safe_workspace_path(req.workspace_path):
          raise HTTPException(400, "Invalid workspace path")

      room = Room(id=str(uuid.uuid4()), ...)
      db.add(room)
      db.commit()
      return room.to_dict()
  ```

- [x] `PUT /rooms/{room_id}`: ルーム情報更新（APIClient.swift:updateRoom()で実装済み）
- [x] `DELETE /rooms/{room_id}`: ルーム削除（関連セッション・ジョブも削除）

#### ✅ 1.2.2 メッセージ履歴取得API
- [x] `GET /messages`: ルーム×ランナー別のメッセージ取得
  ```python
  @app.get("/messages")
  async def get_messages(
      device_id: str,
      room_id: str,
      runner: str,  # "claude" or "codex"
      limit: int = 20,
      offset: int = 0,
      api_key: str = Header(alias="x-api-key")
  ):
      jobs = db.query(Job).filter_by(
          device_id=device_id,
          room_id=room_id,
          runner=runner
      ).order_by(Job.created_at.desc()).limit(limit).offset(offset).all()

      return [job.to_dict() for job in reversed(jobs)]
  ```

- [x] ページング対応（limit/offset）
- [x] 降順取得後に反転（最新が下に表示されるよう）

#### ✅ 1.2.3 ジョブ作成APIの拡張
- [x] `POST /jobs` に `room_id` パラメータ追加
  ```python
  class CreateJobRequest(BaseModel):
      runner: str
      prompt: str
      device_id: str
      room_id: str  # 追加
  ```

- [x] バックグラウンドタスクで `room.workspace_path` を `cwd` として渡す
  ```python
  room = db.query(Room).filter_by(id=req.room_id).first()
  result = session_manager.execute_job(
      prompt=req.prompt,
      device_id=req.device_id,
      runner=req.runner,
      room_id=req.room_id,
      workspace_path=room.workspace_path  # 追加
  )
  ```

#### ✅ 1.2.4 セッションクリアAPI
- [x] `DELETE /sessions`: ルーム×ランナー別のセッション削除
  ```python
  @app.delete("/sessions")
  async def delete_session(
      device_id: str,
      room_id: str,
      runner: str,
      api_key: str = Header(alias="x-api-key")
  ):
      db.query(DeviceSession).filter_by(
          device_id=device_id,
          room_id=room_id,
          runner=runner
      ).delete()
      db.commit()
      return {"status": "ok"}
  ```

---

### 1.3 セッションマネージャー拡張（✅ 完了）

#### ✅ 1.3.1 `session_manager.py` の `execute_job` に `workspace_path` 引数追加
- [x] `ClaudeSessionManager.execute_job()` のシグネチャ変更
  ```python
  def execute_job(
      self,
      prompt: str,
      device_id: str,
      runner: str,
      room_id: str,
      workspace_path: str,  # 追加
      continue_session: bool = True,
  ) -> Dict[str, Optional[str]]:
  ```

- [x] `subprocess.run()` の `cwd` パラメータに `workspace_path` を設定
  ```python
  result = subprocess.run(
      cmd,
      input=prompt,
      capture_output=True,
      text=True,
      timeout=300,
      cwd=workspace_path,  # ルームごとの作業ディレクトリ
  )
  ```

#### ✅ 1.3.2 セッションID取得ロジックの拡張
- [x] `_get_session_id_from_db()` に `room_id` を追加
  ```python
  def _get_session_id_from_db(self, device_id: str, room_id: str) -> Optional[str]:
      session = db.query(DeviceSession).filter_by(
          device_id=device_id,
          room_id=room_id,
          runner=self.runner_name
      ).first()
      return session.session_id if session else None
  ```

#### ✅ 1.3.3 セッション保存ロジックの拡張
- [x] `_save_session_id_to_db()` に `room_id` を追加

#### ✅ 1.3.4 `CodexSessionManager` にも同様の変更を適用

---

### 1.4 セキュリティとバリデーション（✅ 完了）

#### ✅ 1.4.1 ワークスペースパスのバリデーション関数
- [x] `utils/path_validator.py` を作成
  ```python
  ALLOWED_BASE_PATHS = [
      "/Users/macstudio/Projects",
      "/Users/macstudio/Documents",
  ]

  def is_safe_workspace_path(path: str) -> bool:
      abs_path = Path(path).resolve()
      return any(
          str(abs_path).startswith(base)
          for base in ALLOWED_BASE_PATHS
      )
  ```

- [x] システムディレクトリへのアクセスを禁止（`/System`, `/Library`, etc.）
- [x] シンボリックリンク攻撃を防ぐため `.resolve()` を使用

#### ✅ 1.4.2 ルーム所有権の検証
- [x] ルーム更新/削除時に `device_id` が一致するか確認
  ```python
  room = db.query(Room).filter_by(id=room_id).first()
  if room.device_id != request_device_id:
      raise HTTPException(403, "Forbidden")
  ```

---

### 1.5 テスト（✅ 完了）

#### ✅ 1.5.1 データベーステスト
- [x] ルーム作成・取得・更新・削除のテスト
- [x] `device_sessions` の一意制約テスト（device_id + room_id + runner）

#### ✅ 1.5.2 APIテスト
- [x] `POST /rooms` でルーム作成
- [x] `GET /messages?room_id=xxx&runner=claude` でメッセージ取得
- [x] `POST /jobs` で異なる `room_id` を指定してジョブ実行
- [x] 作業ディレクトリが正しく設定されているか確認（`pwd` コマンドで検証）

#### ✅ 1.5.3 セキュリティテスト
- [x] 禁止パス（`/System`, `/etc`）へのアクセスが拒否されるか
- [x] 他デバイスのルームにアクセスできないか

---

## Phase 2: iOS側の実装（✅ 完了）

### 2.1 データモデル

#### ✅ 2.1.1 `Room.swift` モデル作成
- [x] `Models/Room.swift` を作成
  ```swift
  struct Room: Identifiable, Codable {
      let id: String
      var name: String
      var workspacePath: String
      var icon: String
      let createdAt: Date
      let updatedAt: Date

      enum CodingKeys: String, CodingKey {
          case id, name, icon
          case workspacePath = "workspace_path"
          case createdAt = "created_at"
          case updatedAt = "updated_at"
      }
  }
  ```

#### ✅ 2.1.2 `Message.swift` に `roomId` 追加
- [x] `room_id` プロパティを追加
- [x] CodingKeys に `roomId = "room_id"` を追加

---

### 2.2 API Client拡張

#### ✅ 2.2.1 ルーム関連API呼び出し
- [x] `APIClient.swift` に以下のメソッド追加
  ```swift
  func fetchRooms(deviceId: String) async throws -> [Room]
  func createRoom(name: String, workspacePath: String, deviceId: String) async throws -> Room
  func updateRoom(roomId: String, name: String, workspacePath: String) async throws -> Room
  func deleteRoom(roomId: String) async throws
  ```

#### ✅ 2.2.2 メッセージ取得API呼び出し
- [x] `fetchMessages()` メソッド追加
  ```swift
  func fetchMessages(
      deviceId: String,
      roomId: String,
      runner: String,
      limit: Int = 20,
      offset: Int = 0
  ) async throws -> [Job]
  ```

#### ✅ 2.2.3 `createJob()` に `roomId` パラメータ追加
- [x] `CreateJobRequest` に `room_id` フィールド追加

---

### 2.3 ViewModels

#### ✅ 2.3.1 `RoomsViewModel.swift` 作成
- [x] ルーム一覧の管理
  ```swift
  @MainActor
  final class RoomsViewModel: ObservableObject {
      @Published var rooms: [Room] = []
      @Published var isLoading = false
      @Published var errorMessage: String?

      private let apiClient = APIClient.shared

      func loadRooms() async {
          // API経由でルーム一覧を取得
      }

      func createRoom(name: String, workspacePath: String) async {
          // 新規ルーム作成
      }

      func deleteRoom(_ room: Room) async {
          // ルーム削除
      }
  }
  ```

#### ✅ 2.3.2 `ChatViewModel.swift` の拡張
- [x] `roomId` プロパティ追加
  ```swift
  private let roomId: String

  init(runner: String, roomId: String) {
      self.runner = runner
      self.roomId = roomId
      loadMessages()
  }
  ```

- [x] `loadMessages()` でサーバーからメッセージ取得
  ```swift
  func loadMessages() async {
      let jobs = try await apiClient.fetchMessages(
          deviceId: APIClient.getDeviceId(),
          roomId: roomId,
          runner: runner,
          limit: 20,
          offset: 0
      )
      // jobs を Message に変換して表示
  }
  ```

- [x] `sendMessage()` で `roomId` を送信
  ```swift
  let response = try await apiClient.createJob(
      runner: runner,
      prompt: prompt,
      deviceId: APIClient.getDeviceId(),
      roomId: roomId  // 追加
  )
  ```

- [x] ページング機能追加（スクロールで過去履歴をロード）
  ```swift
  func loadMoreMessages() async {
      offset += 20
      let olderJobs = try await apiClient.fetchMessages(...)
      messages.insert(contentsOf: olderJobs, at: 0)
  }
  ```

#### ✅ 2.3.3 `MessageStore` の削除または簡素化
- [x] サーバーが情報源となるため、`UserDefaults` への保存を廃止
- [x] または最新10件のみキャッシュする実装に変更

---

### 2.4 Views

#### ✅ 2.4.1 `RoomsListView.swift` 作成（ルーム一覧画面）
- [x] ルーム一覧を表示
  ```swift
  NavigationStack {
      List(viewModel.rooms) { room in
          NavigationLink(value: room) {
              RoomRow(room: room)
          }
      }
      .navigationTitle("Rooms")
      .navigationDestination(for: Room.self) { room in
          RoomDetailView(room: room)
      }
      .toolbar {
          ToolbarItem(placement: .primaryAction) {
              Button("New Room") {
                  showCreateRoomSheet = true
              }
          }
      }
  }
  ```

#### ✅ 2.4.2 `RoomRow.swift` 作成（ルーム行）
- [x] ルーム名、アイコン、パスを表示
  ```swift
  HStack {
      Text(room.icon)
          .font(.title2)
      VStack(alignment: .leading) {
          Text(room.name)
              .font(.headline)
          Text(room.workspacePath)
              .font(.caption)
              .foregroundColor(.secondary)
      }
  }
  ```

#### ✅ 2.4.3 `CreateRoomView.swift` 作成（ルーム作成シート）
- [x] 名前入力フィールド
- [x] ワークスペースパス入力フィールド（または選択UI）
- [x] アイコン選択（絵文字ピッカー）
- [x] 作成ボタン

#### ✅ 2.4.4 `RoomDetailView.swift` 作成（ルーム詳細 = タブUI）
- [x] ClaudeタブとCodexタブを表示
  ```swift
  struct RoomDetailView: View {
      let room: Room

      var body: some View {
          TabView {
              ChatView(viewModel: ChatViewModel(runner: "claude", roomId: room.id))
                  .tabItem { Label("Claude", systemImage: "bubble.left") }

              ChatView(viewModel: ChatViewModel(runner: "codex", roomId: room.id))
                  .tabItem { Label("Codex", systemImage: "chevron.left.forwardslash.chevron.right") }
          }
          .navigationTitle(room.name)
      }
  }
  ```

#### ✅ 2.4.5 `ChatView.swift` の調整
- [x] `ChatViewModel` を外部から注入する形に変更（既存実装を流用）
- [x] ページング実装（スクロール上端到達時に `loadMoreMessages()` を呼び出し）
  ```swift
  ScrollViewReader { proxy in
      ScrollView {
          LazyVStack {
              // ページングトリガー
              if canLoadMore {
                  ProgressView()
                      .onAppear {
                          Task { await viewModel.loadMoreMessages() }
                      }
              }

              ForEach(viewModel.messages) { message in
                  MessageBubble(message: message)
              }
          }
      }
  }
  ```

#### ✅ 2.4.6 `ContentView.swift` のエントリーポイント変更
- [x] `RoomsListView` を最初の画面に設定
  ```swift
  @main
  struct RemotePromptApp: App {
      var body: some Scene {
          WindowGroup {
              RoomsListView()
          }
      }
  }
  ```

---

### 2.5 ローカルデータ移行

#### ✅ 2.5.1 既存の `UserDefaults` データ処理
- [x] `MessageStore.swift` で一度だけ `UserDefaults` からメモリへ移行
- [x] 以降はサーバー側が唯一の情報源（Source of Truth）
- [x] 既存データのサーバーへのアップロード機能は **Phase 2.5.2（未実装）** として残す

#### ☐ 2.5.2 既存メッセージのサーバーアップロード機能（未実装）
- [ ] UI実装: 「過去の履歴をサーバーにアップロード」ボタン
- [ ] 移行ロジック: UserDefaults → POST /jobs で再作成
- [ ] 移行完了後に UserDefaults をクリア

---

### 2.6 テスト（✅ テストコード実装完了）

#### ✅ 2.6.1 UIテスト
**実装ファイル**:
- [RoomBasedArchitectureTests.swift](../../iOS_WatchOS/RemotePrompt/RemotePromptTests/RoomBasedArchitectureTests.swift) (モデル/ロジック)
- [RoomBasedArchitectureUITests.swift](../../iOS_WatchOS/RemotePrompt/RemotePromptUITests/RoomBasedArchitectureUITests.swift) (UI E2E)

**完了項目**:
- [x] Room/Job/Messageモデルのデータ構造テスト & Codable検証
- [x] RoomsListViewの表示/ナビゲーションタイトル検証
- [x] ルーム作成ボタンの有効性検証
- [x] ルーム作成フロー（入力→保存→一覧反映）の自動テスト
- [x] RoomDetailViewでのClaude/Codexタブ切り替えテスト
- [x] ChatViewでの送信→レスポンス表示（room_id紐づけ）テスト

#### ✅ 2.6.2 ページングテスト
**完了項目**:
- [x] ChatViewModelの初期ページング状態テスト（モックAPI/AutoLoad制御）
- [x] ページングオフセット計算ロジックテスト（limit/offsetシミュレーション）
- [x] Jobs→Messages変換テスト（ユーザー/アシスタントペア確認）
- [x] canLoadMoreHistory状態管理テスト
- [ ] Scroll/Pull-to-RefreshのUI統合テスト（ハードウェアスクロールイベントの自動化はPhase3で対応）

#### ✅ 2.6.3 整合性テスト
**完了項目**:
- [x] RoomsViewModelの初期状態テスト
- [x] MessageStoreのコンテキスト切り替えテスト (room_id + runner単位)
- [x] MessageStoreの全置換機能テスト (replaceAll)
- [x] MessageStoreのクリア機能テスト
- [x] DeviceID永続化テスト (UserDefaults)
- [ ] サーバー側セッションクリア統合テスト (プレースホルダー: APIモッキングが必要)

**テスト実装サマリー**:
- 単体テスト: 11テストケース実装
- UIテスト: 5テストケース (全て実装済み)
- 詳細レポート: [Phase_2_6_Test_Report.md](../../Tests/Phase_2_6_Test_Report.md)

**今後の拡張予定**:
- Scroll/Pull-to-RefreshのUIテスト (Phase 3で実装)
- SSEストリーミング統合テスト (Phase 3で実装)

---

## Phase 3: watchOS対応（オプション）

#### ☐ 3.1 watchOS用の簡易版ルーム選択UI
- [ ] ルーム一覧を表示（最大5件程度）
- [ ] 選択したルームでメッセージ送信

#### ☐ 3.2 Handoff対応
- [ ] iPhoneで開いているルームをwatchOSで継続

---

## Phase 4: パフォーマンス最適化

#### ☐ 4.1 サーバー側キャッシング
- [ ] Redis導入でメッセージ取得を高速化（オプション）

#### ☐ 4.2 iOS側のメモリ管理
- [ ] 古いメッセージを自動的にアンロード
- [ ] 画像添付対応（将来）時のサムネイル生成

---

## Phase 5: ドキュメント更新

#### ☐ 5.1 `Docs/MASTER_SPECIFICATION.md` 更新
- [ ] ルーム機能のアーキテクチャ図追加
- [ ] API仕様書更新

#### ☐ 5.2 `README.md` 更新
- [ ] 新機能の説明追加
- [ ] スクリーンショット追加

---

## リスクと対策

### リスク1: パス指定の脆弱性
- **対策**: ホワイトリスト方式でパスを検証、シンボリックリンク解決

### リスク2: データベースマイグレーション失敗
- **対策**: 既存データのバックアップ、ロールバック手順の準備

### リスク3: iOS側のページング実装が複雑
- **対策**: シンプルなプロトタイプから開始、段階的に改善

---

## 完了条件

- [x] **Phase 1 (サーバー側)**: 完了
- [x] **Phase 2 (iOS側)**: Phase 2.1 ~ 2.6 完了
- [x] **Phase 2.6 (テスト)**: 完了 (単体11件 + UI5件)
- [x] **ドキュメント**: 最新化完了
- [ ] **Phase 2.5.2 (履歴アップロード)**: 未実装（オプション、Phase 3で検討）

---

## 次のステップ

### 完了済み
- ✅ Phase 1: データベース設計とサーバー側API実装
- ✅ Phase 2.1 ~ 2.4: iOS側のUI実装（Room一覧、作成、詳細、チャット）
- ✅ Phase 2.5.1: UserDefaultsからメモリへの移行
- ✅ Phase 2.6: テスト実装（単体11件 + UI5件、全て自動実行可能）

### 残タスク（優先度順）
1. **Phase 2.5.2**: 既存メッセージのサーバーアップロード機能（オプション）
2. **Phase 3**: Scroll/Pull-to-RefreshテストとSSE統合テスト拡張
3. **Phase 4**: watchOS対応（オプション）
4. **Phase 5**: パフォーマンス最適化（オプション）
5. **Phase 6**: ドキュメント更新（README.md、スクリーンショット）
