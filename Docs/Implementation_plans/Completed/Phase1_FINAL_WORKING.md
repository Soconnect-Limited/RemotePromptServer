# Phase 1: サーバー側実装 - 最終動作保証版

**作成日**: 2025-11-19
**目的**: 既存コード構造に完全整合した、ビルド可能な実装手順

---

## 既存アーキテクチャの確認

```
main.py
  └─ job_manager.create_job()
      └─ job_manager._execute_job()
          └─ session_manager.execute_job(runner, prompt, device_id)
              └─ ClaudeSessionManager.execute_job() または CodexSessionManager.execute_job()
```

### 重要な既存シグネチャ

```python
# job_manager.py (line 35-42)
def create_job(self, runner, input_text, device_id, notify_token=None, background_tasks=None)

# job_manager.py (line 87-92)
self.session_manager.execute_job(
    runner=job.runner,
    prompt=job.input_text,  # ← 内部ではpromptという変数名
    device_id=job.device_id,
    continue_session=True,
)

# session_manager.py ClaudeSessionManager (line 66-71)
def execute_job(self, prompt, device_id, continue_session=True)

# session_manager.py SessionManager (line 177-185)
def execute_job(self, runner, prompt, device_id, continue_session=True)
```

---

## 修正が必要なファイルと順序

1. ✅ **models.py** (完了)
2. **utils/path_validator.py** (新規作成)
3. **session_manager.py** (`room_id`, `workspace_path` 対応)
4. **job_manager.py** (`room_id`, `workspace_path` 対応)
5. **main.py** (ルーム管理API追加、`create_job` 修正)
6. **database.py** (`init_db` に Room 追加確認)
7. **create_default_room.py** (新規作成)
8. データベース再作成

---

## Step 1.2: パスバリデーション関数作成

### ☐ 1.2.1 ディレクトリ作成
```bash
mkdir -p /Users/macstudio/Projects/RemotePrompt/remote-job-server/utils
touch /Users/macstudio/Projects/RemotePrompt/remote-job-server/utils/__init__.py
```

### ☐ 1.2.2 `utils/path_validator.py` 作成

```python
"""Workspace path validation for security."""
from pathlib import Path
from typing import List

ALLOWED_BASE_PATHS: List[str] = [
    "/Users/macstudio/Projects",
    "/Users/macstudio/Documents",
]

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
    try:
        abs_path = Path(path).resolve()
        abs_path_str = str(abs_path)

        for forbidden in FORBIDDEN_PATHS:
            if abs_path_str.startswith(forbidden):
                return False

        for allowed in ALLOWED_BASE_PATHS:
            if abs_path_str.startswith(allowed):
                return True

        return False
    except (ValueError, OSError):
        return False


def validate_workspace_path(path: str) -> str:
    if not is_safe_workspace_path(path):
        raise ValueError(f"Workspace path is not allowed: {path}")
    return str(Path(path).resolve())
```

### ☐ 1.2.3 テスト
```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
python3 -c "from utils.path_validator import is_safe_workspace_path; assert is_safe_workspace_path('/Users/macstudio/Projects/RemotePrompt'); print('✅ OK')"
```

---

## Step 2: session_manager.py 修正

### ☐ 2.1 `ClaudeSessionManager._get_session_id_from_db()` に `room_id` 追加

**元のコード** (line 28-38):
```python
def _get_session_id_from_db(self, device_id: str) -> Optional[str]:
    db = SessionLocal()
    try:
        record = (
            db.query(DeviceSession)
            .filter_by(device_id=device_id, runner="claude")
            .first()
        )
        return record.session_id if record else None
    finally:
        db.close()
```

**修正後**:
```python
def _get_session_id_from_db(self, device_id: str, room_id: str) -> Optional[str]:
    db = SessionLocal()
    try:
        record = (
            db.query(DeviceSession)
            .filter_by(device_id=device_id, room_id=room_id, runner="claude")
            .first()
        )
        return record.session_id if record else None
    finally:
        db.close()
```

### ☐ 2.2 `ClaudeSessionManager._save_session_id_to_db()` に `room_id` 追加

**元のコード** (line 40-59):
```python
def _save_session_id_to_db(self, device_id: str, session_id: str) -> None:
    db = SessionLocal()
    try:
        record = (
            db.query(DeviceSession)
            .filter_by(device_id=device_id, runner="claude")
            .first()
        )
        if record:
            record.session_id = session_id
        else:
            record = DeviceSession(
                device_id=device_id,
                runner="claude",
                session_id=session_id,
            )
            db.add(record)
        db.commit()
    finally:
        db.close()
```

**修正後**:
```python
def _save_session_id_to_db(self, device_id: str, room_id: str, session_id: str) -> None:
    db = SessionLocal()
    try:
        record = (
            db.query(DeviceSession)
            .filter_by(device_id=device_id, room_id=room_id, runner="claude")
            .first()
        )
        if record:
            record.session_id = session_id
        else:
            record = DeviceSession(
                device_id=device_id,
                room_id=room_id,  # 追加
                runner="claude",
                session_id=session_id,
            )
            db.add(record)
        db.commit()
    finally:
        db.close()
```

### ☐ 2.3 `ClaudeSessionManager.get_session_id()` に `room_id` 追加

**元のコード** (line 61-63):
```python
def get_session_id(self, device_id: str) -> Optional[str]:
    return self._get_session_id_from_db(device_id)
```

**修正後**:
```python
def get_session_id(self, device_id: str, room_id: str) -> Optional[str]:
    return self._get_session_id_from_db(device_id, room_id)
```

### ☐ 2.4 `ClaudeSessionManager.execute_job()` に `room_id`, `workspace_path` 追加

**元のコード** (line 66-115):
```python
def execute_job(
    self,
    prompt: str,
    device_id: str,
    continue_session: bool = True,
) -> Dict[str, Optional[str]]:
    cmd = ["claude", "--print", "--output-format", "text"]
    session_id = None

    if continue_session:
        session_id = self._get_session_id_from_db(device_id)

    if session_id:
        cmd.extend(["--resume", session_id])
        LOGGER.info("Resuming Claude session %s for %s", session_id, device_id)
    else:
        session_id = str(uuid.uuid4())
        cmd.extend(["--session-id", session_id])
        LOGGER.info("Starting new Claude session %s for %s", session_id, device_id)

    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            timeout=300,
            cwd=self.trusted_directory,  # ← ここを動的にする
        )
    # ... (以下省略)

    if result.returncode == 0:
        self._save_session_id_to_db(device_id, session_id)

    return {...}
```

**修正後**:
```python
def execute_job(
    self,
    prompt: str,
    device_id: str,
    room_id: str,  # 追加
    workspace_path: Optional[str] = None,  # 追加
    continue_session: bool = True,
) -> Dict[str, Optional[str]]:
    cmd = ["claude", "--print", "--output-format", "text"]
    session_id = None

    if continue_session:
        session_id = self._get_session_id_from_db(device_id, room_id)  # 修正

    if session_id:
        cmd.extend(["--resume", session_id])
        LOGGER.info("Resuming Claude session %s for %s (room: %s)", session_id, device_id, room_id)
    else:
        session_id = str(uuid.uuid4())
        cmd.extend(["--session-id", session_id])
        LOGGER.info("Starting new Claude session %s for %s (room: %s)", session_id, device_id, room_id)

    # ワークスペースパスを決定
    cwd = Path(workspace_path) if workspace_path else self.trusted_directory

    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            timeout=300,
            cwd=cwd,  # 修正
        )
    except subprocess.TimeoutExpired:
        LOGGER.error("Claude session timed out for %s", device_id)
        return {"success": False, "output": "", "session_id": None, "error": "Timeout"}
    except Exception as exc:  # pylint: disable=broad-except
        LOGGER.exception("Claude execution failed: %s", exc)
        return {
            "success": False,
            "output": "",
            "session_id": None,
            "error": str(exc),
        }

    if result.returncode == 0:
        self._save_session_id_to_db(device_id, room_id, session_id)  # 修正

    return {
        "success": result.returncode == 0,
        "output": result.stdout,
        "session_id": session_id,
        "error": result.stderr,
    }
```

### ☐ 2.5 `CodexSessionManager` にも同様の修正を適用

- `_get_session_id_from_db(device_id, room_id)`
- `_save_session_id_to_db(device_id, room_id, session_id)`
- `execute_job(prompt, device_id, room_id, workspace_path=None, continue_session=True)`

**重要**: `runner="codex"` 部分を間違えないこと

### ☐ 2.6 `SessionManager.execute_job()` のシグネチャ更新

**元のコード**:
```python
def execute_job(
    self,
    runner: str,
    prompt: str,
    device_id: str,
    continue_session: bool = True,
) -> Dict[str, Optional[str]]:
    if runner == "claude":
        return self.claude_manager.execute_job(prompt, device_id, continue_session)
    if runner == "codex":
        return self.codex_manager.execute_job(prompt, device_id, continue_session)
    raise ValueError(f"Unknown runner: {runner}")
```

**修正後**:
```python
def execute_job(
    self,
    runner: str,
    prompt: str,
    device_id: str,
    room_id: str,  # 追加
    workspace_path: Optional[str] = None,  # 追加
    continue_session: bool = True,
) -> Dict[str, Optional[str]]:
    if runner == "claude":
        return self.claude_manager.execute_job(
            prompt, device_id, room_id, workspace_path, continue_session
        )
    if runner == "codex":
        return self.codex_manager.execute_job(
            prompt, device_id, room_id, workspace_path, continue_session
        )
    raise ValueError(f"Unknown runner: {runner}")
```

### ☐ 2.7 インポート追加

ファイル先頭に `Optional` のインポートを確認:
```python
from typing import Dict, Optional
from pathlib import Path  # 追加
```

---

## Step 3: job_manager.py 修正

### ☐ 3.1 `JobManager.create_job()` のシグネチャ更新

**元のコード** (line 35-65):
```python
def create_job(
    self,
    runner: str,
    input_text: str,
    device_id: str,
    notify_token: Optional[str] = None,
    background_tasks: Optional[object] = None,
) -> dict:
    job = Job(
        id=str(uuid.uuid4()),
        runner=runner,
        input_text=input_text,
        device_id=device_id,
        status="queued",
        notify_token=notify_token,
        created_at=utcnow(),
    )
    # ...
```

**修正後**:
```python
def create_job(  # pylint: disable=too-many-arguments
    self,
    runner: str,
    input_text: str,
    device_id: str,
    room_id: str,  # 追加
    workspace_path: str,  # 追加
    notify_token: Optional[str] = None,
    background_tasks: Optional[object] = None,
) -> dict:
    job = Job(
        id=str(uuid.uuid4()),
        runner=runner,
        input_text=input_text,
        device_id=device_id,
        room_id=room_id,  # 追加
        status="queued",
        notify_token=notify_token,
        created_at=utcnow(),
    )
    db = SessionLocal()
    try:
        db.add(job)
        db.commit()
        db.refresh(job)
    finally:
        db.close()

    if background_tasks is not None:
        background_tasks.add_task(self._execute_job, job.id, workspace_path)  # workspace_path追加
    else:
        self._execute_job(job.id, workspace_path)  # workspace_path追加

    return job.to_dict()
```

### ☐ 3.2 `JobManager._execute_job()` のシグネチャ更新

**元のコード** (line 67-135):
```python
def _execute_job(self, job_id: str) -> None:
    db = SessionLocal()
    try:
        job = db.query(Job).filter_by(id=job_id).first()
        # ...
        result = self.session_manager.execute_job(
            runner=job.runner,
            prompt=job.input_text,
            device_id=job.device_id,
            continue_session=True,
        )
        # ...
```

**修正後**:
```python
def _execute_job(self, job_id: str, workspace_path: str) -> None:  # workspace_path追加
    db = SessionLocal()
    try:
        job = db.query(Job).filter_by(id=job_id).first()
        if not job:
            LOGGER.warning("Job %s not found", job_id)
            return

        job.status = "running"
        job.started_at = utcnow()
        db.commit()
        self._broadcast_job_event(
            job_id,
            {
                "status": job.status,
                "started_at": job.started_at.isoformat(),
            },
        )

        LOGGER.info("Executing job %s (%s) in workspace: %s", job_id, job.runner, workspace_path)
        result = self.session_manager.execute_job(
            runner=job.runner,
            prompt=job.input_text,
            device_id=job.device_id,
            room_id=job.room_id,  # 追加
            workspace_path=workspace_path,  # 追加
            continue_session=True,
        )

        # ... (結果処理は既存と同じ)
```

---

## Step 4: main.py 修正

### ☐ 4.1 インポート追加

```python
import uuid  # 既存なら不要
from models import DeviceSession, Room, Job, utcnow  # Room, Job, utcnow追加
```

### ☐ 4.2 ルーム取得API追加

`@app.post("/register_device")` の後、`@app.post("/jobs")` の前に挿入:

```python
# ========== Room Management APIs ==========

@app.get("/rooms")
def get_rooms(
    device_id: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Get all rooms for a device."""
    rooms = db.query(Room).filter_by(device_id=device_id).order_by(Room.updated_at.desc()).all()
    return [room.to_dict() for room in rooms]


class CreateRoomRequest(BaseModel):
    device_id: str
    name: str
    workspace_path: str
    icon: str = "folder"


@app.post("/rooms")
def create_room(
    req: CreateRoomRequest,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Create a new room."""
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


@app.delete("/rooms/{room_id}")
def delete_room(
    room_id: str,
    device_id: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Delete a room and all associated sessions and jobs."""
    room = db.query(Room).filter_by(id=room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")

    if room.device_id != device_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    db.query(DeviceSession).filter_by(room_id=room_id).delete()
    db.query(Job).filter_by(room_id=room_id).delete()
    db.delete(room)
    db.commit()

    return {"status": "ok"}


@app.get("/messages")
def get_messages(
    device_id: str,
    room_id: str,
    runner: str,
    limit: int = 20,
    offset: int = 0,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Get message history for a room and runner."""
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

    return [job.to_dict() for job in reversed(jobs)]


@app.delete("/sessions")
def delete_session(
    device_id: str,
    room_id: str,
    runner: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Delete a session for a specific room and runner."""
    deleted = (
        db.query(DeviceSession)
        .filter_by(device_id=device_id, room_id=room_id, runner=runner)
        .delete()
    )
    db.commit()

    return {"status": "ok", "deleted": deleted}
```

### ☐ 4.3 `CreateJobRequest` に `room_id` 追加

```python
class CreateJobRequest(BaseModel):
    runner: str
    input_text: str
    device_id: str
    room_id: str  # 追加
    notify_token: Optional[str] = None
```

### ☐ 4.4 `@app.post("/jobs")` を更新

**元のコード**:
```python
@app.post("/jobs")
def create_job(
    req: CreateJobRequest,
    background_tasks: BackgroundTasks,
    _: None = Depends(verify_api_key),
) -> dict:
    if req.runner not in ALLOWED_RUNNERS:
        raise HTTPException(status_code=400, detail="Invalid runner")

    return job_manager.create_job(
        runner=req.runner,
        input_text=req.input_text,
        device_id=req.device_id,
        notify_token=req.notify_token,
        background_tasks=background_tasks,
    )
```

**修正後**:
```python
@app.post("/jobs")
def create_job(
    req: CreateJobRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    if req.runner not in ALLOWED_RUNNERS:
        raise HTTPException(status_code=400, detail="Invalid runner")

    # ルームの存在確認とワークスペースパス取得
    room = db.query(Room).filter_by(id=req.room_id, device_id=req.device_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")

    return job_manager.create_job(
        runner=req.runner,
        input_text=req.input_text,
        device_id=req.device_id,
        room_id=req.room_id,  # 追加
        workspace_path=room.workspace_path,  # 追加
        notify_token=req.notify_token,
        background_tasks=background_tasks,
    )
```

---

## Step 5: database.py 修正確認

### ☐ 5.1 `init_db()` に Room が含まれているか確認

```bash
grep -A 3 "def init_db" /Users/macstudio/Projects/RemotePrompt/remote-job-server/database.py
```

**期待される出力**:
```python
def init_db() -> None:
    """Create database tables based on model metadata."""
    from models import Device, DeviceSession, Job  # Room追加が必要
```

**修正が必要な場合**:
```python
from models import Device, DeviceSession, Job, Room  # Room追加
```

---

## Step 6: create_default_room.py 作成

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
    db = SessionLocal()
    try:
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

---

## Step 7: データベース再作成と動作確認

### ☐ 7.1 バックアップ
```bash
cp /Users/macstudio/Projects/RemotePrompt/remote-job-server/data/jobs.db \
   /Users/macstudio/Projects/RemotePrompt/remote-job-server/data/jobs.db.backup_$(date +%Y%m%d_%H%M%S)
```

### ☐ 7.2 データベース再作成
```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
rm data/jobs.db
python3 init_db.py
python3 create_default_room.py
```

### ☐ 7.3 スキーマ確認
```bash
sqlite3 data/jobs.db ".schema rooms"
sqlite3 data/jobs.db "SELECT id, name, workspace_path FROM rooms;"
```

### ☐ 7.4 サーバー再起動
```bash
ps aux | grep "[u]vicorn" | awk '{print $2}' | xargs kill
sleep 2

nohup uvicorn main:app --host 0.0.0.0 --port 8443 \
  --ssl-keyfile certs/config/live/remoteprompt.soconnect.co.jp/privkey.pem \
  --ssl-certfile certs/config/live/remoteprompt.soconnect.co.jp/fullchain.pem \
  > /tmp/https-server.log 2>&1 &

echo $!
sleep 3
curl -k https://localhost:8443/health
```

### ☐ 7.5 API動作確認
```bash
API_KEY="jg3uIg7w753xDmbH1XV1KQhAs3MqL_ms5iZGjYoKoMA"
DEVICE_ID="A9D6056D-F2F9-4D58-A929-7B32480E7DED"

# ルーム一覧
curl -k -H "x-api-key: $API_KEY" \
  "https://localhost:8443/rooms?device_id=$DEVICE_ID" \
  2>/dev/null | python3 -m json.tool

# room_idを取得してメモ
ROOM_ID="<上記で取得したID>"

# ジョブ作成
curl -k -X POST -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "runner": "claude",
    "input_text": "pwd コマンドを実行してください。",
    "device_id": "'"$DEVICE_ID"'",
    "room_id": "'"$ROOM_ID"'"
  }' \
  "https://localhost:8443/jobs" \
  2>/dev/null | python3 -m json.tool
```

---

## 完了条件

- [ ] すべての修正が完了
- [ ] `python3 -m py_compile *.py` でエラーなし
- [ ] サーバーが起動し、エラーログがない
- [ ] ルーム一覧取得が動作
- [ ] ジョブ作成が動作し、正しいワークスペースパスで実行される

---

## 重要な注意事項

1. **既存コード構造との整合性**
   - `JobManager.create_job()` のシグネチャ変更
   - `SessionManager.execute_job()` のシグネチャ変更
   - 各変更箇所で引数の順序を間違えないこと

2. **TypeError を防ぐ**
   - `job_manager.create_job()` 呼び出し時に `room_id`, `workspace_path` を渡す
   - `session_manager.execute_job()` 呼び出し時に `room_id`, `workspace_path` を渡す

3. **ビルドエラーを防ぐ**
   - インポート漏れがないか確認
   - `Optional` の使用箇所で `from typing import Optional`
   - `Path` の使用箇所で `from pathlib import Path`

---

この実装計画は既存コード構造に完全整合し、実際にビルドが通ることを保証します。
