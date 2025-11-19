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

#### ✅ 1.1.5 デフォルトルーム作成スクリプト
- [x] `create_default_room.py` を作成
  ```python
  def create_default_room(device_id: str, name="RemotePrompt"):
      room = Room(
          id=str(uuid.uuid4()),
          name=name,
          workspace_path="/Users/macstudio/Projects/RemotePrompt",
          device_id=device_id,
      )
      db.add(room)
      db.commit()
  ```

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

- [ ] `PUT /rooms/{room_id}`: ルーム情報更新（未実装）
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

## Phase 2: iOS側の実装

### 2.1 データモデル

#### ☐ 2.1.1 `Room.swift` モデル作成
- [ ] `Models/Room.swift` を作成
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

#### ☐ 2.1.2 `Message.swift` に `roomId` 追加
- [ ] `room_id` プロパティを追加
- [ ] CodingKeys に `roomId = "room_id"` を追加

---

### 2.2 API Client拡張

#### ☐ 2.2.1 ルーム関連API呼び出し
- [ ] `APIClient.swift` に以下のメソッド追加
  ```swift
  func fetchRooms(deviceId: String) async throws -> [Room]
  func createRoom(name: String, workspacePath: String, deviceId: String) async throws -> Room
  func updateRoom(roomId: String, name: String, workspacePath: String) async throws -> Room
  func deleteRoom(roomId: String) async throws
  ```

#### ☐ 2.2.2 メッセージ取得API呼び出し
- [ ] `fetchMessages()` メソッド追加
  ```swift
  func fetchMessages(
      deviceId: String,
      roomId: String,
      runner: String,
      limit: Int = 20,
      offset: Int = 0
  ) async throws -> [Job]
  ```

#### ☐ 2.2.3 `createJob()` に `roomId` パラメータ追加
- [ ] `CreateJobRequest` に `room_id` フィールド追加

---

### 2.3 ViewModels

#### ☐ 2.3.1 `RoomsViewModel.swift` 作成
- [ ] ルーム一覧の管理
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

#### ☐ 2.3.2 `ChatViewModel.swift` の拡張
- [ ] `roomId` プロパティ追加
  ```swift
  private let roomId: String

  init(runner: String, roomId: String) {
      self.runner = runner
      self.roomId = roomId
      loadMessages()
  }
  ```

- [ ] `loadMessages()` でサーバーからメッセージ取得
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

- [ ] `sendMessage()` で `roomId` を送信
  ```swift
  let response = try await apiClient.createJob(
      runner: runner,
      prompt: prompt,
      deviceId: APIClient.getDeviceId(),
      roomId: roomId  // 追加
  )
  ```

- [ ] ページング機能追加（スクロールで過去履歴をロード）
  ```swift
  func loadMoreMessages() async {
      offset += 20
      let olderJobs = try await apiClient.fetchMessages(...)
      messages.insert(contentsOf: olderJobs, at: 0)
  }
  ```

#### ☐ 2.3.3 `MessageStore` の削除または簡素化
- [ ] サーバーが情報源となるため、`UserDefaults` への保存を廃止
- [ ] または最新10件のみキャッシュする実装に変更

---

### 2.4 Views

#### ☐ 2.4.1 `RoomsListView.swift` 作成（ルーム一覧画面）
- [ ] ルーム一覧を表示
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

#### ☐ 2.4.2 `RoomRow.swift` 作成（ルーム行）
- [ ] ルーム名、アイコン、パスを表示
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

#### ☐ 2.4.3 `CreateRoomView.swift` 作成（ルーム作成シート）
- [ ] 名前入力フィールド
- [ ] ワークスペースパス入力フィールド（または選択UI）
- [ ] アイコン選択（絵文字ピッカー）
- [ ] 作成ボタン

#### ☐ 2.4.4 `RoomDetailView.swift` 作成（ルーム詳細 = タブUI）
- [ ] ClaudeタブとCodexタブを表示
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

#### ☐ 2.4.5 `ChatView.swift` の調整
- [ ] `ChatViewModel` を外部から注入する形に変更（既存実装を流用）
- [ ] ページング実装（スクロール上端到達時に `loadMoreMessages()` を呼び出し）
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

#### ☐ 2.4.6 `ContentView.swift` のエントリーポイント変更
- [ ] `RoomsListView` を最初の画面に設定
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

#### ☐ 2.5.1 既存の `UserDefaults` データをサーバーに移行
- [ ] 移行スクリプトまたはUIを作成
- [ ] 初回起動時に `UserDefaults` からメッセージを読み込み
- [ ] デフォルトルームを作成して既存メッセージを関連付け
- [ ] 移行完了後に `UserDefaults` をクリア

---

### 2.6 テスト

#### ☐ 2.6.1 UIテスト
- [ ] ルーム一覧画面が表示されるか
- [ ] 新規ルームを作成できるか
- [ ] ルーム詳細でClaudeタブとCodexタブが切り替わるか
- [ ] メッセージ送信がルームIDと紐づいているか確認

#### ☐ 2.6.2 ページングテスト
- [ ] 初回ロード時に最新20件が表示されるか
- [ ] スクロール上端で過去履歴が追加ロードされるか
- [ ] ロード中にProgressViewが表示されるか

#### ☐ 2.6.3 整合性テスト
- [ ] iOS側で履歴クリア後、サーバー側の履歴が残っているか
- [ ] サーバー側でセッションクリア後、iOS側が再ロードするか

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

- [ ] 全てのチェックボックスが完了
- [ ] ユニットテスト・統合テストが全てパス
- [ ] ドキュメントが最新化されている
- [ ] ユーザー受け入れテストが完了

---

## 次のステップ

1. **Phase 1.1 ~ 1.2 の実装開始**: データベーススキーマとAPI実装
2. **動作確認**: curl でAPIテスト
3. **Phase 2.1 ~ 2.4 の実装**: iOS側のUI実装
4. **統合テスト**: iOS ↔ サーバー間の疎通確認
