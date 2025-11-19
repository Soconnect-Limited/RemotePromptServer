# Phase 1: サーバー側実装 - 詳細チェックリスト

**作成日**: 2025-11-19
**対象**: Room-Based Architecture - サーバー側実装
**前提**: データベース初期化済み (`data/jobs.db` が存在)

---

## 実装順序の原則

1. **データモデル → マイグレーション → API → テスト** の順で進める
2. 各ステップ完了後に動作確認を行う
3. エラーが出た場合は次に進まず、原因を特定して修正する

---

## Step 1: データモデル定義

### 1.1 `Room` モデル作成

#### ☐ 1.1.1 `remote-job-server/models.py` を開く
- [ ] ファイルを読み込み、既存の `DeviceSession`, `Device`, `Job` モデルを確認

#### ☐ 1.1.2 `Room` クラスを追加（`DeviceSession` の前に配置）
```python
class Room(Base):
    __tablename__ = "rooms"

    id = Column(String(36), primary_key=True)  # UUID
    name = Column(String(100), nullable=False)
    workspace_path = Column(String(500), nullable=False)
    icon = Column(String(50), nullable=False, default="folder")
    device_id = Column(String(100), nullable=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "workspace_path": self.workspace_path,
            "icon": self.icon,
            "device_id": self.device_id,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
```

- [ ] コードを追加
- [ ] インデントとインポートを確認

#### ☐ 1.1.3 `DeviceSession` モデルに `room_id` カラム追加
```python
class DeviceSession(Base):
    # ... 既存のコード ...
    room_id = Column(String(36), nullable=False)  # 追加

    # __table_args__ を更新
    __table_args__ = (
        UniqueConstraint("device_id", "room_id", "runner", name="uq_device_room_runner"),
        Index("idx_device_room_runner", "device_id", "room_id", "runner"),
    )
```

- [ ] `room_id` カラムを追加（`runner` の下に配置）
- [ ] `__table_args__` の `UniqueConstraint` を更新
- [ ] `Index` を更新

#### ☐ 1.1.4 `Job` モデルに `room_id` カラム追加
```python
class Job(Base):
    # ... 既存のコード ...
    room_id = Column(String(36), nullable=False)  # device_id の下に追加

    def to_dict(self) -> dict:
        return {
            # ... 既存のフィールド ...
            "room_id": self.room_id,  # 追加
        }
```

- [ ] `room_id` カラムを追加
- [ ] `to_dict()` メソッドに `room_id` を追加

#### ☐ 1.1.5 保存してインポートエラーがないか確認
```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
python3 -c "from models import Room, DeviceSession, Job; print('OK')"
```

- [ ] コマンド実行
- [ ] "OK" が表示されることを確認

---

### 1.2 パスバリデーション関数作成

#### ☐ 1.2.1 `remote-job-server/utils/` ディレクトリ作成
```bash
mkdir -p /Users/macstudio/Projects/RemotePrompt/remote-job-server/utils
touch /Users/macstudio/Projects/RemotePrompt/remote-job-server/utils/__init__.py
```

- [ ] ディレクトリ作成
- [ ] `__init__.py` 作成

#### ☐ 1.2.2 `remote-job-server/utils/path_validator.py` 作成
```python
"""Workspace path validation for security."""
from pathlib import Path
from typing import List

# ホワイトリスト: これらのディレクトリ配下のみ許可
ALLOWED_BASE_PATHS: List[str] = [
    "/Users/macstudio/Projects",
    "/Users/macstudio/Documents",
]

# ブラックリスト: これらのディレクトリは絶対に許可しない
FORBIDDEN_PATHS: List[str] = [
    "/System",
    "/Library",
    "/private",
    "/etc",
    "/usr",
    "/bin",
    "/sbin",
    "/var",
]


def is_safe_workspace_path(path: str) -> bool:
    """
    ワークスペースパスが安全かどうかを検証する。

    Args:
        path: 検証するパス文字列

    Returns:
        bool: 安全な場合True、危険な場合False
    """
    try:
        # 絶対パスに変換し、シンボリックリンクを解決
        abs_path = Path(path).resolve()
        abs_path_str = str(abs_path)

        # ブラックリストチェック
        for forbidden in FORBIDDEN_PATHS:
            if abs_path_str.startswith(forbidden):
                return False

        # ホワイトリストチェック
        for allowed in ALLOWED_BASE_PATHS:
            if abs_path_str.startswith(allowed):
                return True

        # どのホワイトリストにも一致しない場合は拒否
        return False

    except (ValueError, OSError):
        # パスが無効な場合は拒否
        return False


def validate_workspace_path(path: str) -> str:
    """
    ワークスペースパスを検証し、問題があれば例外を発生させる。

    Args:
        path: 検証するパス文字列

    Returns:
        str: 検証済みの絶対パス

    Raises:
        ValueError: パスが安全でない場合
    """
    if not is_safe_workspace_path(path):
        raise ValueError(f"Workspace path is not allowed: {path}")

    abs_path = Path(path).resolve()
    return str(abs_path)
```

- [ ] ファイル作成
- [ ] コード貼り付け

#### ☐ 1.2.3 パスバリデーションのテスト
```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
python3 << 'EOF'
from utils.path_validator import is_safe_workspace_path

# 正常系
assert is_safe_workspace_path("/Users/macstudio/Projects/RemotePrompt") == True
assert is_safe_workspace_path("/Users/macstudio/Documents/test") == True

# 異常系
assert is_safe_workspace_path("/System/Library") == False
assert is_safe_workspace_path("/etc/passwd") == False
assert is_safe_workspace_path("/tmp") == False

print("✅ Path validation tests passed")
EOF
```

- [ ] テスト実行
- [ ] "✅ Path validation tests passed" が表示されることを確認

---

## Step 2: データベースマイグレーション

### 2.1 既存データベースのバックアップ

#### ☐ 2.1.1 バックアップ作成
```bash
cp /Users/macstudio/Projects/RemotePrompt/remote-job-server/data/jobs.db \
   /Users/macstudio/Projects/RemotePrompt/remote-job-server/data/jobs.db.backup_$(date +%Y%m%d_%H%M%S)
```

- [ ] バックアップ作成
- [ ] ファイルが存在することを確認: `ls -lh data/jobs.db.backup_*`

---

### 2.2 データベーススキーマ更新

#### ☐ 2.2.1 `database.py` の `init_db()` を確認
```bash
grep -A 5 "def init_db" /Users/macstudio/Projects/RemotePrompt/remote-job-server/database.py
```

- [ ] `init_db()` 関数が `Room` をインポートしているか確認
- [ ] インポートされていない場合は追加

#### ☐ 2.2.2 既存データベースを削除して再作成
```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
rm data/jobs.db
python3 init_db.py
```

- [ ] データベース削除
- [ ] `init_db.py` 実行
- [ ] "Database initialized." が表示されることを確認

#### ☐ 2.2.3 新スキーマの確認
```bash
sqlite3 data/jobs.db ".schema rooms"
sqlite3 data/jobs.db ".schema device_sessions"
sqlite3 data/jobs.db ".schema jobs"
```

- [ ] `rooms` テーブルが作成されていることを確認
- [ ] `device_sessions` に `room_id` カラムがあることを確認
- [ ] `jobs` に `room_id` カラムがあることを確認

---

### 2.3 デフォルトルーム作成スクリプト

#### ☐ 2.3.1 `remote-job-server/create_default_room.py` 作成
```python
"""Create a default room for testing."""
import uuid
from database import SessionLocal
from models import Room, utcnow


def create_default_room(
    device_id: str = "A9D6056D-F2F9-4D58-A929-7B32480E7DED",
    name: str = "RemotePrompt",
    workspace_path: str = "/Users/macstudio/Projects/RemotePrompt"
) -> Room:
    """Create a default room."""
    db = SessionLocal()
    try:
        # 既存のルームをチェック
        existing = db.query(Room).filter_by(device_id=device_id, name=name).first()
        if existing:
            print(f"Room already exists: {existing.id}")
            return existing

        room = Room(
            id=str(uuid.uuid4()),
            name=name,
            workspace_path=workspace_path,
            icon="folder",
            device_id=device_id,
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.add(room)
        db.commit()
        db.refresh(room)
        print(f"✅ Created room: {room.id} - {room.name}")
        return room
    except Exception as e:
        db.rollback()
        print(f"❌ Error: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    room = create_default_room()
    print(f"Room ID: {room.id}")
    print(f"Name: {room.name}")
    print(f"Workspace: {room.workspace_path}")
```

- [ ] ファイル作成

#### ☐ 2.3.2 デフォルトルーム作成
```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
python3 create_default_room.py
```

- [ ] スクリプト実行
- [ ] "✅ Created room" が表示されることを確認
- [ ] Room ID をメモ（後で使用）

#### ☐ 2.3.3 ルームが作成されたか確認
```bash
sqlite3 data/jobs.db "SELECT id, name, workspace_path FROM rooms;"
```

- [ ] ルームが1件表示されることを確認

---

## Step 3: REST API実装

### 3.1 ルーム管理API

#### ☐ 3.1.1 `main.py` にルーム取得API追加

**挿入位置**: `@app.post("/jobs")` の前

```python
# ========== Room Management APIs ==========

@app.get("/rooms")
async def get_rooms(
    device_id: str,
    api_key: str = Header(alias="x-api-key"),
    db: Session = Depends(get_db)
):
    """Get all rooms for a device."""
    validate_api_key(api_key)

    rooms = db.query(Room).filter_by(device_id=device_id).order_by(Room.updated_at.desc()).all()
    return [room.to_dict() for room in rooms]
```

- [ ] コードを追加
- [ ] インポートを確認: `from models import Room` が必要
- [ ] `Session` と `Depends` のインポートを確認

#### ☐ 3.1.2 ルーム作成API追加

```python
class CreateRoomRequest(BaseModel):
    device_id: str
    name: str
    workspace_path: str
    icon: str = "folder"


@app.post("/rooms")
async def create_room(
    req: CreateRoomRequest,
    api_key: str = Header(alias="x-api-key"),
    db: Session = Depends(get_db)
):
    """Create a new room."""
    validate_api_key(api_key)

    # パスのバリデーション
    from utils.path_validator import validate_workspace_path
    try:
        validated_path = validate_workspace_path(req.workspace_path)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    room = Room(
        id=str(uuid.uuid4()),
        name=req.name,
        workspace_path=validated_path,
        icon=req.icon,
        device_id=req.device_id,
        created_at=utcnow(),
        updated_at=utcnow(),
    )
    db.add(room)
    db.commit()
    db.refresh(room)

    return room.to_dict()
```

- [ ] `CreateRoomRequest` モデルを追加（`CreateJobRequest` の近くに配置）
- [ ] `create_room()` エンドポイントを追加
- [ ] `uuid` のインポートを確認: `import uuid`
- [ ] `utcnow` のインポートを確認: `from models import utcnow`

#### ☐ 3.1.3 ルーム削除API追加

```python
@app.delete("/rooms/{room_id}")
async def delete_room(
    room_id: str,
    device_id: str,
    api_key: str = Header(alias="x-api-key"),
    db: Session = Depends(get_db)
):
    """Delete a room and all associated sessions and jobs."""
    validate_api_key(api_key)

    room = db.query(Room).filter_by(id=room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")

    # 所有権チェック
    if room.device_id != device_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    # 関連データを削除
    db.query(DeviceSession).filter_by(room_id=room_id).delete()
    db.query(Job).filter_by(room_id=room_id).delete()
    db.delete(room)
    db.commit()

    return {"status": "ok"}
```

- [ ] コードを追加
- [ ] `DeviceSession`, `Job` のインポートを確認

#### ☐ 3.1.4 `get_db()` 依存関数を確認

`main.py` に以下が存在するか確認:

```python
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

- [ ] 存在しない場合は追加
- [ ] `SessionLocal` のインポートを確認: `from database import SessionLocal`

---

### 3.2 メッセージ履歴取得API

#### ☐ 3.2.1 メッセージ取得API追加

```python
@app.get("/messages")
async def get_messages(
    device_id: str,
    room_id: str,
    runner: str,
    limit: int = 20,
    offset: int = 0,
    api_key: str = Header(alias="x-api-key"),
    db: Session = Depends(get_db)
):
    """Get message history for a room and runner."""
    validate_api_key(api_key)

    # ルームの所有権確認
    room = db.query(Room).filter_by(id=room_id, device_id=device_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")

    jobs = (
        db.query(Job)
        .filter_by(device_id=device_id, room_id=room_id, runner=runner)
        .order_by(Job.created_at.desc())
        .limit(limit)
        .offset(offset)
        .all()
    )

    # 降順で取得したものを反転（最新が下になるよう）
    return [job.to_dict() for job in reversed(jobs)]
```

- [ ] コードを追加（`@app.get("/jobs/{job_id}")` の前に配置）
- [ ] インポートを確認

---

### 3.3 ジョブ作成APIの拡張

#### ☐ 3.3.1 `CreateJobRequest` に `room_id` 追加

```python
class CreateJobRequest(BaseModel):
    runner: str
    prompt: str
    device_id: str
    room_id: str  # 追加
```

- [ ] `room_id` フィールドを追加

#### ☐ 3.3.2 `create_job()` エンドポイントを更新

既存の `@app.post("/jobs")` を以下のように修正:

```python
@app.post("/jobs")
async def create_job(
    req: CreateJobRequest,
    background_tasks: BackgroundTasks,
    api_key: str = Header(alias="x-api-key"),
    db: Session = Depends(get_db)
):
    validate_api_key(api_key)

    # ルームの存在確認とワークスペースパス取得
    room = db.query(Room).filter_by(id=req.room_id, device_id=req.device_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")

    job_id = str(uuid.uuid4())
    job = Job(
        id=job_id,
        runner=req.runner,
        input_text=req.prompt,
        device_id=req.device_id,
        room_id=req.room_id,  # 追加
        status="queued",
        created_at=utcnow(),
    )
    db.add(job)
    db.commit()

    # バックグラウンドタスクにworkspace_pathを渡す
    background_tasks.add_task(
        execute_job_background,
        job_id,
        req.runner,
        req.prompt,
        req.device_id,
        req.room_id,  # 追加
        room.workspace_path  # 追加
    )

    return {"id": job_id, "status": "queued"}
```

- [ ] コードを更新
- [ ] `room_id` を `Job` に追加
- [ ] `background_tasks.add_task()` の引数に `room_id` と `workspace_path` を追加

---

### 3.4 バックグラウンドタスクの更新

#### ☐ 3.4.1 `execute_job_background()` のシグネチャ更新

既存の関数を以下のように更新:

```python
def execute_job_background(
    job_id: str,
    runner: str,
    prompt: str,
    device_id: str,
    room_id: str,  # 追加
    workspace_path: str  # 追加
):
    """Execute job in background."""
    db = SessionLocal()
    try:
        job = db.query(Job).filter_by(id=job_id).first()
        if not job:
            return

        job.status = "running"
        job.started_at = utcnow()
        db.commit()

        # SSE通知
        broadcast_job_status(job_id, "running", job.started_at, None, None)

        # セッションマネージャーを選択
        if runner == "claude":
            manager = ClaudeSessionManager()
        elif runner == "codex":
            manager = CodexSessionManager()
        else:
            raise ValueError(f"Unknown runner: {runner}")

        # ジョブ実行（workspace_pathを渡す）
        result = manager.execute_job(
            prompt=prompt,
            device_id=device_id,
            room_id=room_id,  # 追加
            workspace_path=workspace_path,  # 追加
            continue_session=True
        )

        # 結果を保存
        job.status = "success" if result["success"] else "failed"
        job.exit_code = 0 if result["success"] else 1
        job.stdout = result.get("output", "")
        job.stderr = result.get("error", "")
        job.finished_at = utcnow()
        db.commit()

        # SSE通知
        broadcast_job_status(job_id, job.status, job.started_at, job.finished_at, job.exit_code)

    except Exception as e:
        LOGGER.exception("Job execution failed")
        job.status = "failed"
        job.exit_code = 1
        job.stderr = str(e)
        job.finished_at = utcnow()
        db.commit()

        broadcast_job_status(job_id, "failed", job.started_at, job.finished_at, 1)
    finally:
        db.close()
```

- [ ] 関数シグネチャを更新
- [ ] `manager.execute_job()` に `room_id` と `workspace_path` を追加

---

## Step 4: セッションマネージャー拡張

### 4.1 `ClaudeSessionManager` の更新

#### ☐ 4.1.1 `session_manager.py` を開く
- [ ] ファイルを読み込み

#### ☐ 4.1.2 `execute_job()` メソッドのシグネチャを更新

```python
def execute_job(
    self,
    prompt: str,
    device_id: str,
    room_id: str,  # 追加
    workspace_path: str,  # 追加
    continue_session: bool = True,
) -> Dict[str, Optional[str]]:
```

- [ ] 引数を追加

#### ☐ 4.1.3 セッションID取得ロジックを更新

```python
if continue_session:
    session_id = self._get_session_id_from_db(device_id, room_id)
```

- [ ] `room_id` を渡すように変更

#### ☐ 4.1.4 `subprocess.run()` に `cwd` を追加

```python
result = subprocess.run(
    cmd,
    input=prompt,
    capture_output=True,
    text=True,
    timeout=300,
    cwd=workspace_path,  # 追加
)
```

- [ ] `cwd` パラメータを追加

#### ☐ 4.1.5 セッション保存ロジックを更新

```python
if result.returncode == 0:
    self._save_session_id_to_db(device_id, room_id, session_id)
```

- [ ] `room_id` を渡すように変更

#### ☐ 4.1.6 `_get_session_id_from_db()` メソッドを更新

```python
def _get_session_id_from_db(self, device_id: str, room_id: str) -> Optional[str]:
    """Return the persisted session ID, if any."""
    db = SessionLocal()
    try:
        session = (
            db.query(DeviceSession)
            .filter_by(device_id=device_id, room_id=room_id, runner="claude")
            .first()
        )
        return session.session_id if session else None
    finally:
        db.close()
```

- [ ] 引数に `room_id` を追加
- [ ] `filter_by` に `room_id` を追加

#### ☐ 4.1.7 `_save_session_id_to_db()` メソッドを更新

```python
def _save_session_id_to_db(self, device_id: str, room_id: str, session_id: str) -> None:
    """Save the session ID to the database."""
    db = SessionLocal()
    try:
        session = (
            db.query(DeviceSession)
            .filter_by(device_id=device_id, room_id=room_id, runner="claude")
            .first()
        )

        if session:
            session.session_id = session_id
            session.updated_at = utcnow()
        else:
            session = DeviceSession(
                device_id=device_id,
                room_id=room_id,
                runner="claude",
                session_id=session_id,
                created_at=utcnow(),
                updated_at=utcnow(),
            )
            db.add(session)

        db.commit()
    finally:
        db.close()
```

- [ ] 引数に `room_id` を追加
- [ ] `filter_by` と新規作成時に `room_id` を追加

#### ☐ 4.1.8 `get_session_id()` メソッドを更新

```python
def get_session_id(self, device_id: str, room_id: str) -> Optional[str]:
    """Return the persisted session ID, if any."""
    return self._get_session_id_from_db(device_id, room_id)
```

- [ ] 引数に `room_id` を追加

---

### 4.2 `CodexSessionManager` の更新

#### ☐ 4.2.1 `ClaudeSessionManager` と同様の変更を適用
- [ ] `execute_job()` に `room_id`, `workspace_path` を追加
- [ ] `subprocess.run()` に `cwd=workspace_path` を追加
- [ ] `_get_session_id_from_db()` に `room_id` を追加（`runner="codex"` に変更）
- [ ] `_save_session_id_to_db()` に `room_id` を追加（`runner="codex"` に変更）
- [ ] `get_session_id()` に `room_id` を追加

---

### 4.3 インポート追加

#### ☐ 4.3.1 `session_manager.py` の先頭でインポート確認

```python
from database import SessionLocal
from models import DeviceSession, utcnow
```

- [ ] インポートが存在することを確認
- [ ] 不足している場合は追加

---

## Step 5: セッションクリアAPI

#### ☐ 5.1 `main.py` にセッションクリアAPI追加

```python
@app.delete("/sessions")
async def delete_session(
    device_id: str,
    room_id: str,
    runner: str,
    api_key: str = Header(alias="x-api-key"),
    db: Session = Depends(get_db)
):
    """Delete a session for a specific room and runner."""
    validate_api_key(api_key)

    deleted = (
        db.query(DeviceSession)
        .filter_by(device_id=device_id, room_id=room_id, runner=runner)
        .delete()
    )
    db.commit()

    return {"status": "ok", "deleted": deleted}
```

- [ ] コードを追加（`@app.delete("/rooms/{room_id}")` の後）

---

## Step 6: サーバー再起動とテスト

### 6.1 サーバー再起動

#### ☐ 6.1.1 既存のサーバープロセスを停止
```bash
ps aux | grep "[u]vicorn" | awk '{print $2}' | xargs kill
sleep 2
```

- [ ] コマンド実行
- [ ] プロセスが停止したことを確認: `ps aux | grep uvicorn`

#### ☐ 6.1.2 サーバー起動
```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
nohup uvicorn main:app --host 0.0.0.0 --port 8443 \
  --ssl-keyfile certs/config/live/remoteprompt.soconnect.co.jp/privkey.pem \
  --ssl-certfile certs/config/live/remoteprompt.soconnect.co.jp/fullchain.pem \
  > /tmp/https-server.log 2>&1 &

echo $!
sleep 3
```

- [ ] サーバー起動
- [ ] PIDをメモ
- [ ] ログ確認: `tail -20 /tmp/https-server.log`
- [ ] エラーがないことを確認

#### ☐ 6.1.3 ヘルスチェック
```bash
curl -k https://localhost:8443/health
```

- [ ] `{"status":"ok"}` が返ることを確認

---

### 6.2 API動作テスト

#### ☐ 6.2.1 APIキー設定
```bash
API_KEY="jg3uIg7w753xDmbH1XV1KQhAs3MqL_ms5iZGjYoKoMA"
DEVICE_ID="A9D6056D-F2F9-4D58-A929-7B32480E7DED"
```

- [ ] 変数設定

#### ☐ 6.2.2 ルーム一覧取得テスト
```bash
curl -k -H "x-api-key: $API_KEY" \
  "https://localhost:8443/rooms?device_id=$DEVICE_ID" \
  2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] デフォルトルームが1件返ることを確認
- [ ] `room_id` をメモ（次のテストで使用）

#### ☐ 6.2.3 新規ルーム作成テスト
```bash
curl -k -X POST -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "'"$DEVICE_ID"'",
    "name": "Test Room",
    "workspace_path": "/Users/macstudio/Projects",
    "icon": "📁"
  }' \
  "https://localhost:8443/rooms" \
  2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] 新規ルームが作成されることを確認
- [ ] `id` が返ることを確認

#### ☐ 6.2.4 禁止パステスト（失敗するべき）
```bash
curl -k -X POST -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "'"$DEVICE_ID"'",
    "name": "Bad Room",
    "workspace_path": "/System/Library",
    "icon": "⛔"
  }' \
  "https://localhost:8443/rooms" 2>&1 | grep -o "400\|Workspace path"
```

- [ ] 実行
- [ ] `400` エラーまたは "Workspace path" エラーメッセージが表示されることを確認

#### ☐ 6.2.5 ジョブ作成テスト（room_id付き）

デフォルトルームのIDを使用:

```bash
ROOM_ID="<デフォルトルームのID>"  # 6.2.2 で取得したID

curl -k -X POST -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "runner": "claude",
    "prompt": "pwd コマンドを実行して、現在の作業ディレクトリを教えてください。",
    "device_id": "'"$DEVICE_ID"'",
    "room_id": "'"$ROOM_ID"'"
  }' \
  "https://localhost:8443/jobs" \
  2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] `job_id` が返ることを確認
- [ ] `job_id` をメモ

#### ☐ 6.2.6 ジョブ結果確認
```bash
JOB_ID="<上記で取得したjob_id>"

sleep 5  # ジョブ実行を待機

curl -k -H "x-api-key: $API_KEY" \
  "https://localhost:8443/jobs/$JOB_ID" \
  2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] `status: "success"` が返ることを確認
- [ ] `stdout` に `/Users/macstudio/Projects/RemotePrompt` が含まれることを確認（作業ディレクトリが正しく設定されている）

#### ☐ 6.2.7 メッセージ履歴取得テスト
```bash
curl -k -H "x-api-key: $API_KEY" \
  "https://localhost:8443/messages?device_id=$DEVICE_ID&room_id=$ROOM_ID&runner=claude&limit=10" \
  2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] 先ほど作成したジョブが返ることを確認

#### ☐ 6.2.8 セッションクリアテスト
```bash
curl -k -X DELETE -H "x-api-key: $API_KEY" \
  "https://localhost:8443/sessions?device_id=$DEVICE_ID&room_id=$ROOM_ID&runner=claude" \
  2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] `{"status": "ok", "deleted": 1}` が返ることを確認

---

## Step 7: 統合テスト

#### ☐ 7.1 2つの異なるルームでジョブを実行

##### 7.1.1 ルーム1でジョブ実行
```bash
ROOM_ID_1="<デフォルトルームのID>"

curl -k -X POST -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "runner": "claude",
    "prompt": "このディレクトリ名は何ですか？（basename コマンドで確認してください）",
    "device_id": "'"$DEVICE_ID"'",
    "room_id": "'"$ROOM_ID_1"'"
  }' \
  "https://localhost:8443/jobs" 2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] `job_id` をメモ

##### 7.1.2 ルーム2を作成
```bash
curl -k -X POST -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "'"$DEVICE_ID"'",
    "name": "Documents Room",
    "workspace_path": "/Users/macstudio/Documents",
    "icon": "📄"
  }' \
  "https://localhost:8443/rooms" 2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] `room_id` をメモ（`ROOM_ID_2` とする）

##### 7.1.3 ルーム2でジョブ実行
```bash
ROOM_ID_2="<上記で取得したID>"

curl -k -X POST -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "runner": "claude",
    "prompt": "このディレクトリ名は何ですか？（basename コマンドで確認してください）",
    "device_id": "'"$DEVICE_ID"'",
    "room_id": "'"$ROOM_ID_2"'"
  }' \
  "https://localhost:8443/jobs" 2>/dev/null | python3 -m json.tool
```

- [ ] 実行
- [ ] `job_id` をメモ

##### 7.1.4 両方のジョブ結果を確認
```bash
sleep 10

# ルーム1のメッセージ
curl -k -H "x-api-key: $API_KEY" \
  "https://localhost:8443/messages?device_id=$DEVICE_ID&room_id=$ROOM_ID_1&runner=claude&limit=5" \
  2>/dev/null | python3 -m json.tool | grep -A 2 '"stdout"'

# ルーム2のメッセージ
curl -k -H "x-api-key: $API_KEY" \
  "https://localhost:8443/messages?device_id=$DEVICE_ID&room_id=$ROOM_ID_2&runner=claude&limit=5" \
  2>/dev/null | python3 -m json.tool | grep -A 2 '"stdout"'
```

- [ ] 実行
- [ ] ルーム1の結果に "RemotePrompt" が含まれることを確認
- [ ] ルーム2の結果に "Documents" が含まれることを確認
- [ ] **ワークスペースパスが正しく機能していることを確認**

---

## Step 8: ドキュメント更新

#### ☐ 8.1 `Docs/MASTER_SPECIFICATION.md` の更新
- [ ] ファイルを開く
- [ ] "データベーススキーマ" セクションに `rooms` テーブルを追加
- [ ] "REST API仕様" セクションにルーム管理APIを追加
- [ ] "セッション管理" セクションに `room_id` を追加

#### ☐ 8.2 API仕様の文書化

`Docs/API_Reference.md` を作成（存在しない場合）:

```markdown
# REST API Reference

## Room Management

### GET /rooms
- **説明**: デバイスの全ルーム取得
- **パラメータ**:
  - `device_id` (query, required)
- **レスポンス**: `Room[]`

### POST /rooms
- **説明**: 新規ルーム作成
- **ボディ**: `CreateRoomRequest`
- **レスポンス**: `Room`

### DELETE /rooms/{room_id}
- **説明**: ルーム削除
- **パラメータ**:
  - `room_id` (path, required)
  - `device_id` (query, required)
- **レスポンス**: `{"status": "ok"}`

## Messages

### GET /messages
- **説明**: ルーム×ランナー別のメッセージ履歴取得
- **パラメータ**:
  - `device_id` (query, required)
  - `room_id` (query, required)
  - `runner` (query, required): "claude" or "codex"
  - `limit` (query, optional, default: 20)
  - `offset` (query, optional, default: 0)
- **レスポンス**: `Job[]`
```

- [ ] ファイル作成
- [ ] 全APIエンドポイントを文書化

---

## 完了条件

### 必須チェック
- [ ] 全てのチェックボックスが完了している
- [ ] サーバーが起動し、エラーログがない
- [ ] ルーム作成・取得・削除が動作する
- [ ] 禁止パスへのアクセスが拒否される
- [ ] 異なるルームで異なる作業ディレクトリが使用される
- [ ] メッセージ履歴取得が動作する
- [ ] セッション管理が `room_id` と連動している

### 推奨チェック
- [ ] コードにコメントが追加されている
- [ ] ドキュメントが更新されている
- [ ] バックアップが作成されている

---

## トラブルシューティング

### エラー: "No module named 'utils'"
- **原因**: `utils/__init__.py` が存在しない
- **対処**: `touch remote-job-server/utils/__init__.py`

### エラー: "workspace path is not allowed"
- **原因**: パスがホワイトリストに含まれていない
- **対処**: `utils/path_validator.py` の `ALLOWED_BASE_PATHS` にパスを追加

### エラー: "Room not found"
- **原因**: `room_id` が存在しないまたは `device_id` が一致しない
- **対処**: `sqlite3 data/jobs.db "SELECT * FROM rooms;"` でルームを確認

### セッションが復元されない
- **原因**: `device_sessions` テーブルに `room_id` が記録されていない
- **対処**: `sqlite3 data/jobs.db "SELECT * FROM device_sessions;"` で確認

---

## 次のステップ

Phase 1 完了後、Phase 2（iOS側実装）に進む前に:

1. **動作確認**: 全てのAPIテストが成功していることを再確認
2. **ログ確認**: `/tmp/https-server.log` にエラーがないことを確認
3. **データ確認**: SQLiteデータベースに正しくデータが保存されていることを確認
4. **バックアップ**: 現在の状態をコミット（Git）

iOS側実装の準備ができたら、Phase 2の詳細チェックリストを作成します。
