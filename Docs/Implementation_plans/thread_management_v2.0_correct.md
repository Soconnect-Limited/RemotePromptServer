# スレッド管理機能 実装計画 v2.0（現行仕様完全適合版）

## 概要

**目的**: 現行のRoom-Based Architecture (v3.0) にThread層を追加し、Room内で複数の会話スレッドを管理可能にする

**現行構造**:
- Room → Jobs (直接) - セッション管理: `(device_id, room_id, runner)`

**新構造**:
- Room → Thread → Jobs - セッション管理: `(device_id, room_id, runner, thread_id)`

**重要な設計方針**:
1. **現行仕様との完全互換性**: 既存クライアント・APIとの互換性を維持
2. **段階的導入**: スキーマ→API→クライアントの順で、各段階で動作確認
3. **セッション分離の4次元化**: `thread_id`軸追加によるセッション衝突回避
4. **認証ポリシー統一**: 全APIで`x-api-key` + room/device所有チェック必須
5. **デフォルトスレッド方式**: 互換性のため、thread_id未指定時はデフォルトスレッドにフォールバック

---

## データモデル設計

### 現行スキーマ (v3.0)

```sql
-- rooms
CREATE TABLE rooms (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    workspace_path TEXT NOT NULL,
    icon TEXT,
    device_id TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

-- jobs
CREATE TABLE jobs (
    id TEXT PRIMARY KEY,
    runner TEXT NOT NULL,
    input_text TEXT NOT NULL,
    device_id TEXT NOT NULL,
    room_id TEXT,  -- v3.0で追加
    status TEXT NOT NULL,
    stdout TEXT,
    stderr TEXT,
    created_at DATETIME NOT NULL,
    finished_at DATETIME,
    FOREIGN KEY (room_id) REFERENCES rooms(id)
);

-- device_sessions
CREATE TABLE device_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    room_id TEXT NOT NULL,  -- v3.0で追加
    runner TEXT NOT NULL,
    session_id TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE(device_id, room_id, runner)  -- 3次元で一意
);

-- devices
CREATE TABLE devices (
    id TEXT PRIMARY KEY,
    device_token TEXT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);
```

### 新スキーマ (v4.0: Thread対応)

```sql
-- threads (新規)
CREATE TABLE threads (
    id TEXT PRIMARY KEY,  -- UUID
    room_id TEXT NOT NULL,
    name TEXT NOT NULL DEFAULT '無題',
    runner TEXT NOT NULL,  -- 'claude' or 'codex'
    device_id TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
);

-- jobs (拡張)
ALTER TABLE jobs ADD COLUMN thread_id TEXT;
-- 後でNOT NULL制約を追加（マイグレーション完了後）

-- device_sessions (拡張)
-- 既存: UNIQUE(device_id, room_id, runner)
-- 新規: UNIQUE(device_id, room_id, runner, thread_id)
-- マイグレーション: 既存レコードにthread_idを追加してから制約変更

-- 新しいdevice_sessions
CREATE TABLE device_sessions_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    runner TEXT NOT NULL,
    thread_id TEXT NOT NULL,  -- 追加
    session_id TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE(device_id, room_id, runner, thread_id),  -- 4次元で一意
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
);
```

---

## フェーズ1: データベースマイグレーション

### 1.1 マイグレーションスクリプト作成

#### 1.1.1 マイグレーション前の準備
- [ ] バックアップ作成
  ```bash
  cp remote-job-server/remote_jobs.db remote-job-server/remote_jobs_backup_$(date +%Y%m%d_%H%M%S).db
  ```

- [ ] 既存データ確認
  ```sql
  SELECT COUNT(*) FROM rooms;
  SELECT COUNT(*) FROM jobs;
  SELECT COUNT(*) FROM device_sessions;
  ```

#### 1.1.2 マイグレーションスクリプト実装
- [ ] `remote-job-server/migrations/v3_to_v4_threads.py` 作成

```python
"""
v3.0 → v4.0 マイグレーション: Thread層追加
"""
import sqlite3
import uuid
from datetime import datetime, timezone

def migrate_v3_to_v4(db_path: str):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. threadsテーブル作成
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS threads (
            id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT '無題',
            runner TEXT NOT NULL,
            device_id TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
        )
    """)

    # 2. 各Room×Runnerごとにデフォルトスレッド生成
    cursor.execute("""
        SELECT DISTINCT r.id, r.device_id, 'claude' as runner
        FROM rooms r
        UNION
        SELECT DISTINCT r.id, r.device_id, 'codex' as runner
        FROM rooms r
    """)

    default_threads = {}
    for room_id, device_id, runner in cursor.fetchall():
        thread_id = str(uuid.uuid4())
        thread_name = f"{runner.title()} 会話"
        now = datetime.now(timezone.utc).isoformat()

        cursor.execute("""
            INSERT INTO threads (id, room_id, name, runner, device_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (thread_id, room_id, thread_name, runner, device_id, now, now))

        default_threads[(room_id, runner)] = thread_id

    # 3. jobsテーブルにthread_id追加
    cursor.execute("ALTER TABLE jobs ADD COLUMN thread_id TEXT")

    # 4. 既存jobsにthread_id割り当て
    cursor.execute("SELECT id, room_id, runner FROM jobs WHERE room_id IS NOT NULL")
    for job_id, room_id, runner in cursor.fetchall():
        thread_id = default_threads.get((room_id, runner))
        if thread_id:
            cursor.execute("UPDATE jobs SET thread_id = ? WHERE id = ?", (thread_id, job_id))

    # 5. device_sessionsを新スキーマに移行
    cursor.execute("""
        CREATE TABLE device_sessions_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            runner TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            UNIQUE(device_id, room_id, runner, thread_id),
            FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
        )
    """)

    cursor.execute("SELECT device_id, room_id, runner, session_id, created_at, updated_at FROM device_sessions")
    for device_id, room_id, runner, session_id, created_at, updated_at in cursor.fetchall():
        thread_id = default_threads.get((room_id, runner))
        if thread_id:
            cursor.execute("""
                INSERT INTO device_sessions_new
                (device_id, room_id, runner, thread_id, session_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (device_id, room_id, runner, thread_id, session_id, created_at, updated_at))

    cursor.execute("DROP TABLE device_sessions")
    cursor.execute("ALTER TABLE device_sessions_new RENAME TO device_sessions")

    conn.commit()
    conn.close()
    print("✅ Migration completed successfully")

if __name__ == "__main__":
    migrate_v3_to_v4("remote_jobs.db")
```

#### 1.1.3 ロールバックスクリプト
- [ ] `remote-job-server/migrations/v4_to_v3_rollback.py` 作成
- [ ] threads削除、jobs.thread_id削除、device_sessionsを3次元に戻す

#### 1.1.4 マイグレーション実行
- [ ] テストDBで動作確認
- [ ] 本番DB実行前に再バックアップ
- [ ] マイグレーション実行
- [ ] データ整合性確認

---

## フェーズ2: モデル層更新

### 2.1 SQLAlchemyモデル更新

#### 2.1.1 Thread モデル追加
- [ ] `remote-job-server/models.py` に Thread クラス追加

```python
class Thread(Base):
    __tablename__ = "threads"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String, ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    name = Column(String, nullable=False, default="無題")
    runner = Column(String, nullable=False)  # 'claude' or 'codex'
    device_id = Column(String, nullable=False)
    created_at = Column(DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, nullable=False, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    # リレーション
    room = relationship("Room", back_populates="threads")
    jobs = relationship("Job", back_populates="thread", cascade="all, delete-orphan")
```

#### 2.1.2 Room モデル更新
- [ ] Room に threads リレーション追加

```python
class Room(Base):
    # 既存フィールド...
    threads = relationship("Thread", back_populates="room", cascade="all, delete-orphan")
```

#### 2.1.3 Job モデル更新
- [ ] Job に thread_id フィールド追加

```python
class Job(Base):
    # 既存フィールド...
    thread_id = Column(String, ForeignKey("threads.id"), nullable=True)  # 互換性のため初期はnullable

    # リレーション
    thread = relationship("Thread", back_populates="jobs")
```

#### 2.1.4 DeviceSession モデル更新
- [ ] device_sessions の UNIQUE制約を4次元に変更

```python
class DeviceSession(Base):
    # 既存フィールド...
    thread_id = Column(String, ForeignKey("threads.id", ondelete="CASCADE"), nullable=False)

    __table_args__ = (
        UniqueConstraint('device_id', 'room_id', 'runner', 'thread_id', name='_device_room_runner_thread_uc'),
    )
```

---

## フェーズ3: API設計（現行仕様準拠）

### 3.1 認証ポリシー統一

**全Thread系APIの共通仕様**:
- Header: `x-api-key` 必須
- Query: `device_id` 必須
- 権限チェック: room所有確認 (room.device_id == request device_id)

### 3.2 Thread API エンドポイント

#### 3.2.1 GET /rooms/{room_id}/threads
- [ ] エンドポイント実装

**リクエスト**:
```
GET /rooms/{room_id}/threads?device_id=iphone-nao-1
Headers:
  x-api-key: your-api-key
```

**レスポンス**:
```json
[
  {
    "id": "thread-uuid-1",
    "room_id": "room-uuid",
    "name": "Claude 会話",
    "runner": "claude",
    "created_at": "2025-01-20T10:00:00Z",
    "updated_at": "2025-01-20T12:30:00Z"
  },
  ...
]
```

**処理フロー**:
1. x-api-key検証
2. room存在確認
3. room.device_id == query device_id 確認
4. threadsをupdated_at DESCでソート
5. 返却

#### 3.2.2 POST /rooms/{room_id}/threads
- [ ] エンドポイント実装

**リクエスト**:
```
POST /rooms/{room_id}/threads?device_id=iphone-nao-1
Headers:
  x-api-key: your-api-key
Body:
{
  "name": "新しい会話",
  "runner": "claude"
}
```

**バリデーション**:
- runner: "claude" | "codex"
- name: 1-100文字

**レスポンス**:
```json
{
  "id": "thread-uuid-new",
  "room_id": "room-uuid",
  "name": "新しい会話",
  "runner": "claude",
  "created_at": "2025-01-20T13:00:00Z",
  "updated_at": "2025-01-20T13:00:00Z"
}
```

#### 3.2.3 PATCH /threads/{thread_id}
- [ ] エンドポイント実装

**リクエスト**:
```
PATCH /threads/{thread_id}?device_id=iphone-nao-1
Headers:
  x-api-key: your-api-key
Body:
{
  "name": "編集後の名前"
}
```

**権限チェック**:
1. threadからroom取得
2. room.device_id == query device_id 確認

#### 3.2.4 DELETE /threads/{thread_id}
- [ ] エンドポイント実装

**リクエスト**:
```
DELETE /threads/{thread_id}?device_id=iphone-nao-1
Headers:
  x-api-key: your-api-key
```

**カスケード削除**: jobs, device_sessions

---

## フェーズ4: 既存API拡張（互換性維持）

### 4.1 POST /jobs 拡張

#### 4.1.1 互換モード実装
- [ ] リクエストボディに `thread_id` (optional) 追加
- [ ] thread_id未指定時: デフォルトスレッド取得ロジック

**新リクエスト**:
```json
{
  "runner": "claude",
  "input_text": "質問",
  "device_id": "iphone-nao-1",
  "room_id": "room-uuid",
  "thread_id": "thread-uuid"  // オプショナル
}
```

**デフォルトスレッド取得ロジック**:
```python
def get_default_thread(room_id: str, runner: str, db: Session) -> Thread:
    """
    互換性のため、thread_id未指定時はデフォルトスレッドを返す
    """
    # 該当room×runnerの最古スレッド（マイグレーションで生成されたもの）
    thread = db.query(Thread).filter(
        Thread.room_id == room_id,
        Thread.runner == runner
    ).order_by(Thread.created_at.asc()).first()

    if not thread:
        # 存在しない場合は新規作成
        thread = Thread(
            room_id=room_id,
            runner=runner,
            name=f"{runner.title()} 会話",
            device_id=get_room_device_id(room_id, db)
        )
        db.add(thread)
        db.commit()

    return thread
```

#### 4.1.2 セッション管理更新
- [ ] SessionManager を4次元セッション対応に変更

**変更前**:
```python
session_id = get_session(device_id, room_id, runner)
```

**変更後**:
```python
session_id = get_session(device_id, room_id, runner, thread_id)
```

### 4.2 GET /messages 拡張

#### 4.2.1 thread_id パラメータ追加
- [ ] Query に `thread_id` (optional) 追加

**新リクエスト**:
```
GET /messages?room_id=room-uuid&runner=claude&thread_id=thread-uuid&device_id=iphone-nao-1
Headers:
  x-api-key: your-api-key
```

**互換性**:
- thread_id未指定: 全スレッドのjobsを返す（既存動作維持）
- thread_id指定: 該当スレッドのjobsのみ

---

## フェーズ5: iOS クライアント実装

### 5.1 モデル追加

#### 5.1.1 Thread.swift
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Models/Thread.swift` 作成

```swift
struct Thread: Identifiable, Codable, Hashable {
    let id: String
    let roomId: String
    let name: String
    let runner: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, runner
        case roomId = "room_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

### 5.2 ThreadService

#### 5.2.1 ThreadService.swift
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/ThreadService.swift` 作成

```swift
final class ThreadService {
    private let apiClient: APIClientProtocol

    func listThreads(roomId: String, deviceId: String) async throws -> [Thread] {
        // GET /rooms/{roomId}/threads?device_id={deviceId}
    }

    func createThread(roomId: String, name: String, runner: String, deviceId: String) async throws -> Thread {
        // POST /rooms/{roomId}/threads
    }

    func updateThread(threadId: String, name: String, deviceId: String) async throws -> Thread {
        // PATCH /threads/{threadId}
    }

    func deleteThread(threadId: String, deviceId: String) async throws {
        // DELETE /threads/{threadId}
    }
}
```

### 5.3 ThreadListViewModel

#### 5.3.1 ViewModel実装
- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ThreadListViewModel.swift` 作成

```swift
@MainActor
final class ThreadListViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let room: Room
    private let threadService: ThreadService
    private let deviceId: String

    func loadThreads() async { ... }
    func createThread(name: String, runner: String) async -> Thread? { ... }
    func updateThreadName(threadId: String, name: String) async -> Bool { ... }
    func deleteThread(_ thread: Thread) async -> Bool { ... }
}
```

### 5.4 UI Components

#### 5.4.1 ThreadListView.swift
- [ ] スレッド一覧表示
- [ ] NavigationLink to ChatView
- [ ] Empty state
- [ ] Pull to refresh

#### 5.4.2 CreateThreadView.swift
- [ ] Sheet presentation
- [ ] Form (name, runner picker)
- [ ] Validation
- [ ] Create button

#### 5.4.3 EditThreadNameView.swift
- [ ] Sheet presentation
- [ ] TextField (focused)
- [ ] Save button

### 5.5 RoomDetailView リファクタリング

#### 5.5.1 タブ削除
- [ ] RunnerTab enum 削除
- [ ] claude/codex ViewModel 削除
- [ ] Picker UI 削除

#### 5.5.2 ThreadListView 埋め込み
- [ ] body: ThreadListView(room: room)

#### 5.5.3 ツールバー再配置
- [ ] FileBrowser button → .navigationBarLeading
- [ ] Create Thread button → .primaryAction

### 5.6 ChatViewModel 更新

#### 5.6.1 thread 対応
- [ ] let thread: Thread 追加
- [ ] init(thread: Thread) に変更
- [ ] runner = thread.runner (固定)
- [ ] POST /jobs に thread_id 含める
- [ ] GET /messages に thread_id 含める

---

## フェーズ6: テスト実装

### 6.1 バックエンドテスト

#### 6.1.1 マイグレーションテスト
- [ ] 空DBでのマイグレーション
- [ ] 既存データありでのマイグレーション
- [ ] ロールバック動作確認

#### 6.1.2 Thread API テスト
- [ ] test_list_threads
- [ ] test_create_thread
- [ ] test_update_thread
- [ ] test_delete_thread
- [ ] test_cascade_delete
- [ ] test_unauthorized_access

#### 6.1.3 互換性テスト
- [ ] POST /jobs (thread_id未指定)
- [ ] POST /jobs (thread_id指定)
- [ ] GET /messages (thread_id未指定)
- [ ] GET /messages (thread_id指定)

### 6.2 iOSテスト

#### 6.2.1 単体テスト
- [ ] ThreadService tests
- [ ] ThreadListViewModel tests

#### 6.2.2 UIテスト
- [ ] ThreadList navigation
- [ ] Thread creation
- [ ] Thread name edit
- [ ] Thread deletion

---

## フェーズ7: 段階的デプロイ

### 7.1 Phase A: バックエンドデプロイ（互換モードON）

#### 7.1.1 デプロイ前確認
- [ ] 全テストパス
- [ ] マイグレーション実行
- [ ] 互換モード有効確認

#### 7.1.2 デプロイ
- [ ] サーバー再起動
- [ ] 既存クライアントで動作確認（thread_id未指定）
- [ ] ログ監視

### 7.2 Phase B: iOSクライアント更新

#### 7.2.1 段階的ロールアウト
- [ ] TestFlight配信
- [ ] ベータテスト
- [ ] 本番リリース

#### 7.2.2 動作確認
- [ ] Thread作成・一覧・編集・削除
- [ ] セッション継続
- [ ] マルチスレッド会話

### 7.3 Phase C: 互換モード無効化（オプション）

#### 7.3.1 全クライアント更新後
- [ ] thread_id必須化
- [ ] デフォルトスレッドロジック削除
- [ ] API仕様書更新

---

## ドキュメント更新

### MASTER_SPECIFICATION.md 更新

#### セクション追加
- [ ] **v4.0: Thread Management**
  - データモデル図 (Room → Thread → Job)
  - セッション管理 4次元 (device_id, room_id, runner, thread_id)
  - API仕様 (Thread CRUD)
  - 互換性ポリシー
  - マイグレーション手順

#### データフロー図更新
```
1. iPhone → POST /jobs {runner, input_text, device_id, room_id, thread_id}
2. Server → thread存在確認
3. Server → Job DB保存 (thread_id含む)
4. Session Manager → (device_id, room_id, runner, thread_id) でセッション取得
5. subprocess.run(['claude', '--print', '--resume', session_id], cwd=workspace_path)
6. Session Manager → device_sessions更新 (4次元)
7. Job DB更新
8. APNs通知
```

---

## リスク管理

### リスク1: マイグレーション失敗
**対策**:
- 複数世代バックアップ
- テストDB先行実行
- ロールバックスクリプト準備

### リスク2: セッション混線
**対策**:
- 4次元UNIQUE制約で排他制御
- 統合テストで並行実行確認

### リスク3: 既存クライアント互換性
**対策**:
- 互換モード実装
- 段階的デプロイ
- モニタリング強化

### リスク4: パフォーマンス劣化
**対策**:
- thread_id, room_id にインデックス
- N+1クエリ回避

---

## 工数見積もり

| フェーズ | 内容 | 工数 |
|---------|------|------|
| 1 | マイグレーション | 6h |
| 2 | モデル層更新 | 3h |
| 3 | Thread API実装 | 5h |
| 4 | 既存API拡張 | 4h |
| 5 | iOSクライアント | 12h |
| 6 | テスト実装 | 8h |
| 7 | 段階的デプロイ | 4h |
| ドキュメント | MASTER_SPEC更新 | 2h |

**合計**: 約44時間

---

## 完了基準

### Phase A完了
- [ ] マイグレーション成功
- [ ] Thread API全エンドポイント動作
- [ ] 既存クライアント動作確認（互換モード）
- [ ] 全バックエンドテストパス

### Phase B完了
- [ ] iOS Thread機能実装
- [ ] UIテストパス
- [ ] TestFlight動作確認

### 全体完了
- [ ] 本番環境デプロイ
- [ ] マルチスレッド会話動作確認
- [ ] ドキュメント更新
- [ ] パフォーマンス基準クリア

---

**作成日**: 2025-01-20
**バージョン**: 2.0 (現行仕様v3.0完全適合版)
**作成者**: Claude Code

---

## 次のステップ

1. この計画をレビュー
2. フェーズ1（マイグレーション）から着手
3. 各フェーズ完了時にチェックマーク更新
4. 問題発生時は本ドキュメントに記録し、MASTER_SPECIFICATIONに反映
