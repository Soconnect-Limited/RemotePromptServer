# 非対話モード方式 MacStudio ⇔ iPhone/Apple Watch ジョブ実行システム 詳細技術仕様書

作成日: 2025-11-16
最終更新: 2025-11-17
バージョン: 2.0（非対話モード + セッション管理版）
想定作成者: Nao

**変更履歴**:
- v1.0 (2025-11-16): PTY永続セッション方式での初版
- v2.0 (2025-11-17): 調査結果に基づき非対話モード + セッション管理方式に変更

---

## 目次

1. [概要とゴール](#1-概要とゴール)
2. [アーキテクチャ概要](#2-アーキテクチャ概要)
3. [非対話モード + セッション管理設計](#3-非対話モードセッション管理設計)
4. [MacStudio サーバー詳細仕様](#4-macstudio-サーバー詳細仕様)
5. [データベース設計](#5-データベース設計)
6. [REST API 仕様](#6-rest-api-仕様)
7. [プッシュ通知設計](#7-プッシュ通知設計)
8. [iOS アプリ仕様](#8-ios-アプリ仕様)
9. [watchOS アプリ仕様](#9-watchos-アプリ仕様)
10. [セキュリティとエラーハンドリング](#10-セキュリティとエラーハンドリング)
11. [実装ロードマップ](#11-実装ロードマップ)
12. [運用・保守](#12-運用保守)
13. [付録: PTY方式調査結果](#13-付録pty方式調査結果)

---

## 1. 概要とゴール

### 1.1 プロジェクトの目的

MacStudio上で動作するClaude Code / Codex CLIを、iPhoneとApple Watchから操作可能にし、**継続的な会話セッション**を維持しながらジョブを実行・管理するシステムを構築する。

### 1.2 重要な設計方針

- **定額プラン内での利用**: Claude Max、OpenAI ProプランのCLI使用に限定し、API従量課金を一切使用しない
- **非対話モード + セッション管理**: `--print`/`exec`による非対話モードと`--continue`/`resume`によるセッション継続で会話履歴とMCP接続を維持
- **両CLI対応**: Claude CodeとCodexの両方をサポートし、ユーザーが選択可能
- **Tailscale VPN内通信**: セキュリティを確保しつつHTTPで通信

### 1.3 主要機能

1. **iPhone からのジョブ投稿**
   - テキスト入力、CLI選択（claude/codex）
   - 継続的な会話として処理
   
2. **セッション管理**
   - デバイスごとに最新セッションIDを保存
   - 次回ジョブ実行時に自動的に前回セッションを継続
   - 会話履歴とMCP接続の保持
   
3. **プッシュ通知**
   - ジョブ完了時にiPhone/Apple Watchへ通知
   - 通知タップで結果画面へ遷移
   
4. **Apple Watch からの定型実行**
   - プリセットボタンでよく使うコマンドを即座に実行

### 1.4 前提環境

#### ネットワーク
- MacStudio: `192.168.11.110` (ローカル), `100.100.30.35` (Tailscale)
- iPhone/Watch: `100.76.45.62` (Tailscale, 例)

#### ソフトウェア
- MacStudio: macOS, Python 3.10+, FastAPI
- CLI: Claude Code, Codex（両方インストール済み）
- MCP: Serena, sequential-thinking, Context7（設定済み）
- VPN: Tailscale

#### 課金プラン
- Claude Max プラン（無制限CLI使用）
- OpenAI Pro プラン（無制限CLI使用）

---

## 2. アーキテクチャ概要

### 2.1 システム構成図

```
┌─────────────────────────────────────────────────────────┐
│                    iPhone / Apple Watch                  │
│  ┌──────────────┐          ┌──────────────┐            │
│  │ iOS App      │          │ watchOS App  │            │
│  │ - Job List   │◄────────►│ - Presets    │            │
│  │ - Job Detail │          │ - Quick Send │            │
│  │ - New Job    │          └──────────────┘            │
│  └──────┬───────┘                                        │
│         │ HTTP (Tailscale VPN)                          │
└─────────┼─────────────────────────────────────────────┘
          │
          │ REST API
          │
┌─────────▼─────────────────────────────────────────────┐
│              MacStudio Python Server                    │
│  ┌────────────────────────────────────────────┐        │
│  │           FastAPI REST Server               │        │
│  │  - /jobs (POST, GET)                        │        │
│  │  - /jobs/{id} (GET)                         │        │
│  │  - /register_device (POST)                  │        │
│  │  - /sessions (GET)                          │        │
│  └─────────┬──────────────────────────────────┘        │
│            │                                             │
│  ┌─────────▼──────────────────────────────────┐        │
│  │      Session Manager                        │        │
│  │  - Claude Session Tracker                   │        │
│  │  - Codex Session Tracker                    │        │
│  │  - Device Session Mapping                   │        │
│  └─────────┬──────────────────────────────────┘        │
│            │                                             │
│  ┌─────────▼──────────────────────────────────┐        │
│  │    subprocess.run() Layer                   │        │
│  │  - claude --print --resume <session_id>     │        │
│  │  - codex exec [resume <session_id>]         │        │
│  │  - Session ID DB persistence                │        │
│  └─────────┬──────────────────────────────────┘        │
│            │                                             │
│  ┌─────────▼──────────┬──────────────────────┐        │
│  │  claude --print    │  codex exec           │        │
│  │  + MCP Servers     │  + MCP Servers        │        │
│  │  - Serena          │  - Serena             │        │
│  │  - seq-thinking    │  - seq-thinking       │        │
│  │  - Context7        │  - Context7           │        │
│  └────────────────────┴───────────────────────┘        │
│                                                          │
│  ┌─────────────────────────────────────────────┐       │
│  │          SQLite Database                     │       │
│  │  - jobs table                                │       │
│  │  - devices table                             │       │
│  │  - device_sessions table (device→session)    │       │
│  └──────────────────────────────────────────────┘      │
│                                                          │
│  ┌─────────────────────────────────────────────┐       │
│  │       APNs Client (Push Notification)        │       │
│  └──────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────┘
```

### 2.2 データフロー

#### ジョブ実行フロー

```
1. iPhone → POST /jobs {runner: "claude", input_text: "質問", device_id: "iphone-nao-1"}
2. Server → Job DB に保存 (status: queued)
3. Server → Session Manager: execute_job("claude", "質問", device_id)
4. Session Manager → device_sessions DBからセッションIDを取得（初回はNone）
5a. 【初回】Session Manager → UUID生成、subprocess.run(['claude', '--print', '--session-id', <UUID>], input="質問")
5b. 【2回目以降】Session Manager → subprocess.run(['claude', '--print', '--resume', <session_id>], input="質問")
6. claude → 処理実行（MCP使用可）
7. subprocess ← claude: 応答テキスト
8. Session Manager → セッションIDを device_sessions DBに保存
9. Server ← 結果を受け取り
10. Job DB → 更新 (status: success, stdout: "応答", finished_at: now)
11. APNs → iPhone へプッシュ通知送信
12. iPhone ← 通知受信 → タップ → GET /jobs/{id} → 結果表示
13. 次回ジョブ → Session Manager が device_sessions DBから前回セッションIDを取得し、--resumeで継続
```

---

## 3. 非対話モード + セッション管理設計

### 3.1 設計方針の変更理由

**調査結果** (詳細は[Docs/Investigation_Report.md](../Investigation_Report.md)を参照):
- PTY方式: プロンプト検出の不安定性、ANSIエスケープ処理の複雑さ、信頼ダイアログの問題により実装困難
- 非対話モード: `claude --print`および`codex exec`が安定して動作し、MCPサーバーもサポート
- セッション継続: Claude Codeは`--continue`/`--resume`、Codexは`exec resume <session_id>`で会話履歴を保持可能

**Claude Code CLIオプション検証** (2025-11-17実施):
```bash
$ claude --help | grep -A 2 resume
-r, --resume [sessionId]    Resume a conversation - provide a session ID or
                            interactively select a conversation to resume
--session-id <uuid>         Use a specific session ID for the conversation
                            (must be a valid UUID)
```

✅ `--resume [sessionId]`: 既存セッションの継続をサポート（検証済み）
✅ `--session-id <uuid>`: 新規セッション作成時にUUID指定可能（検証済み）

### 3.2 Claude Code セッション管理

#### 基本実装

```python
import subprocess
import uuid
from typing import Optional
from database import SessionLocal
from models import DeviceSession
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class ClaudeSessionManager:
    """
    Claude Code非対話モード + セッション継続管理

    --resume <sessionId> と --session-id を使用してデバイス別セッション管理を実現
    """

    def __init__(self):
        self.trusted_directory = "/Users/nao/workspace"  # 信頼済みディレクトリ

    def _get_session_id_from_db(self, device_id: str) -> Optional[str]:
        """DBからデバイスのセッションIDを取得"""
        db = SessionLocal()
        try:
            session_record = db.query(DeviceSession).filter_by(
                device_id=device_id,
                runner='claude'
            ).first()
            return session_record.session_id if session_record else None
        finally:
            db.close()

    def _save_session_id_to_db(self, device_id: str, session_id: str):
        """セッションIDをDBに保存"""
        db = SessionLocal()
        try:
            session_record = db.query(DeviceSession).filter_by(
                device_id=device_id,
                runner='claude'
            ).first()

            if session_record:
                session_record.session_id = session_id
                session_record.updated_at = datetime.utcnow()
            else:
                session_record = DeviceSession(
                    device_id=device_id,
                    runner='claude',
                    session_id=session_id,
                    created_at=datetime.utcnow(),
                    updated_at=datetime.utcnow()
                )
                db.add(session_record)

            db.commit()
            logger.info(f"Saved Claude session {session_id} for device {device_id}")
        finally:
            db.close()

    def execute_job(self, prompt: str, device_id: str, continue_session: bool = True) -> dict:
        """
        Claude Codeを非対話モードで実行

        Args:
            prompt: ユーザー入力
            device_id: デバイスID (例: "iphone-nao-1")
            continue_session: 前回セッションを継続するか

        Returns:
            {
                'success': bool,
                'output': str,
                'session_id': str,
                'error': str
            }
        """
        try:
            cmd = ['claude', '--print', '--output-format', 'text']

            # デバイスごとのセッションIDを取得または新規生成
            session_id = None
            if continue_session:
                session_id = self._get_session_id_from_db(device_id)

            if session_id:
                # 既存セッションを継続
                cmd.extend(['--resume', session_id])
                logger.info(f"Resuming Claude session {session_id} for device {device_id}")
            else:
                # 新規セッションを作成（UUIDを事前生成）
                session_id = str(uuid.uuid4())
                cmd.extend(['--session-id', session_id])
                logger.info(f"Creating new Claude session {session_id} for device {device_id}")

            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=300,
                cwd=self.trusted_directory  # 信頼確認ダイアログをスキップ
            )

            # セッションIDをDBに保存
            if result.returncode == 0:
                self._save_session_id_to_db(device_id, session_id)

            return {
                'success': result.returncode == 0,
                'output': result.stdout,
                'session_id': session_id,
                'error': result.stderr
            }
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'output': '',
                'session_id': None,
                'error': 'Timeout'
            }
        except Exception as e:
            return {
                'success': False,
                'output': '',
                'session_id': None,
                'error': str(e)
            }
```

#### セッション継続の仕組み

**デバイス別セッション管理フロー**:

1. **初回ジョブ実行**
   - UUID生成: `session_id = str(uuid.uuid4())`
   - CLI実行: `claude --print --session-id <session_id> "質問"`
   - DB保存: `device_sessions`テーブルに`(device_id, runner='claude', session_id)`を保存

2. **2回目以降のジョブ実行**
   - DB取得: `device_sessions`テーブルから`session_id`を取得
   - CLI実行: `claude --print --resume <session_id> "次の質問"`
   - 会話履歴が継続される

**使用例**:
```bash
# 初回実行（セッションID: abc-123-def）
claude --print --session-id abc-123-def "今日の日付を教えて"

# 継続実行（同じセッションIDで継続）
claude --print --resume abc-123-def "それを英語で言うと?"
```

**利点**:
- ✅ デバイスごとに独立したセッション管理
- ✅ 複数デバイスでの会話混線を完全回避
- ✅ DB永続化によりプロセス再起動後も継続可能

---

### 3.3 Codex セッション管理

#### 基本実装

```python
import subprocess
import re
from typing import Dict, Optional
import logging
from datetime import datetime

from database import SessionLocal
from models import DeviceSession

logger = logging.getLogger(__name__)

class CodexSessionManager:
    """
    Codex exec + セッション管理

    セッションIDを抽出してDBに永続化し、
    次回実行時に自動的に前回セッションを継続する
    """

    def _get_session_id_from_db(self, device_id: str) -> Optional[str]:
        """DBからデバイスのセッションIDを取得"""
        db = SessionLocal()
        try:
            session_record = db.query(DeviceSession).filter_by(
                device_id=device_id,
                runner='codex'
            ).first()
            return session_record.session_id if session_record else None
        finally:
            db.close()

    def _save_session_id_to_db(self, device_id: str, session_id: str):
        """セッションIDをDBに保存"""
        db = SessionLocal()
        try:
            session_record = db.query(DeviceSession).filter_by(
                device_id=device_id,
                runner='codex'
            ).first()

            if session_record:
                session_record.session_id = session_id
                session_record.updated_at = datetime.utcnow()
            else:
                session_record = DeviceSession(
                    device_id=device_id,
                    runner='codex',
                    session_id=session_id,
                    created_at=datetime.utcnow(),
                    updated_at=datetime.utcnow()
                )
                db.add(session_record)

            db.commit()
            logger.info(f"Saved Codex session {session_id} for device {device_id}")
        finally:
            db.close()

    def execute_job(self, prompt: str, device_id: str, continue_session: bool = True) -> dict:
        """
        Codex execを実行

        Args:
            prompt: ユーザー入力
            device_id: デバイスID
            continue_session: 前回セッションを継続するか

        Returns:
            {
                'success': bool,
                'output': str,
                'session_id': Optional[str],
                'error': str
            }
        """
        try:
            cmd = ['codex', 'exec']

            # デバイスごとのセッションIDをDBから取得
            session_id = None
            if continue_session:
                session_id = self._get_session_id_from_db(device_id)

            if session_id:
                cmd.extend(['resume', session_id])
                logger.info(f"Resuming Codex session {session_id} for device {device_id}")

            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=300
            )

            # セッションIDを抽出
            session_match = re.search(r'session id: ([a-f0-9\-]+)', result.stdout)
            extracted_session_id = None
            if session_match:
                extracted_session_id = session_match.group(1)
                # セッションIDをDBに保存
                self._save_session_id_to_db(device_id, extracted_session_id)

            # 実際の応答部分を抽出
            output_lines = []
            lines = result.stdout.strip().split('\n')
            output_start = False
            for line in lines:
                # メタデータ行をスキップ
                if line.startswith('codex') or line.startswith('**結論**') or line.startswith('**根拠**'):
                    output_start = True
                if output_start:
                    output_lines.append(line)

            return {
                'success': result.returncode == 0,
                'output': '\n'.join(output_lines),
                'session_id': extracted_session_id,
                'error': result.stderr
            }
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'output': '',
                'session_id': None,
                'error': 'Timeout'
            }
        except Exception as e:
            return {
                'success': False,
                'output': '',
                'session_id': None,
                'error': str(e)
            }
```

#### セッション継続の仕組み

**`exec resume <sessionId>`**:
- セッションIDを明示的に指定して会話を継続
- デバイスごとにセッションIDを管理可能
- 複数デバイス対応に最適

**使用例**:
```bash
# 初回実行
codex exec "What is 5 * 7?"
# 出力: session id: 019a9134-ad13-76d1-9579-efff00095049

# 継続実行
codex exec resume 019a9134-ad13-76d1-9579-efff00095049 "That multiplied by 2?"
```

**デバイス別セッション管理フロー**:
1. 初回ジョブ: `codex exec` でセッションID生成
2. セッションIDを `device_sessions` テーブルに永続化 (device_id, runner='codex', session_id)
3. 次回ジョブ: DBから `session_id` を取得し、`codex exec resume <session_id>` で前回セッションを継続

---

### 3.4 統合セッションマネージャー

複数のCLIを統一的に管理するマネージャー

```python
import logging
from typing import Dict, Optional

logger = logging.getLogger(__name__)

class SessionManager:
    """
    Claude CodeとCodexの両方を統一的に管理
    """

    def __init__(self):
        self.claude_manager = ClaudeSessionManager()
        self.codex_manager = CodexSessionManager()

    def execute_job(self, runner: str, prompt: str, device_id: str,
                   continue_session: bool = True) -> dict:
        """
        指定されたrunnerでジョブを実行

        Args:
            runner: "claude" or "codex"
            prompt: ユーザー入力
            device_id: デバイスID
            continue_session: セッションを継続するか

        Returns:
            実行結果の辞書
        """
        if runner == "claude":
            return self.claude_manager.execute_job(prompt, device_id, continue_session)
        elif runner == "codex":
            return self.codex_manager.execute_job(prompt, device_id, continue_session)
        else:
            return {
                'success': False,
                'output': '',
                'error': f'Unknown runner: {runner}'
            }

    def get_session_status(self, runner: str, device_id: str) -> dict:
        """セッション状態を取得"""
        if runner == "codex":
            session_id = self.codex_manager._get_session_id_from_db(device_id)
            return {
                'exists': session_id is not None,
                'session_id': session_id
            }
        elif runner == "claude":
            session_id = self.claude_manager._get_session_id_from_db(device_id)
            return {
                'exists': session_id is not None,
                'session_id': session_id
            }
        else:
            return {'exists': False, 'session_id': None}
```

---

### 3.5 MCP サーバー対応

両CLIとも非対話モードでMCPサーバーをサポート

**Claude Code + MCP**:
```bash
echo "Use the serena mcp tool to list files" | claude --print
```

**Codex + MCP**:
```bash
codex exec "Use serena to read the config file"
```

**動作確認済みMCPサーバー**:
- Serena
- sequential-thinking
- Context7

---

## 4. MacStudio サーバー詳細仕様

### 4.1 技術スタック

- **言語**: Python 3.10+
- **Webフレームワーク**: FastAPI
- **非同期処理**: asyncio, BackgroundTasks
- **DB**: SQLite3 + SQLAlchemy
- **プッシュ通知**: PyAPNs2
- **プロセス管理**: subprocess, uuid

### 4.2 ディレクトリ構成

```
~/remote-job-server/
├── main.py                 # FastAPIエントリポイント
├── config.py               # 設定値
├── models.py               # SQLAlchemyモデル
├── database.py             # DB接続管理
├── session_manager.py      # ClaudeSessionManager, CodexSessionManager, SessionManager
├── job_manager.py          # ジョブ実行ロジック
├── notify.py               # APNs通知
├── requirements.txt
├── .env                    # 環境変数（APNsキーなど）
└── data/
    └── jobs.db             # SQLiteデータベース
```

### 4.3 主要モジュール

#### main.py（FastAPI）

```python
from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List
import uvicorn

from database import engine, SessionLocal
from models import Base, Job, Device, DeviceSession
from job_manager import JobManager
from session_manager import SessionManager
from config import settings

# テーブル作成
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Remote Job Server")

# CORS設定（Tailscale内のみ想定）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ジョブマネージャーのシングルトン
job_manager = JobManager()

# リクエストモデル
class CreateJobRequest(BaseModel):
    runner: str  # "claude" or "codex"
    input_text: str
    device_id: str  # デバイスID（必須）

class RegisterDeviceRequest(BaseModel):
    device_id: str
    device_token: str

# エンドポイント
@app.post("/register_device")
async def register_device(req: RegisterDeviceRequest):
    db = SessionLocal()
    try:
        device = db.query(Device).filter_by(device_id=req.device_id).first()
        if device:
            device.device_token = req.device_token
        else:
            device = Device(device_id=req.device_id, device_token=req.device_token)
            db.add(device)
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()

@app.post("/jobs")
async def create_job(req: CreateJobRequest, background_tasks: BackgroundTasks):
    return await job_manager.create_job(
        runner=req.runner,
        input_text=req.input_text,
        device_id=req.device_id,
        background_tasks=background_tasks
    )

@app.get("/jobs")
async def list_jobs(limit: int = 20, status: Optional[str] = None):
    db = SessionLocal()
    try:
        query = db.query(Job).order_by(Job.created_at.desc()).limit(limit)
        if status:
            query = query.filter_by(status=status)
        jobs = query.all()
        return [job.to_dict() for job in jobs]
    finally:
        db.close()

@app.get("/jobs/{job_id}")
async def get_job(job_id: str):
    db = SessionLocal()
    try:
        job = db.query(Job).filter_by(id=job_id).first()
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        return job.to_dict()
    finally:
        db.close()

@app.get("/sessions")
async def get_sessions(device_id: str):
    """デバイスごとのセッション状態を取得"""
    return {
        "claude": job_manager.session_manager.get_session_status("claude", device_id),
        "codex": job_manager.session_manager.get_session_status("codex", device_id)
    }

@app.delete("/sessions/{runner}")
async def delete_session(runner: str, device_id: str):
    """指定されたデバイスのセッションを削除"""
    db = SessionLocal()
    try:
        from models import DeviceSession
        session_record = db.query(DeviceSession).filter_by(
            device_id=device_id,
            runner=runner
        ).first()

        if session_record:
            db.delete(session_record)
            db.commit()
            return {
                "status": "deleted",
                "runner": runner,
                "device_id": device_id
            }
        else:
            raise HTTPException(status_code=404, detail="Session not found")
    finally:
        db.close()

@app.get("/health")
async def health():
    return {"status": "ok"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

#### job_manager.py

```python
import uuid
from datetime import datetime
from fastapi import BackgroundTasks
from database import SessionLocal
from models import Job
from session_manager import SessionManager
from notify import send_push_notification
import logging

logger = logging.getLogger(__name__)

class JobManager:
    def __init__(self):
        self.session_manager = SessionManager()
    
    async def create_job(self, runner: str, input_text: str, 
                        device_id: str, background_tasks: BackgroundTasks):
        """ジョブを作成してバックグラウンドで実行"""
        db = SessionLocal()
        try:
            # ジョブレコード作成
            job = Job(
                id=str(uuid.uuid4()),
                runner=runner,
                input_text=input_text,
                device_id=device_id,
                status="queued",
                created_at=datetime.utcnow()
            )

            # device_tokenを取得
            from models import Device
            device = db.query(Device).filter_by(device_id=device_id).first()
            if device:
                job.notify_token = device.device_token
            
            db.add(job)
            db.commit()
            db.refresh(job)
            
            # バックグラウンドで実行
            background_tasks.add_task(self._execute_job, job.id)
            
            return {
                "id": job.id,
                "status": job.status
            }
        finally:
            db.close()
    
    def _execute_job(self, job_id: str):
        """ジョブを実際に実行（バックグラウンドスレッド）"""
        db = SessionLocal()
        try:
            job = db.query(Job).filter_by(id=job_id).first()
            if not job:
                return
            
            # ステータス更新: running
            job.status = "running"
            job.started_at = datetime.utcnow()
            db.commit()

            # SessionManagerでジョブ実行
            logger.info(f"Executing job {job_id} with {job.runner}")
            result = self.session_manager.execute_job(
                runner=job.runner,
                prompt=job.input_text,
                device_id=job.device_id,
                continue_session=True
            )
            
            # 結果を保存
            if result['success']:
                job.status = "success"
                job.exit_code = 0
                job.stdout = result['output']
                job.stderr = ""
            else:
                job.status = "failed"
                job.exit_code = 1
                job.stdout = ""
                job.stderr = result.get('error', 'Unknown error')
            
            job.finished_at = datetime.utcnow()
            db.commit()
            
            # プッシュ通知送信
            if job.notify_token:
                send_push_notification(
                    device_token=job.notify_token,
                    job_id=job.id,
                    runner=job.runner,
                    status=job.status
                )
            
            logger.info(f"Job {job_id} completed with status: {job.status}")
            
        except Exception as e:
            logger.error(f"Job {job_id} failed with exception: {e}")
            job = db.query(Job).filter_by(id=job_id).first()
            if job:
                job.status = "failed"
                job.exit_code = 1
                job.stderr = str(e)
                job.finished_at = datetime.utcnow()
                db.commit()
        finally:
            db.close()
```

---

## 5. データベース設計

### 5.1 スキーマ定義

#### jobs テーブル

```sql
CREATE TABLE jobs (
    id TEXT PRIMARY KEY,              -- UUID v4
    runner TEXT NOT NULL,              -- "claude" or "codex"
    input_text TEXT NOT NULL,          -- ユーザー入力
    device_id TEXT NOT NULL,           -- デバイスID (例: "iphone-nao-1")
    status TEXT NOT NULL,              -- queued/running/success/failed
    exit_code INTEGER,                 -- 0=成功, 1=失敗
    stdout TEXT,                       -- 標準出力
    stderr TEXT,                       -- エラー出力
    created_at DATETIME NOT NULL,      -- 作成日時
    started_at DATETIME,               -- 実行開始日時
    finished_at DATETIME,              -- 終了日時
    notify_token TEXT                  -- APNs device token
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at DESC);
CREATE INDEX idx_jobs_device_id ON jobs(device_id);
```

#### devices テーブル

```sql
CREATE TABLE devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT UNIQUE NOT NULL,    -- "iphone-nao-1"
    device_token TEXT NOT NULL,         -- APNs token
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);
```

#### device_sessions テーブル（セッション継続用）

```sql
CREATE TABLE device_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,            -- "iphone-nao-1"
    runner TEXT NOT NULL,               -- "claude" or "codex"
    session_id TEXT NOT NULL,           -- Claude/Codex両方のセッションID
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE(device_id, runner)           -- デバイス+runnerの組み合わせで一意
);

CREATE INDEX idx_device_sessions ON device_sessions(device_id, runner);
```

**セッションID管理方式**:
- **Claude Code**: `--session-id <UUID>`で新規作成、`--resume <sessionId>`で継続
- **Codex**: `codex exec`で自動生成、`exec resume <sessionId>`で継続

### 5.2 SQLAlchemy モデル

```python
# models.py
from sqlalchemy import Column, Integer, String, DateTime, Text
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

Base = declarative_base()

class Job(Base):
    __tablename__ = 'jobs'

    id = Column(String(36), primary_key=True)
    runner = Column(String(20), nullable=False)
    input_text = Column(Text, nullable=False)
    device_id = Column(String(100), nullable=False)
    status = Column(String(20), nullable=False)
    exit_code = Column(Integer)
    stdout = Column(Text)
    stderr = Column(Text)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    notify_token = Column(String(255))
    
    def to_dict(self):
        return {
            'id': self.id,
            'runner': self.runner,
            'input_text': self.input_text,
            'device_id': self.device_id,
            'status': self.status,
            'exit_code': self.exit_code,
            'stdout': self.stdout,
            'stderr': self.stderr,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'started_at': self.started_at.isoformat() if self.started_at else None,
            'finished_at': self.finished_at.isoformat() if self.finished_at else None
        }

class Device(Base):
    __tablename__ = 'devices'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    device_id = Column(String(100), unique=True, nullable=False)
    device_token = Column(String(255), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
```

---

## 6. REST API 仕様

### 6.1 ベースURL

```
http://100.100.30.35:8000
```

### 6.2 エンドポイント詳細

#### POST /register_device

デバイスのAPNs tokenを登録。

**Request:**
```json
{
  "device_id": "iphone-nao-1",
  "device_token": "apns_token_here_64_chars"
}
```

**Response:**
```json
{
  "status": "ok"
}
```

---

#### POST /jobs

新規ジョブを作成・実行。

**Request:**
```json
{
  "runner": "claude",
  "input_text": "Pythonでクイックソートを実装して",
  "device_id": "iphone-nao-1"
}
```

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued"
}
```

**処理フロー:**
1. DBにジョブレコード作成（status: queued）
2. BackgroundTasksで`_execute_job()`を実行
3. SessionManager経由で非対話モードCLI（`claude --print` / `codex exec`）を起動
4. 結果をDBに保存
5. APNs通知送信

---

#### GET /jobs

ジョブ一覧を取得。

**Query Parameters:**
- `limit`: 最大件数（デフォルト: 20）
- `status`: フィルタ（queued/running/success/failed）

**Response:**
```json
[
  {
    "id": "job-uuid-1",
    "runner": "claude",
    "status": "success",
    "created_at": "2025-11-16T10:00:00",
    "finished_at": "2025-11-16T10:02:30"
  },
  ...
]
```

---

#### GET /jobs/{id}

単一ジョブの詳細を取得。

**Response:**
```json
{
  "id": "job-uuid-1",
  "runner": "claude",
  "input_text": "Pythonでクイックソートを実装して",
  "status": "success",
  "exit_code": 0,
  "stdout": "実装したコードは以下です:\n\ndef quicksort(arr):\n...",
  "stderr": "",
  "created_at": "2025-11-16T10:00:00",
  "started_at": "2025-11-16T10:00:05",
  "finished_at": "2025-11-16T10:02:30"
}
```

---

#### GET /sessions

デバイスごとのセッション状態を取得。

**Query Parameters:**
- `device_id`: デバイスID（必須）

**Response:**
```json
{
  "claude": {
    "exists": true,
    "session_id": "abc-123-def-456"
  },
  "codex": {
    "exists": true,
    "session_id": "789-ghi-jkl-012"
  }
}
```

---

#### DELETE /sessions/{runner}

指定されたデバイスのセッションを削除（新規会話開始）。

**Query Parameters:**
- `device_id`: デバイスID（必須）

**Example:**
```
DELETE /sessions/claude?device_id=iphone-nao-1
```

**Response:**
```json
{
  "status": "deleted",
  "runner": "claude",
  "device_id": "iphone-nao-1"
}
```

---

## 7. プッシュ通知設計

### 7.1 APNs設定

#### 必要なファイル
- `.p8` ファイル（APNs認証キー）
- Team ID
- Key ID
- Bundle ID

#### 環境変数（.env）
```bash
APNS_KEY_PATH=/path/to/AuthKey_XXXXXXXX.p8
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=YYYYYYYYYY
APNS_BUNDLE_ID=com.example.remotejob
APNS_USE_SANDBOX=false  # 本番環境
```

### 7.2 通知送信実装

```python
# notify.py
from apns2.client import APNsClient
from apns2.payload import Payload
from config import settings
import logging

logger = logging.getLogger(__name__)

def send_push_notification(device_token: str, job_id: str, runner: str, status: str):
    """
    APNs経由でプッシュ通知を送信
    
    Args:
        device_token: デバイストークン
        job_id: ジョブID
        runner: "claude" or "codex"
        status: "success" or "failed"
    """
    try:
        client = APNsClient(
            credentials=settings.APNS_KEY_PATH,
            use_sandbox=settings.APNS_USE_SANDBOX
        )
        
        # ペイロード作成
        title = "ジョブ完了" if status == "success" else "ジョブ失敗"
        body = f"[{runner}] {job_id[:8]}: {status}"
        
        payload = Payload(
            alert={
                "title": title,
                "body": body
            },
            sound="default",
            custom={
                "job_id": job_id
            }
        )
        
        # 送信
        client.send_notification(
            device_token,
            payload,
            topic=settings.APNS_BUNDLE_ID
        )
        
        logger.info(f"Push notification sent for job {job_id}")
        
    except Exception as e:
        logger.error(f"Failed to send push notification: {e}")
```

### 7.3 通知ペイロード例

```json
{
  "aps": {
    "alert": {
      "title": "ジョブ完了",
      "body": "[claude] 550e8400: success"
    },
    "sound": "default"
  },
  "job_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

---

## 8. iOS アプリ仕様

### 8.1 プロジェクト構成

```
RemoteJobClient/
├── RemoteJobClient.xcodeproj
├── RemoteJobClient/
│   ├── App/
│   │   ├── RemoteJobClientApp.swift
│   │   └── AppDelegate.swift
│   ├── Models/
│   │   ├── Job.swift
│   │   └── Device.swift
│   ├── Services/
│   │   ├── APIClient.swift
│   │   └── PushNotificationManager.swift
│   ├── Views/
│   │   ├── JobsListView.swift
│   │   ├── JobDetailView.swift
│   │   └── NewJobView.swift
│   └── Info.plist
└── RemoteJobClient Watch/
    └── ...
```

### 8.2 データモデル

```swift
// Job.swift
import Foundation

struct Job: Identifiable, Codable {
    let id: String
    let runner: String
    let inputText: String
    let status: String
    let exitCode: Int?
    let stdout: String?
    let stderr: String?
    let createdAt: Date?
    let startedAt: Date?
    let finishedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, runner, status, stdout, stderr
        case inputText = "input_text"
        case exitCode = "exit_code"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

struct CreateJobRequest: Codable {
    let runner: String
    let inputText: String
    let deviceId: String  // 必須（サーバー側 device_id NOT NULL に対応）

    enum CodingKeys: String, CodingKey {
        case runner
        case inputText = "input_text"
        case deviceId = "device_id"
    }
}
```

### 8.3 API Client

```swift
// APIClient.swift
import Foundation

class APIClient: ObservableObject {
    static let shared = APIClient()
    
    private let baseURL = "http://100.100.30.35:8000"
    private let deviceId = "iphone-nao-1"
    
    func registerDevice(deviceToken: String) async throws {
        let url = URL(string: "\(baseURL)/register_device")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "device_id": deviceId,
            "device_token": deviceToken
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }
    
    func fetchJobs(limit: Int = 20) async throws -> [Job] {
        let url = URL(string: "\(baseURL)/jobs?limit=\(limit)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Job].self, from: data)
    }
    
    func fetchJob(id: String) async throws -> Job {
        let url = URL(string: "\(baseURL)/jobs/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Job.self, from: data)
    }
    
    func createJob(runner: String, inputText: String) async throws -> Job {
        let url = URL(string: "\(baseURL)/jobs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = CreateJobRequest(runner: runner, inputText: inputText, deviceId: deviceId)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Job.self, from: data)
    }
}

enum APIError: Error {
    case requestFailed
    case invalidResponse
}
```

### 8.4 主要画面

#### JobsListView.swift

```swift
import SwiftUI

struct JobsListView: View {
    @State private var jobs: [Job] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            List(jobs) { job in
                NavigationLink(destination: JobDetailView(jobId: job.id)) {
                    JobRowView(job: job)
                }
            }
            .navigationTitle("Jobs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: NewJobView()) {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await loadJobs()
            }
            .task {
                await loadJobs()
            }
        }
    }
    
    func loadJobs() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            jobs = try await APIClient.shared.fetchJobs()
        } catch {
            print("Failed to load jobs: \(error)")
        }
    }
}

struct JobRowView: View {
    let job: Job
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(job.runner)
                    .font(.caption)
                    .padding(4)
                    .background(runnerColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                Text(job.status)
                    .font(.caption)
                    .foregroundColor(statusColor)
                
                Spacer()
                
                if let createdAt = job.createdAt {
                    Text(createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(job.inputText)
                .lineLimit(2)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
    
    var runnerColor: Color {
        job.runner == "claude" ? .blue : .green
    }
    
    var statusColor: Color {
        switch job.status {
        case "success": return .green
        case "failed": return .red
        case "running": return .orange
        default: return .gray
        }
    }
}
```

#### NewJobView.swift

```swift
import SwiftUI

struct NewJobView: View {
    @Environment(\.dismiss) var dismiss
    @State private var inputText = ""
    @State private var selectedRunner = "claude"
    @State private var isSubmitting = false
    
    let runners = ["claude", "codex"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Runner")) {
                    Picker("CLI Tool", selection: $selectedRunner) {
                        ForEach(runners, id: \.self) { runner in
                            Text(runner.capitalized).tag(runner)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Input")) {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 200)
                }
                
                Section {
                    Button(action: submitJob) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("実行")
                        }
                    }
                    .disabled(inputText.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("新規ジョブ")
            .navigationBarItems(trailing: Button("閉じる") {
                dismiss()
            })
        }
    }
    
    func submitJob() {
        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            
            do {
                _ = try await APIClient.shared.createJob(
                    runner: selectedRunner,
                    inputText: inputText
                )
                dismiss()
            } catch {
                print("Failed to create job: \(error)")
            }
        }
    }
}
```

### 8.5 Info.plist（ATS設定）

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>100.100.30.35</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

### 8.6 プッシュ通知ハンドリング

```swift
// AppDelegate.swift
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerForPushNotifications()
        return true
    }
    
    func registerForPushNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
    }
    
    func application(_ application: UIApplication,
                    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            try? await APIClient.shared.registerDevice(deviceToken: tokenString)
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let jobId = userInfo["job_id"] as? String {
            // JobDetailViewへ遷移（NotificationCenterで通知）
            NotificationCenter.default.post(
                name: .openJobDetail,
                object: nil,
                userInfo: ["jobId": jobId]
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let openJobDetail = Notification.Name("openJobDetail")
}
```

---

## 9. watchOS アプリ仕様

### 9.1 機能概要

Apple Watchから定型文ボタンをタップ → iPhone経由でジョブを投稿。

### 9.2 WatchConnectivity設定

#### Watch側（送信）

```swift
// WatchViewModel.swift
import WatchKit
import WatchConnectivity

class WatchViewModel: NSObject, ObservableObject, WCSessionDelegate {
    var session: WCSession?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    func sendPreset(action: String, runner: String) {
        guard let session = session, session.isReachable else { return }
        
        let message = [
            "type": "preset",
            "action": action,
            "runner": runner
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending message: \(error)")
        }
    }
    
    // WCSessionDelegate methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
```

#### iPhone側（受信）

```swift
// WatchConnectivityManager.swift
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    var session: WCSession?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard message["type"] as? String == "preset" else { return }
        
        let action = message["action"] as? String ?? ""
        let runner = message["runner"] as? String ?? "claude"
        
        // アクションに応じたテキストを生成
        let inputText = presetTextForAction(action)
        
        // ジョブを投稿
        Task {
            try? await APIClient.shared.createJob(runner: runner, inputText: inputText)
        }
    }
    
    func presetTextForAction(_ action: String) -> String {
        switch action {
        case "daily_batch":
            return "今日のバッチ処理を開始してください"
        case "status_check":
            return "現在のシステムステータスを確認してください"
        default:
            return action
        }
    }
    
    // WCSessionDelegate methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
}
```

### 9.3 Watch画面

```swift
// PresetButtonsView.swift (watchOS)
import SwiftUI

struct PresetButtonsView: View {
    @StateObject private var viewModel = WatchViewModel()
    
    let presets: [(title: String, action: String, runner: String)] = [
        ("今日のバッチ", "daily_batch", "claude"),
        ("ステータス確認", "status_check", "codex"),
        ("ログ確認", "check_logs", "claude")
    ]
    
    var body: some View {
        List(presets, id: \.action) { preset in
            Button(action: {
                viewModel.sendPreset(action: preset.action, runner: preset.runner)
            }) {
                VStack(alignment: .leading) {
                    Text(preset.title)
                        .font(.headline)
                    Text(preset.runner)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("プリセット")
    }
}
```

---

## 10. セキュリティとエラーハンドリング

### 10.1 セキュリティ対策

#### ネットワークセキュリティ
- **Tailscale VPN必須**: 外部からのアクセスを完全にブロック
- **ファイアウォール**: MacStudioでポート8000をTailscaleインターフェースのみに制限

```bash
# macOS Firewall設定（例）
sudo pfctl -e
sudo pfctl -f /etc/pf.conf
```

#### 認証（将来拡張）
- 初期実装: 認証なし（Tailscale内のみ）
- 将来: `X-API-Key` ヘッダーによる簡易認証

```python
# 将来の実装例
from fastapi import Header, HTTPException

async def verify_api_key(x_api_key: str = Header(...)):
    if x_api_key != settings.API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")
```

### 10.2 エラーハンドリング

#### セッション実行エラー

```python
class SessionExecutionError(Exception):
    """セッション実行関連のエラー"""
    pass

class SessionTimeoutError(SessionExecutionError):
    """セッション実行がタイムアウト"""
    pass

class SessionDBError(SessionExecutionError):
    """DB操作でエラー発生"""
    pass
```

#### 自動リトライ

```python
def _execute_job_with_retry(self, job_id: str, max_retries: int = 3):
    """リトライ機能付きジョブ実行"""
    for attempt in range(max_retries):
        try:
            self._execute_job(job_id)
            break
        except subprocess.TimeoutExpired:
            logger.warning(f"Job timeout, retrying ({attempt+1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(5)
            else:
                raise SessionTimeoutError(f"Job {job_id} timed out after {max_retries} attempts")
        except Exception as e:
            logger.error(f"Job execution error: {e}")
            raise
```

#### タイムアウト処理

- **CLI実行タイムアウト**: 300秒（5分）
- **DB接続タイムアウト**: 5秒

### 10.3 ロギング

```python
# config.py
import logging
from logging.handlers import RotatingFileHandler

def setup_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    
    # ファイルハンドラー
    handler = RotatingFileHandler(
        'logs/server.log',
        maxBytes=10*1024*1024,  # 10MB
        backupCount=5
    )
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    # コンソールハンドラー
    console = logging.StreamHandler()
    console.setFormatter(formatter)
    logger.addHandler(console)
```

---

## 11. 実装ロードマップ

### Phase 1: 非対話モード実装（1-2日）

**目標**: subprocess経由でclaude/codexと通信できることを確認

**タスク**:
1. `session_manager.py` の基本実装
   - `ClaudeSessionManager` クラス
   - `CodexSessionManager` クラス
   - セッションID抽出ロジック
2. テストスクリプト作成
   ```python
   # test_session.py
   claude_mgr = ClaudeSessionManager()
   result = claude_mgr.execute_job("こんにちは", "test-device", continue_session=True)
   print(result)
   ```
3. 両方のCLI（claude/codex）で動作確認

**成功基準**:
- ✅ claudeから応答取得（--print動作確認）
- ✅ codexから応答取得（exec動作確認）
- ✅ セッション継続機能の動作確認

---

### Phase 2: 統合SessionManager実装（1-2日）

**目標**: 両CLIを統一的に管理する

**タスク**:
1. `SessionManager` クラス実装
2. デバイス別セッション管理
3. device_sessionsテーブル連携
4. エラーハンドリング強化

**成功基準**:
- ✅ claude/codex両方の実行に対応
- ✅ デバイスごとのセッション保存・継続
- ✅ タイムアウトとエラー処理

---

### Phase 3: FastAPI + DB（3-4日）

**目標**: REST APIとデータベースを統合

**タスク**:
1. SQLAlchemyモデル定義（Job, Device, DeviceSession）
2. FastAPIエンドポイント実装
   - POST /jobs
   - GET /jobs
   - GET /jobs/{id}
3. `JobManager` でSessionManagerと連携
4. BackgroundTasksでジョブ実行

**成功基準**:
- ✅ curlでジョブ作成・取得可能
- ✅ ジョブがSessionManagerで実行される
- ✅ 結果がDBに保存される
- ✅ セッションIDが device_sessions テーブルに保存される

---

### Phase 4: iOS アプリ基本UI（3-5日）

**目標**: iPhone からジョブの作成・閲覧ができる

**タスク**:
1. Xcodeプロジェクト作成
2. `APIClient` 実装
3. `JobsListView` 実装
4. `JobDetailView` 実装
5. `NewJobView` 実装
6. ATS設定（Info.plist）

**成功基準**:
- ✅ iPhone シミュレータからジョブ作成
- ✅ ジョブ一覧の表示
- ✅ ジョブ詳細の表示（stdout確認）

---

### Phase 5: プッシュ通知（2-3日）

**目標**: ジョブ完了時にiPhoneへ通知

**タスク**:
1. APNs設定（.p8キー取得）
2. `notify.py` 実装
3. iOS側: UNUserNotificationCenter設定
4. device token登録フロー
5. 通知タップ時のジョブ詳細表示

**成功基準**:
- ✅ ジョブ完了時にプッシュ通知受信
- ✅ 通知タップでジョブ詳細画面表示

---

### Phase 6: Apple Watch連携（2-3日）

**目標**: Watchからプリセットボタンでジョブ実行

**タスク**:
1. watchOSターゲット作成
2. WatchConnectivity設定（Watch/iPhone両方）
3. プリセットボタンUI
4. メッセージ送受信ロジック

**成功基準**:
- ✅ Watchボタンタップでジョブ作成
- ✅ iPhoneで通知受信

---

### Phase 7: 安定化・テスト（3-5日）

**タスク**:
1. エラーハンドリング強化
2. ログ整備
3. 長時間実行テスト
4. メモリリーク確認
5. ドキュメント整備

---

## 12. 運用・保守

### 12.1 サーバー起動

#### 手動起動
```bash
cd ~/remote-job-server
python3 main.py
```

#### systemd（自動起動）

```ini
# /etc/systemd/system/remote-job-server.service
[Unit]
Description=Remote Job Server
After=network.target

[Service]
Type=simple
User=nao
WorkingDirectory=/Users/nao/remote-job-server
ExecStart=/usr/local/bin/python3 main.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable remote-job-server
sudo systemctl start remote-job-server
```

### 12.2 ログ監視

```bash
# リアルタイムログ
tail -f ~/remote-job-server/logs/server.log

# エラーのみ抽出
grep ERROR ~/remote-job-server/logs/server.log
```

### 12.3 セッション健全性チェック

```bash
# セッション状態API（device_id必須）
curl "http://100.100.30.35:8000/sessions?device_id=iphone-nao-1"

# 応答例
{
  "claude": {
    "exists": true,
    "session_id": "550e8400-e29b-41d4-a716-446655440000"
  },
  "codex": {
    "exists": true,
    "session_id": "codex_session_abc123xyz"
  }
}
```

### 12.4 バックアップ

```bash
# DBバックアップ（日次）
cp ~/remote-job-server/data/jobs.db ~/backups/jobs_$(date +%Y%m%d).db

# 7日以上前のバックアップ削除
find ~/backups -name "jobs_*.db" -mtime +7 -delete
```

### 12.5 トラブルシューティング

#### セッションがクラッシュする

```bash
# ログ確認
grep "Session crashed" ~/remote-job-server/logs/server.log

# セッションを削除して次回ジョブで新規セッション開始
curl -X DELETE "http://100.100.30.35:8000/sessions/claude?device_id=iphone-nao-1"
# 次回のジョブ投稿時に新しいセッションIDが自動生成される
```

#### メモリ使用量増加

```bash
# プロセス監視
ps aux | grep python

# 必要に応じてサーバー再起動
sudo systemctl restart remote-job-server
```

---

## 付録A: 設定ファイル例

### config.py

```python
import os
from pydantic import BaseSettings

class Settings(BaseSettings):
    # Server
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    
    # Database
    DATABASE_URL: str = "sqlite:///./data/jobs.db"
    
    # APNs
    APNS_KEY_PATH: str = os.getenv("APNS_KEY_PATH", "")
    APNS_KEY_ID: str = os.getenv("APNS_KEY_ID", "")
    APNS_TEAM_ID: str = os.getenv("APNS_TEAM_ID", "")
    APNS_BUNDLE_ID: str = os.getenv("APNS_BUNDLE_ID", "com.example.remotejob")
    APNS_USE_SANDBOX: bool = os.getenv("APNS_USE_SANDBOX", "false").lower() == "true"
    
    # Logging
    LOG_LEVEL: str = "INFO"
    LOG_FILE: str = "logs/server.log"
    
    class Config:
        env_file = ".env"

settings = Settings()
```

### requirements.txt

```
fastapi==0.104.1
uvicorn==0.24.0
sqlalchemy==2.0.23
apns2==0.7.2
pydantic==2.5.0
python-dotenv==1.0.0
```

---

## 付録B: MCP設定確認

Claude Code / Codex で使用しているMCP設定を確認:

```bash
# Claude Code
cat ~/.config/claude-code/config.json

# Codex
cat ~/.codex/config.toml
```

MCPサーバー（Serena, sequential-thinking, Context7）が正しく設定されていることを確認してください。

---

## 13. 付録: PTY方式調査結果

当初、PTY（疑似端末）を使用した永続セッション方式を検討しましたが、調査の結果、以下の問題により実装困難と判断しました。

### PTY方式の問題点

1. **プロンプト検出の不安定性**
   - Claude Code / Codexのプロンプト記号（`›`/`>`）の検出が不確実
   - ANSI エスケープシーケンスの除去が必要で処理が複雑

2. **信頼確認ダイアログの問題**
   - Claude Codeの信頼確認ダイアログがPTY経由で表示される
   - 自動化困難（Expectスクリプトでも安定せず）

3. **プロセス管理の複雑さ**
   - fork/pty.openpty()によるプロセス管理
   - セッションクラッシュ時の再起動処理
   - メモリリークやゾンビプロセスのリスク

### 詳細な調査レポート

PTY方式の調査過程と実験結果の詳細は以下のドキュメントを参照してください:

- **[Docs/Investigation_Report.md](../Investigation_Report.md)**: PTY調査の全記録
  - 試行錯誤の過程
  - Claude Code / Codexそれぞれのテスト結果
  - 非対話モードの発見と検証
  - セッション継続機能の確認

- **[Tests/pty_investigation/](../../Tests/pty_investigation/)**: 調査用テストスクリプト
  - `test_pty_prompts.py`: PTYプロンプト検出テスト
  - `test_pty_interactive.py`: 信頼ダイアログ処理テスト
  - `test_claude.exp` / `test_claude_final.exp`: Expectスクリプト

### 最終的な設計決定

調査の結果、**非対話モード + セッション管理方式**を採用しました:

- ✅ **実装難易度**: 低い（subprocessのみ使用）
- ✅ **安定性**: 高い（プロンプト検出不要）
- ✅ **会話継続**: Claude `--continue` / Codex `exec resume`でサポート
- ✅ **MCP対応**: 両CLIとも非対話モードでMCP利用可能

---

## まとめ

この仕様書では、**非対話モード + セッション管理方式**を使用してClaude CodeとCodex CLIをiPhoneとApple Watchから操作可能にするシステムの詳細設計を示しました。

**重要なポイント**:
1. ✅ 定額プラン内で運用（API従量課金なし）
2. ✅ 会話履歴とMCP接続の維持（--continue/resume）
3. ✅ 両CLIのサポート（非対話モード）
4. ✅ プッシュ通知による完了通知
5. ✅ 段階的な実装ロードマップ

実装を進める際は、Phase 1の非対話モード実装から始めて、各フェーズの成功基準をクリアしながら進めることをお勧めします。

---

**End of Document**
