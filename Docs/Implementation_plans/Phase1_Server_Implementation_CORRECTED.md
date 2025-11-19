# Phase 1: サーバー側実装 - 修正版 v6

**作成日**: 2025-11-19
**最終修正日**: 2025-11-19 (v6更新)
**修正理由**: Step 5 の記述を明確化、前提条件と使用箇所を追記

---

## 修正履歴

### v6 (本バージョン - 2025-11-19 更新)
- ✅ Step 5.1: 各インポートの使用箇所をコメントで明記
- ✅ Step 5.1: 既存のFastAPI関連インポートが変更不要であることを明記
- ✅ Step 5.1: DeviceSessionが実際にはdelete_room()で使用されることを明記
- ✅ Step 5.6: Step 4完了が前提条件であることを明記
- ✅ Step 9: SSL/HTTP環境の違いを補足、BASE_URL環境変数を追加

### v5 (2025-11-19)
- ✅ Step 5.1 のインポート不足を修正（`import uuid`, `from models import Job, Room` を追加）
- ✅ NameError 発生を防ぐため、必要な全てのインポートを明記

### v4 (2025-11-19)
- ✅ Steps 1-4 を「完了」とマーク（実装済みファイルの調査完了）
- ✅ 詳細な修正前/修正後コードを削除し、完了サマリーのみ表示

### v3
- ✅ session_manager.py の修正手順を追加
- ✅ models.py の修正手順を追加
- ✅ job_manager.py の正確な修正手順を追加（実際のインスタンス変数に基づく）
- ✅ 存在しないAPIの参照を削除（sse_manager.broadcast_job_status等）
- ✅ database.py の確認手順を追加

### v2
- ✅ `validate_api_key()` → `Depends(verify_api_key)` に統一
- ✅ `CreateJobRequest.prompt` → `CreateJobRequest.input_text` に統一

### v1 (Phase1_Server_Implementation.md)
- ❌ 未定義関数を使用
- ❌ フィールド名がMaster Specと不一致

---

## 既存アーキテクチャの確認

```
main.py
  └─ job_manager.create_job()
      └─ job_manager._execute_job()
          └─ self.session_manager.execute_job(runner, prompt, device_id)
              └─ ClaudeSessionManager.execute_job() または CodexSessionManager.execute_job()
```

**重要**:
- `job_manager` は `self.session_manager` (インスタンス変数) を持っている
- `job_manager` は `self.sse_manager` (インスタンス変数、Optional) を持っている
- グローバルな `sse_manager` や `session_manager` は存在しない

---

## 実装順序

1. ✅ **models.py** - Room, DeviceSession.room_id, Job.room_id 追加（完了）
2. ✅ **utils/path_validator.py** - パスバリデーション（完了）
3. ✅ **session_manager.py** - room_id, workspace_path 対応（完了）
4. ✅ **job_manager.py** - room_id, workspace_path 対応（完了）
5. **main.py** - ルーム管理API追加、create_job 修正
6. **database.py** - init_db に Room 追加確認
7. **create_default_room.py** - デフォルトルーム作成スクリプト（新規作成）
8. **データベース再作成とテスト**

---

## Step 1: models.py 修正（✅ 完了）

すでに以下が追加済み：
- `Room` モデル
- `DeviceSession.room_id` フィールド
- `Job.room_id` フィールド
- UniqueConstraint の更新

---

## Step 2: utils/path_validator.py 作成（✅ 完了）

すでに以下が作成済み：
- `utils/__init__.py`
- `utils/path_validator.py`（以下の関数を含む）
  - `is_safe_workspace_path(path: str) -> bool`
  - `validate_workspace_path(path: str) -> str`
  - `ALLOWED_BASE_PATHS = ["/Users/macstudio/Projects", "/Users/macstudio/Documents"]`
  - `FORBIDDEN_PATHS = ["/System", "/Library", "/private", ...]`

---

## Step 3: session_manager.py 修正（✅ 完了）

すでに以下が修正済み：
- `ClaudeSessionManager._get_session_id_from_db(device_id: str, room_id: str)` - room_id パラメータ追加
- `ClaudeSessionManager._save_session_id_to_db(device_id: str, room_id: str, session_id: str)` - room_id パラメータ追加
- `ClaudeSessionManager.execute_job(prompt, device_id, room_id, workspace_path, continue_session)` - room_id, workspace_path パラメータ追加、cwd引数にworkspace_path使用
- `CodexSessionManager` - 上記と同様の修正を全て適用済み
- `SessionManager.execute_job(runner, prompt, device_id, room_id, workspace_path, continue_session)` - 新パラメータで各マネージャーに委譲
- `from typing import Dict, Optional` - インポート済み

---

## Step 4: job_manager.py 修正（✅ 完了）

すでに以下が修正済み：
- `create_job(runner, input_text, device_id, room_id, workspace_path, notify_token, background_tasks)` - room_id, workspace_path パラメータ追加
  - Job生成時に `room_id=room_id` 設定
  - `background_tasks.add_task(self._execute_job, job.id, workspace_path)` に workspace_path を渡すよう修正
- `_execute_job(self, job_id: str, workspace_path: str)` - workspace_path パラメータ追加
  - `self.session_manager.execute_job()` 呼び出し時に `room_id=job.room_id, workspace_path=workspace_path` を渡すよう修正
  - ログ出力に workspace_path 表示追加

---

## Step 5: main.py 修正

### ☐ 5.1 インポート追加

**前提**:
- Step 4 (job_manager.py修正) が完了していること
- 既存のFastAPI関連インポート (Depends, HTTPException, Session等) は変更不要

**変更箇所**: line 2-3, line 23, line 25付近

**追加が必要なインポート**:

1. **標準ライブラリ** (line 2-3付近):
```python
from __future__ import annotations

import uuid  # ✅ 追加 - create_room()でuuid.uuid4()を使用
from typing import List, Optional
```

2. **modelsインポート修正** (line 23):
```python
# 修正前
from models import Device, DeviceSession, utcnow

# 修正後（Job, Room を追加）
from models import Device, DeviceSession, Job, Room, utcnow

# 使用箇所:
# - Job: delete_room(), get_messages(), create_job()で使用
# - Room: create_room(), get_rooms(), delete_room(), get_messages(), create_job()で使用
# - DeviceSession: delete_room()で使用（既存）
# - utcnow: create_room()で使用（既存）
```

3. **ユーティリティインポート追加** (line 25付近):
```python
from session_manager import SessionManager
from sse_manager import sse_manager
from utils.path_validator import validate_workspace_path  # ✅ 追加 - create_room()でパス検証に使用
```

**既存で十分なインポート（変更不要）**:
- `from fastapi import Depends, HTTPException` - ルーム管理APIで使用
- `from sqlalchemy.orm import Session` - get_db()依存注入で使用

### ☐ 5.2 `CreateJobRequest` に `room_id` フィールド追加

**変更箇所**: line 55-59 付近

**修正前**:
```python
class CreateJobRequest(BaseModel):
    runner: str
    input_text: str
    device_id: str
    notify_token: Optional[str] = None
```

**修正後**:
```python
class CreateJobRequest(BaseModel):
    runner: str
    input_text: str
    device_id: str
    room_id: str  # 追加
    notify_token: Optional[str] = None
```

### ☐ 5.3 ルーム管理API追加（`@app.post("/jobs")` の前に追加）

```python
# ========== Room Management APIs ==========

class CreateRoomRequest(BaseModel):
    device_id: str
    name: str
    workspace_path: str
    icon: str = "folder"


@app.get("/rooms")
def get_rooms(
    device_id: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Get all rooms for a device."""
    rooms = db.query(Room).filter_by(device_id=device_id).order_by(Room.updated_at.desc()).all()
    return [room.to_dict() for room in rooms]


@app.post("/rooms")
def create_room(
    req: CreateRoomRequest,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Create a new room."""
    # パスのバリデーション
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

### ☐ 5.4 メッセージ履歴取得API追加

```python
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

### ☐ 5.5 セッションクリアAPI追加

```python
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

### ☐ 5.6 `@app.post("/jobs")` エンドポイントの更新

**前提**: Step 4 (job_manager.py修正) が完了し、`job_manager.create_job()` が `room_id` と `workspace_path` パラメータを受け取れるようになっていること

**変更箇所**: 既存の `@app.post("/jobs")` エンドポイント

**修正前**:
```python
@app.post("/jobs")
def create_job(
    req: CreateJobRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    return job_manager.create_job(
        runner=req.runner,
        input_text=req.input_text,
        device_id=req.device_id,
        background_tasks=background_tasks,
        notify_token=req.notify_token,
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
        background_tasks=background_tasks,
        notify_token=req.notify_token,
    )
```

---

## Step 6: database.py 確認

### ☐ 6.1 `init_db()` で Room をインポートしているか確認

```bash
grep -n "from models import" /Users/macstudio/Projects/RemotePrompt/remote-job-server/database.py
```

もし `Room` がインポートされていない場合、追加する：

```python
from models import DeviceSession, Job, Room  # Room を追加
```

そして `init_db()` 内で `Base.metadata.create_all(bind=engine)` が実行されていることを確認。

---

## Step 7: create_default_room.py 作成

### ☐ 7.1 スクリプト作成

**ファイルパス**: `/Users/macstudio/Projects/RemotePrompt/remote-job-server/create_default_room.py`

```python
"""Create a default room for testing."""
import uuid
from datetime import datetime, timezone

from database import SessionLocal
from models import Room


def utcnow():
    return datetime.now(timezone.utc)


def create_default_room(device_id: str, name: str, workspace_path: str):
    db = SessionLocal()
    try:
        # Check if room already exists
        existing = db.query(Room).filter_by(device_id=device_id, name=name).first()
        if existing:
            print(f"✅ Room '{name}' already exists for device {device_id}")
            print(f"   Room ID: {existing.id}")
            print(f"   Workspace: {existing.workspace_path}")
            return existing.id

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
        print(f"✅ Created default room '{name}' for device {device_id}")
        print(f"   Room ID: {room.id}")
        print(f"   Workspace: {room.workspace_path}")
        return room.id
    finally:
        db.close()


if __name__ == "__main__":
    DEVICE_ID = "iphone-test-1"
    ROOM_NAME = "RemotePrompt"
    WORKSPACE_PATH = "/Users/macstudio/Projects/RemotePrompt"

    room_id = create_default_room(DEVICE_ID, ROOM_NAME, WORKSPACE_PATH)
    print(f"\nℹ️  Use this room_id in API requests: {room_id}")
```

---

## Step 8: データベース再作成とテスト

### ☐ 8.1 データベース削除

```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
rm -f data/jobs.db
```

### ☐ 8.2 データベース再作成

```bash
source .venv/bin/activate
python3 -c "from database import init_db; init_db(); print('✅ Database created')"
```

### ☐ 8.3 デフォルトルーム作成

```bash
python3 create_default_room.py
```

出力例：
```
✅ Created default room 'RemotePrompt' for device iphone-test-1
   Room ID: 12345678-1234-1234-1234-123456789abc
   Workspace: /Users/macstudio/Projects/RemotePrompt

ℹ️  Use this room_id in API requests: 12345678-1234-1234-1234-123456789abc
```

### ☐ 8.4 サーバー起動テスト

```bash
source .venv/bin/activate
python3 -c "from main import app; print('✅ main.py imports successfully')"
```

エラーがなければ OK。

---

## Step 9: API動作テスト

**注記**:
- 以下のcurlコマンド例は `https://localhost:8443` を前提としています（本番用SSL設定）
- 開発環境で `uvicorn main:app --port 8000` のようにHTTPで起動している場合は、URLを `http://localhost:8000` に変更してください
- `-k` オプションは自己署名証明書を許可するためのものです（開発環境のみ）

### ☐ 9.1 環境変数設定

```bash
export API_KEY="your-api-key"
export DEVICE_ID="iphone-test-1"
export ROOM_ID="<Step 8.3で取得したroom_id>"
export BASE_URL="https://localhost:8443"  # 開発環境の場合は http://localhost:8000 など
```

### ☐ 9.2 ルーム一覧取得

```bash
# HTTPSの場合（本番・SSL設定済み）
curl -k -X GET \
  -H "x-api-key: $API_KEY" \
  "$BASE_URL/rooms?device_id=$DEVICE_ID" \
  2>/dev/null | python3 -m json.tool

# HTTPの場合（開発環境）
# curl -X GET \
#   -H "x-api-key: $API_KEY" \
#   "http://localhost:8000/rooms?device_id=$DEVICE_ID" \
#   2>/dev/null | python3 -m json.tool
```

期待される出力：
```json
[
  {
    "id": "12345678-...",
    "name": "RemotePrompt",
    "workspace_path": "/Users/macstudio/Projects/RemotePrompt",
    "icon": "folder",
    "device_id": "iphone-test-1",
    "created_at": "2025-11-19T...",
    "updated_at": "2025-11-19T..."
  }
]
```

### ☐ 9.3 ジョブ作成（room_id付き）

```bash
curl -k -X POST \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "runner": "claude",
    "input_text": "pwd コマンドを実行して、現在の作業ディレクトリを教えてください。",
    "device_id": "'"$DEVICE_ID"'",
    "room_id": "'"$ROOM_ID"'"
  }' \
  "https://localhost:8443/jobs" \
  2>/dev/null | python3 -m json.tool
```

期待される出力：
```json
{
  "id": "job-uuid",
  "runner": "claude",
  "input_text": "pwd コマンドを...",
  "device_id": "iphone-test-1",
  "room_id": "12345678-...",
  "status": "queued",
  ...
}
```

### ☐ 9.4 メッセージ履歴取得

```bash
curl -k -X GET \
  -H "x-api-key: $API_KEY" \
  "https://localhost:8443/messages?device_id=$DEVICE_ID&room_id=$ROOM_ID&runner=claude&limit=10" \
  2>/dev/null | python3 -m json.tool
```

---

## 修正内容まとめ

### ✅ v3で追加した内容

1. **session_manager.py の詳細手順** - 各メソッドの修正前/修正後を明記
2. **job_manager.py の詳細手順** - 実際のインスタンス変数 `self.session_manager` に基づく
3. **models.py の完了確認** - 既に修正済みであることを明記
4. **database.py の確認手順** - Room のインポート確認
5. **create_default_room.py** - デフォルトルーム作成スクリプト
6. **存在しないAPIの削除** - `sse_manager.broadcast_job_status()` 等の誤った参照を削除

### ✅ v2での修正（継承）

- `validate_api_key()` → `Depends(verify_api_key)` に統一
- `CreateJobRequest.prompt` → `CreateJobRequest.input_text` に統一

### ✅ 互換性維持

- `input_text` フィールドを維持することで、既存クライアント（iOS/watchOS）が動作し続ける
- `room_id` は新規フィールドとして追加

---

## 次のステップ

この修正版に基づいて実装を進めてください。全ての手順にチェックボックスがあるため、進捗を追跡できます。

実装完了後、Step 9のAPIテストで動作確認を行ってください。
