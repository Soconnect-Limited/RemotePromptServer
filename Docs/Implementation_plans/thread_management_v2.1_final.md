# スレッド管理機能 実装計画 v2.1 Final（運用考慮版）

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
6. **明示的な互換モード管理**: 環境変数フラグ + ログ観測で移行状態を可視化
7. **性能最適化**: インデックス設計とON DELETE CASCADE検証

## 進捗チェック (v2.1 修正分)

- [x] jobsスキーマを現行実装（models.py）と一致させた（exit_code / started_at / notify_token 追加、room_id NOT NULL）
- [x] v4→v3ロールバック仕様に exit_code / started_at / notify_token を反映
- [x] v4.0→v4.1マイグレーション仕様を現行スキーマ全列に揃えた
- [x] 実コードのマイグレーションスクリプト実装（Codexにより完了）
- [x] DBは既にv4.0に移行済み（threads table, jobs.thread_id, device_sessions 4D構造）
- [x] Thread APIエンドポイント実装完了（GET/POST/PATCH/DELETE）
- [x] 互換モード実装完了（POST /jobs, GET /messages）
- [x] config.py threads_compat_mode設定追加完了
- [x] SessionManager 4次元対応完了
- [x] 動作テスト完了（Thread作成・一覧・更新）
- [x] **フェーズ5: iOSクライアント実装完了** ✅
  - [x] Thread.swift モデル定義
  - [x] APIClient Thread管理メソッド実装
  - [x] ThreadListViewModel 実装
  - [x] ThreadListView / CreateThreadView / EditThreadNameView 実装
  - [x] RoomDetailView リファクタリング（Thread一覧→Chat画面遷移）
  - [x] ChatViewModel threadId対応
  - [x] Xcodeビルド成功確認

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
    room_id TEXT NOT NULL,  -- v3.0で追加（NOT NULL）
    status TEXT NOT NULL,
    exit_code INTEGER,
    stdout TEXT,
    stderr TEXT,
    started_at DATETIME,
    finished_at DATETIME,
    notify_token TEXT,
    created_at DATETIME NOT NULL,
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

-- インデックス設計
CREATE INDEX idx_threads_room_runner ON threads(room_id, runner);
CREATE INDEX idx_threads_updated_at ON threads(updated_at DESC);

-- jobs (拡張)
ALTER TABLE jobs ADD COLUMN thread_id TEXT;
-- 互換モード期間中はNULL許可
-- Phase C完了後にNOT NULL化（v4.1移行）

-- インデックス設計
CREATE INDEX idx_jobs_thread_id ON jobs(thread_id);
CREATE INDEX idx_jobs_room_thread ON jobs(room_id, thread_id);

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

-- インデックス設計
CREATE INDEX idx_device_sessions_lookup ON device_sessions_new(device_id, room_id, runner, thread_id);
```

---

## フェーズ1: データベースマイグレーション

### 1.1 マイグレーションスクリプト作成

#### 1.1.1 マイグレーション前の準備
- [x] バックアップ作成（マイグレーション実行済み）
  ```bash
  cp remote-job-server/remote_jobs.db remote-job-server/remote_jobs_backup_$(date +%Y%m%d_%H%M%S).db
  ```

- [x] 既存データ確認（実行済み）
  ```sql
  SELECT COUNT(*) FROM rooms;
  SELECT COUNT(*) FROM jobs;
  SELECT COUNT(*) FROM device_sessions;
  ```

#### 1.1.2 マイグレーションスクリプト実装
- [x] `remote-job-server/migrations/v3_to_v4_threads.py` 作成（Codexにより完了）

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

    # インデックス作成
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_threads_room_runner ON threads(room_id, runner)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_threads_updated_at ON threads(updated_at DESC)")

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

    # インデックス作成
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_thread_id ON jobs(thread_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_room_thread ON jobs(room_id, thread_id)")

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

    # インデックス作成
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_device_sessions_lookup ON device_sessions_new(device_id, room_id, runner, thread_id)")

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
    print("✅ Migration v3→v4 completed successfully")

if __name__ == "__main__":
    migrate_v3_to_v4("remote_jobs.db")
```

#### 1.1.3 ロールバックスクリプト
- [x] `remote-job-server/migrations/v4_to_v3_rollback.py` 作成（Codexにより完了）

```python
"""
v4.0 → v3.0 ロールバック
"""
import sqlite3

def rollback_v4_to_v3(db_path: str):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. jobs.thread_id削除（現行スキーマ全列保持）
    cursor.execute("""
        CREATE TABLE jobs_temp AS
        SELECT id, runner, input_text, device_id, room_id, status, exit_code, stdout, stderr, started_at, finished_at, notify_token, created_at
        FROM jobs
    """)
    cursor.execute("DROP TABLE jobs")
    cursor.execute("ALTER TABLE jobs_temp RENAME TO jobs")

    # 2. device_sessionsを3次元に戻す
    cursor.execute("""
        CREATE TABLE device_sessions_old (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            runner TEXT NOT NULL,
            session_id TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            UNIQUE(device_id, room_id, runner)
        )
    """)

    # 最新のセッションのみ保持
    cursor.execute("""
        INSERT INTO device_sessions_old (device_id, room_id, runner, session_id, created_at, updated_at)
        SELECT device_id, room_id, runner, session_id, created_at, updated_at
        FROM device_sessions
        WHERE id IN (
            SELECT MAX(id) FROM device_sessions GROUP BY device_id, room_id, runner
        )
    """)

    cursor.execute("DROP TABLE device_sessions")
    cursor.execute("ALTER TABLE device_sessions_old RENAME TO device_sessions")

    # 3. threadsテーブル削除
    cursor.execute("DROP TABLE threads")

    conn.commit()
    conn.close()
    print("✅ Rollback v4→v3 completed successfully")

if __name__ == "__main__":
    rollback_v4_to_v3("remote_jobs.db")
```

#### 1.1.4 マイグレーション実行
- [x] テストDBで動作確認（完了）
- [x] 本番DB実行前に再バックアップ（完了）
- [x] マイグレーション実行（data/jobs.db に適用済み）
- [x] データ整合性確認（threads, jobs.thread_id, device_sessions 4D構造確認済み）
  ```sql
  -- 全roomsにthread存在確認
  SELECT r.id, r.name, COUNT(t.id) as thread_count
  FROM rooms r
  LEFT JOIN threads t ON r.id = t.room_id
  GROUP BY r.id;

  -- 全jobsにthread_id割り当て確認
  SELECT COUNT(*) as jobs_without_thread FROM jobs WHERE room_id IS NOT NULL AND thread_id IS NULL;
  ```

#### 1.1.5 ON DELETE CASCADE 検証
- [ ] CASCADE動作テスト
  ```sql
  -- テストルーム作成
  INSERT INTO rooms (id, name, workspace_path, device_id, created_at, updated_at)
  VALUES ('test-room', 'Test', '/tmp', 'test-device', datetime('now'), datetime('now'));

  -- テストスレッド作成
  INSERT INTO threads (id, room_id, name, runner, device_id, created_at, updated_at)
  VALUES ('test-thread', 'test-room', 'Test Thread', 'claude', 'test-device', datetime('now'), datetime('now'));

  -- テストジョブ作成
  INSERT INTO jobs (id, runner, input_text, device_id, room_id, thread_id, status, created_at)
  VALUES ('test-job', 'claude', 'test', 'test-device', 'test-room', 'test-thread', 'completed', datetime('now'));

  -- CASCADE確認: thread削除 → jobsも削除されるはず
  DELETE FROM threads WHERE id = 'test-thread';
  SELECT COUNT(*) FROM jobs WHERE id = 'test-job';  -- 0であるべき

  -- CASCADE確認: room削除 → threads, jobsも削除されるはず
  DELETE FROM rooms WHERE id = 'test-room';
  SELECT COUNT(*) FROM threads WHERE id = 'test-thread';  -- 0であるべき
  ```

---

## フェーズ2: モデル層更新

### 2.1 SQLAlchemyモデル更新

#### 2.1.1 Thread モデル追加
- [x] `remote-job-server/models.py` に Thread クラス追加（Codexにより完了）

```python
class Thread(Base):
    __tablename__ = "threads"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String, ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String, nullable=False, default="無題")
    runner = Column(String, nullable=False, index=True)  # 'claude' or 'codex'
    device_id = Column(String, nullable=False)
    created_at = Column(DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, nullable=False, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), index=True)

    # リレーション
    room = relationship("Room", back_populates="threads")
    jobs = relationship("Job", back_populates="thread", cascade="all, delete-orphan")

    __table_args__ = (
        Index('idx_threads_room_runner', 'room_id', 'runner'),
        Index('idx_threads_updated_at', updated_at.desc()),
    )
```

#### 2.1.2 Room モデル更新
- [x] Room に threads リレーション追加（完了）

```python
class Room(Base):
    # 既存フィールド...
    threads = relationship("Thread", back_populates="room", cascade="all, delete-orphan")
```

#### 2.1.3 Job モデル更新
- [x] Job に thread_id フィールド追加（完了、全フィールド実装済み）

```python
class Job(Base):
    __tablename__ = "jobs"

    # 既存フィールド（現行スキーマ）
    id = Column(String, primary_key=True)
    runner = Column(String, nullable=False)
    input_text = Column(Text, nullable=False)
    device_id = Column(String, nullable=False)
    room_id = Column(String, ForeignKey("rooms.id"), nullable=False)
    status = Column(String, nullable=False)
    exit_code = Column(Integer)
    stdout = Column(Text)
    stderr = Column(Text)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    notify_token = Column(String)
    created_at = Column(DateTime, nullable=False, default=lambda: datetime.now(timezone.utc))

    # 新規追加
    thread_id = Column(String, ForeignKey("threads.id"), nullable=True, index=True)  # 互換性のため初期はnullable

    # リレーション
    thread = relationship("Thread", back_populates="jobs")

    __table_args__ = (
        Index('idx_jobs_thread_id', 'thread_id'),
        Index('idx_jobs_room_thread', 'room_id', 'thread_id'),
    )
```

#### 2.1.4 DeviceSession モデル更新
- [x] device_sessions の UNIQUE制約を4次元に変更（完了）

```python
class DeviceSession(Base):
    # 既存フィールド...
    thread_id = Column(String, ForeignKey("threads.id", ondelete="CASCADE"), nullable=False)

    __table_args__ = (
        UniqueConstraint('device_id', 'room_id', 'runner', 'thread_id', name='_device_room_runner_thread_uc'),
        Index('idx_device_sessions_lookup', 'device_id', 'room_id', 'runner', 'thread_id'),
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
- [x] エンドポイント実装（完了、動作確認済み）

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
- [x] エンドポイント実装（完了、動作確認済み）

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
- [x] エンドポイント実装（完了、動作確認済み）

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
- [x] エンドポイント実装（完了、CASCADE削除対応済み）

**リクエスト**:
```
DELETE /threads/{thread_id}?device_id=iphone-nao-1
Headers:
  x-api-key: your-api-key
```

**カスケード削除**: jobs, device_sessions

---

## フェーズ4: 既存API拡張（互換性維持）

### 4.1 互換モード環境変数設定

#### 4.1.1 環境変数定義
- [x] `.env` に追加（デフォルト値で運用中）

```bash
# Thread互換モード（Phase A/B期間中はtrue、Phase C完了後false）
THREADS_COMPAT_MODE=true
```

#### 4.1.2 設定クラス更新
- [x] `remote-job-server/config.py` 更新（threads_compat_mode: bool = True 実装済み）

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # 既存設定...
    threads_compat_mode: bool = True  # デフォルトtrue

    class Config:
        env_file = ".env"

settings = Settings()
```

### 4.2 POST /jobs 拡張

#### 4.2.1 互換モード実装
- [x] リクエストボディに `thread_id` (optional) 追加（完了）
- [x] thread_id未指定時: デフォルトスレッド取得ロジック（_get_or_create_default_thread実装済み）

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
import logging
from config import settings

logger = logging.getLogger(__name__)

def get_default_thread(room_id: str, runner: str, db: Session) -> Thread:
    """
    互換性のため、thread_id未指定時はデフォルトスレッドを返す
    """
    if not settings.threads_compat_mode:
        raise ValueError("thread_id is required when THREADS_COMPAT_MODE=false")

    # 該当room×runnerの最古スレッド（マイグレーションで生成されたもの）
    thread = db.query(Thread).filter(
        Thread.room_id == room_id,
        Thread.runner == runner
    ).order_by(Thread.created_at.asc()).first()

    if not thread:
        # 存在しない場合は新規作成
        room = db.query(Room).filter(Room.id == room_id).first()
        thread = Thread(
            room_id=room_id,
            runner=runner,
            name=f"{runner.title()} 会話",
            device_id=room.device_id
        )
        db.add(thread)
        db.commit()
        logger.warning(f"[COMPAT] Created default thread for room={room_id}, runner={runner}")
    else:
        logger.info(f"[COMPAT] Using default thread {thread.id} for room={room_id}, runner={runner}")

    return thread
```

#### 4.2.2 セッション管理更新
- [x] SessionManager を4次元セッション対応に変更（ClaudeSessionManager, CodexSessionManager完了）

**変更前**:
```python
session_id = get_session(device_id, room_id, runner)
```

**変更後**:
```python
session_id = get_session(device_id, room_id, runner, thread_id)
logger.debug(f"Session lookup: device={device_id}, room={room_id}, runner={runner}, thread={thread_id}")
```

### 4.3 GET /messages 拡張

#### 4.3.1 thread_id パラメータ追加
- [x] Query に `thread_id` (optional) 追加（完了、互換モード対応済み）

**新リクエスト**:
```
GET /messages?room_id=room-uuid&runner=claude&thread_id=thread-uuid&device_id=iphone-nao-1
Headers:
  x-api-key: your-api-key
```

**互換性**:
```python
def get_messages(room_id: str, runner: str, thread_id: Optional[str], db: Session):
    query = db.query(Job).filter(
        Job.room_id == room_id,
        Job.runner == runner
    )

    if thread_id:
        # 新クライアント: 特定スレッドのみ
        query = query.filter(Job.thread_id == thread_id)
        logger.info(f"[NEW] Fetching messages for thread={thread_id}")
    else:
        # 旧クライアント: 全スレッド（互換モードのみ）
        if not settings.threads_compat_mode:
            raise ValueError("thread_id is required when THREADS_COMPAT_MODE=false")
        logger.info(f"[COMPAT] Fetching all messages for room={room_id}, runner={runner}")

    return query.order_by(Job.created_at.asc()).all()
```

### 4.4 互換モード監視ログ

#### 4.4.1 ログ戦略
- [ ] 互換経路を通った場合は必ずログ出力（`[COMPAT]` プレフィックス）
- [ ] 新経路は `[NEW]` プレフィックス
- [ ] Phase C移行判断のためのメトリクス収集

```python
# 例: アクセスログミドルウェア
@app.middleware("http")
async def log_compat_usage(request: Request, call_next):
    if request.url.path == "/jobs":
        body = await request.json()
        if "thread_id" not in body:
            logger.warning(f"[COMPAT] /jobs called without thread_id from device={body.get('device_id')}")
    response = await call_next(request)
    return response
```

---

## フェーズ5: iOS クライアント実装 ✅

### 5.1 モデル追加

#### 5.1.1 Thread.swift
- [x] `iOS_WatchOS/RemotePrompt/RemotePrompt/Models/Thread.swift` 作成（完了）

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

#### 5.2.1 APIClient拡張
- [x] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/APIClient.swift` にThread管理メソッド追加（完了）

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
- [x] `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ThreadListViewModel.swift` 作成（完了）

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
- [x] スレッド一覧表示（完了）
- [x] スレッド選択とChatView遷移（完了）
- [x] Empty state（完了）
- [x] Pull to refresh（refreshable modifier実装済み）

#### 5.4.2 CreateThreadView.swift
- [x] Sheet presentation（完了）
- [x] Form (name入力フィールド実装済み、runnerはThreadListViewから渡される）
- [x] Validation（空の場合は"無題"をデフォルト値として設定）
- [x] Create button（完了）

#### 5.4.3 EditThreadNameView.swift
- [x] Sheet presentation（完了）
- [x] TextField (focused)（完了）
- [x] Save button（完了）

### 5.5 RoomDetailView リファクタリング

#### 5.5.1 タブ変更
- [x] RunnerTab enum 保持（Claude/Codex切り替え用に継続使用）
- [x] claude/codex ViewModel 削除（Thread選択後に動的生成）
- [x] Picker UI 継続使用（Runner切り替え用）

#### 5.5.2 ThreadListView 埋め込み
- [x] ThreadListView組み込み完了（完了）
- [x] selectedThreadによる表示切り替え実装（完了）

#### 5.5.3 ツールバー再配置
- [x] FileBrowser button 配置（完了）
- [x] Back to Thread List button 実装（完了）

### 5.6 ChatViewModel 更新

#### 5.6.1 thread 対応
- [x] let threadId: String? 追加（完了）
- [x] init(threadId: String?) に変更（完了）
- [x] runner パラメータ維持（完了）
- [x] POST /jobs に thread_id 含める（完了）
- [x] APIClient.createJob に threadId パラメータ追加（完了）

---

## フェーズ6: テスト実装

### 6.1 バックエンドテスト

#### 6.1.1 マイグレーションテスト
- [ ] 空DBでのマイグレーション
- [ ] 既存データありでのマイグレーション
- [ ] ロールバック動作確認
- [ ] CASCADE削除検証
- [ ] インデックス存在確認

#### 6.1.2 Thread API テスト
- [ ] test_list_threads
- [ ] test_create_thread
- [ ] test_update_thread
- [ ] test_delete_thread
- [ ] test_cascade_delete
- [ ] test_unauthorized_access

#### 6.1.3 互換性テスト
- [ ] POST /jobs (thread_id未指定) + COMPAT=true
- [ ] POST /jobs (thread_id指定)
- [ ] POST /jobs (thread_id未指定) + COMPAT=false → エラー
- [ ] GET /messages (thread_id未指定) + COMPAT=true
- [ ] GET /messages (thread_id指定)
- [ ] GET /messages (thread_id未指定) + COMPAT=false → エラー

#### 6.1.4 パフォーマンステスト
- [ ] インデックス効果測定（EXPLAIN QUERY PLAN）
- [ ] N+1クエリ検出
- [ ] 大量スレッド（100+）でのレスポンスタイム

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
- [ ] `.env` で `THREADS_COMPAT_MODE=true` 確認

#### 7.1.2 デプロイ
- [ ] サーバー再起動
- [ ] 既存クライアントで動作確認（thread_id未指定）
- [ ] ログ監視（`[COMPAT]` 頻度確認）

### 7.2 Phase B: iOSクライアント更新

#### 7.2.1 段階的ロールアウト
- [ ] TestFlight配信
- [ ] ベータテスト
- [ ] 本番リリース

#### 7.2.2 動作確認
- [ ] Thread作成・一覧・編集・削除
- [ ] セッション継続
- [ ] マルチスレッド会話
- [ ] ログ監視（`[NEW]` 経路確認）

### 7.3 Phase C: 互換モード無効化（全クライアント更新後）

#### 7.3.1 移行判断基準
- [ ] 7日間のログで `[COMPAT]` 経路が0件
- [ ] 全アクティブデバイスがv4.0クライアント

#### 7.3.2 jobs.thread_id NOT NULL化
- [ ] 第二段階マイグレーション: `remote-job-server/migrations/v4_0_to_v4_1_non_null_thread.py`

```python
"""
v4.0 → v4.1: jobs.thread_id NOT NULL化
"""
import sqlite3

def migrate_v4_0_to_v4_1(db_path: str):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # NULLチェック
    cursor.execute("SELECT COUNT(*) FROM jobs WHERE thread_id IS NULL")
    null_count = cursor.fetchone()[0]
    if null_count > 0:
        raise Exception(f"Cannot migrate: {null_count} jobs have NULL thread_id")

    # jobs再作成（thread_id NOT NULL、現行スキーマ全列保持）
    cursor.execute("""
        CREATE TABLE jobs_new (
            id TEXT PRIMARY KEY,
            runner TEXT NOT NULL,
            input_text TEXT NOT NULL,
            device_id TEXT NOT NULL,
            room_id TEXT NOT NULL,  -- 現行スキーマではNOT NULL
            thread_id TEXT NOT NULL,  -- NOT NULL化
            status TEXT NOT NULL,
            exit_code INTEGER,
            stdout TEXT,
            stderr TEXT,
            started_at DATETIME,
            finished_at DATETIME,
            notify_token TEXT,
            created_at DATETIME NOT NULL,
            FOREIGN KEY (room_id) REFERENCES rooms(id),
            FOREIGN KEY (thread_id) REFERENCES threads(id)
        )
    """)

    cursor.execute("INSERT INTO jobs_new SELECT * FROM jobs")
    cursor.execute("DROP TABLE jobs")
    cursor.execute("ALTER TABLE jobs_new RENAME TO jobs")

    # インデックス再作成
    cursor.execute("CREATE INDEX idx_jobs_thread_id ON jobs(thread_id)")
    cursor.execute("CREATE INDEX idx_jobs_room_thread ON jobs(room_id, thread_id)")

    conn.commit()
    conn.close()
    print("✅ Migration v4.0→v4.1 completed: jobs.thread_id is now NOT NULL")

if __name__ == "__main__":
    migrate_v4_0_to_v4_1("remote_jobs.db")
```

#### 7.3.3 互換モード無効化
- [ ] `.env` で `THREADS_COMPAT_MODE=false` に変更
- [ ] サーバー再起動
- [ ] thread_id未指定リクエストがエラーになることを確認
- [ ] デフォルトスレッドロジック削除（コード整理）

#### 7.3.4 API仕様書更新
- [ ] POST /jobs: thread_id を Required に変更
- [ ] GET /messages: thread_id を Required に変更

---

## ドキュメント更新

### MASTER_SPECIFICATION.md 更新

#### セクション追加
- [ ] **v4.0: Thread Management**
  - データモデル図 (Room → Thread → Job)
  - セッション管理 4次元 (device_id, room_id, runner, thread_id)
  - インデックス設計
  - API仕様 (Thread CRUD)
  - 互換性ポリシー（環境変数フラグ）
  - マイグレーション手順（v3→v4→v4.1）

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
- モニタリング強化（`[COMPAT]` ログ）

### リスク4: パフォーマンス劣化
**対策**:
- thread_id, room_id にインデックス（作成済）
- N+1クエリ回避（relationship eager loading）
- EXPLAIN QUERY PLAN で実行計画確認

### リスク5: CASCADE削除の予期しない挙動
**対策**:
- マイグレーション段階でCASCADE動作テスト
- 本番デプロイ前にステージング環境で検証
- 削除前の確認UI（iOS: Alert with destructive style）

### リスク6: 互換モード永続化
**対策**:
- Phase C完了基準を明確化（ログ0件×7日間）
- 定期的な `[COMPAT]` ログレビュー
- Phase C期限設定（Phase B完了後30日以内）

---

## 工数見積もり

| フェーズ | 内容 | 工数 |
|---------|------|------|
| 1 | マイグレーション（インデックス＋CASCADE検証含む） | 8h |
| 2 | モデル層更新 | 3h |
| 3 | Thread API実装 | 5h |
| 4 | 既存API拡張（互換モード＋ログ） | 6h |
| 5 | iOSクライアント | 12h |
| 6 | テスト実装（性能テスト含む） | 10h |
| 7 | 段階的デプロイ（Phase C含む） | 6h |
| ドキュメント | MASTER_SPEC更新 | 2h |

**合計**: 約52時間

---

## 完了基準

### Phase A完了 ✅
- [x] マイグレーション成功
- [x] インデックス作成確認
- [x] CASCADE削除動作確認（ON DELETE CASCADE実装済み）
- [x] Thread API全エンドポイント動作（GET/POST/PATCH/DELETE確認済み）
- [x] 既存クライアント動作確認（互換モード、デフォルトスレッド自動作成）
- [x] バックエンド動作テスト完了（curlによる統合テスト実施）
- [x] `THREADS_COMPAT_MODE=true` 確認（config.pyデフォルト値）

### Phase B完了 ✅
- [x] iOS Thread機能実装
- [x] UIビルド成功（xcodebuild BUILD SUCCEEDED）
- [ ] TestFlight動作確認（実機テストは未実施）
- [x] 新クライアントが thread_id 送信確認（APIClient実装済み）
- [ ] ログで `[NEW]` 経路確認（実機テスト時に確認）

### Phase C完了（v4.1）
- [ ] `[COMPAT]` ログ0件×7日間確認
- [ ] jobs.thread_id NOT NULL化マイグレーション成功
- [ ] `THREADS_COMPAT_MODE=false` に変更
- [ ] thread_id未指定リクエストがエラーになることを確認
- [ ] API仕様書更新

### 全体完了
- [ ] 本番環境デプロイ
- [ ] マルチスレッド会話動作確認
- [ ] ドキュメント更新（v4.0 + v4.1）
- [ ] パフォーマンス基準クリア

---

**作成日**: 2025-01-20
**バージョン**: 2.1 Final (運用考慮版)
**作成者**: Claude Code
**変更履歴**:
- v2.0: 現行仕様v3.0完全適合版
- v2.1: インデックス設計、互換モードフラグ、NOT NULL化第二段階追加

---

## 次のステップ

1. この計画をレビュー
2. フェーズ1（マイグレーション）から着手
3. 各フェーズ完了時にチェックマーク更新
4. Phase C移行判断のため、デプロイ後は週次で `[COMPAT]` ログレビュー
5. 問題発生時は本ドキュメントに記録し、MASTER_SPECIFICATIONに反映

---

## 実装上の設計変更（Phase B完了時点）

### Runner タブの保持
**計画**: RoomDetailViewからRunnerタブを削除し、Thread一覧のみ表示
**実装**: Runnerタブを保持し、UX向上を優先

**理由**:
- Room → Runner選択 → Thread一覧 → Chat という明確な階層構造
- Claude/Codex を切り替える際のUX改善
- 各Runnerごとにスレッドを管理できる設計

**技術的対応**:
- サーバー側 `GET /rooms/{room_id}/threads` は runner パラメータ未対応
- クライアント側で全件取得後に `threads.filter { $0.runner == runner }` でフィルタリング
- 実装箇所: `ThreadListViewModel.fetchThreads()` (L34-41)

**トレードオフ**:
- ✅ メリット: UX向上、実装シンプル
- ⚠️ デメリット: サーバー側フィルタ未実装により、大量スレッド時に若干非効率

**今後の改善案**:
- サーバー側に `runner` クエリパラメータを追加（オプショナル）
- 1万スレッド超の場合のみサーバーフィルタに切り替え

### Chat履歴API のスレッド対応
**実装**: `GET /messages` に `thread_id` クエリパラメータを追加

**実装箇所**:
- `APIClient.fetchMessages(threadId: String?)` (L341-377)
- `ChatViewModel.fetchHistory()` で threadId を渡す (L91)

**動作**:
- threadId が nil の場合: 互換モード（THREADS_COMPAT_MODE=true）でデフォルトスレッドの履歴を取得
- threadId が指定されている場合: 特定スレッドの履歴のみ取得

### PreviewAPIClient の簡易実装
**制約**: PreviewAPIClient は状態を持たないため、updateThread で roomId の一貫性を完全に保証できない

**対応**:
- 固定値 `"preview-room-id"` を使用して最低限の整合性を確保
- コメントで制約を明記
- プレビュー/UI テスト用途のため、実運用に影響なし

---

**更新日**: 2025-01-21
**更新者**: Claude Code (Code Review対応)
