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
│  │  - claude --print [--continue]              │        │
│  │  - codex exec [resume <session_id>]         │        │
│  │  - Session ID extraction & storage          │        │
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
4. Session Manager → デバイスごとのセッションIDを取得（初回はNone）
5. Session Manager → subprocess.run(['claude', '--print', '--continue'], input="質問")
6. claude → 処理実行（MCP使用可）
7. subprocess ← claude: 応答テキスト + セッション情報
8. Session Manager → セッションIDを抽出し、device_sessions DBに保存
9. Server ← 結果を受け取り
10. Job DB → 更新 (status: success, stdout: "応答", finished_at: now)
11. APNs → iPhone へプッシュ通知送信
12. iPhone ← 通知受信 → タップ → GET /jobs/{id} → 結果表示
13. 次回ジョブ → Session Manager が device_sessions DBから前回セッションIDを取得し継続
```

---

## 3. 非対話モード + セッション管理設計

### 3.1 設計方針の変更理由

**調査結果** (詳細は[Docs/Investigation_Report.md](../Investigation_Report.md)を参照):
- PTY方式: プロンプト検出の不安定性、ANSIエスケープ処理の複雑さ、信頼ダイアログの問題により実装困難
- 非対話モード: `claude --print`および`codex exec`が安定して動作し、MCPサーバーもサポート
- セッション継続: Claude Codeは`--continue`/`--resume`、Codexは`exec resume <session_id>`で会話履歴を保持可能

### 3.2 Claude Code セッション管理

#### 基本実装

```python
import subprocess
from typing import Dict, Optional

class ClaudeSessionManager:
    """
    単一のCLI（claude or codex）を永続的に実行するPTYセッション
    """
    
    def __init__(self, cli_command: list, session_id: str):
        """
        Args:
            cli_command: ["claude"] or ["codex"]
            session_id: セッションの一意識別子
        """
        self.cli_command = cli_command
        self.session_id = session_id
        self.master_fd: Optional[int] = None
        self.slave_fd: Optional[int] = None
        self.pid: Optional[int] = None
        self.is_ready = False
        self.ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        
        self._start()
    
    def _start(self):
        """PTYでCLIプロセスを起動"""
        self.master_fd, self.slave_fd = pty.openpty()
        self.pid = os.fork()
        
        if self.pid == 0:  # 子プロセス
            os.close(self.master_fd)
            
            # stdin, stdout, stderr を slave に接続
            os.dup2(self.slave_fd, 0)
            os.dup2(self.slave_fd, 1)
            os.dup2(self.slave_fd, 2)
            
            # 環境変数を設定（カラー出力を無効化）
            env = os.environ.copy()
            env['TERM'] = 'dumb'  # ANSIエスケープを最小化
            env['NO_COLOR'] = '1'
            
            # CLIを実行
            os.execvpe(self.cli_command[0], self.cli_command, env)
        else:  # 親プロセス
            os.close(self.slave_fd)
            
            # 起動メッセージを待つ
            self.is_ready = self._wait_for_prompt(timeout=30)
            if not self.is_ready:
                raise RuntimeError(f"Failed to start {self.cli_command[0]}")
    
    def _wait_for_prompt(self, timeout: int = 30) -> bool:
        """
        プロンプト記号（› or >）が表示されるまで待機
        
        Args:
            timeout: タイムアウト秒数
        
        Returns:
            成功したらTrue
        """
        start_time = time.time()
        buffer = ""
        
        while time.time() - start_time < timeout:
            ready, _, _ = select.select([self.master_fd], [], [], 0.5)
            if ready:
                try:
                    chunk = os.read(self.master_fd, 4096).decode('utf-8', errors='ignore')
                    buffer += chunk
                    
                    # プロンプト記号を検出
                    # claude: "› "
                    # codex: "> "
                    if '›' in chunk or ('>' in chunk and not chunk.strip().startswith('>')):
                        return True
                except OSError:
                    return False
        
        return False
    
    def send_message(self, message: str, timeout: int = 300) -> dict:
        """
        メッセージを送信して応答を取得
        
        Args:
            message: 送信するテキスト
            timeout: 応答待機のタイムアウト（秒）
        
        Returns:
            {
                'success': bool,
                'output': str,
                'error': Optional[str]
            }
        """
        if not self.is_ready:
            return {
                'success': False,
                'output': '',
                'error': 'Session not ready'
            }
        
        try:
            # メッセージを送信
            os.write(self.master_fd, (message + "\n").encode('utf-8'))
            
            # 応答を収集
            output = self._collect_response(timeout)
            
            return {
                'success': True,
                'output': self._clean_output(output),
                'error': None
            }
        except Exception as e:
            return {
                'success': False,
                'output': '',
                'error': str(e)
            }
    
    def _collect_response(self, timeout: int) -> str:
        """
        CLIからの応答を収集
        
        応答完了の判定基準:
        1. プロンプト記号（› or >）が再表示された
        2. 5秒間出力がない（アイドル判定）
        3. タイムアウト
        """
        start_time = time.time()
        buffer = ""
        last_output_time = time.time()
        idle_threshold = 5.0  # 5秒間出力なしで完了と判断
        
        while time.time() - start_time < timeout:
            ready, _, _ = select.select([self.master_fd], [], [], 0.1)
            
            if ready:
                try:
                    chunk = os.read(self.master_fd, 4096).decode('utf-8', errors='ignore')
                    buffer += chunk
                    last_output_time = time.time()
                    
                    # プロンプト記号で終了判定
                    lines = chunk.split('\n')
                    if lines and ('›' in lines[-1] or '>' in lines[-1].strip()):
                        # プロンプト行を除外して返す
                        return self._remove_final_prompt(buffer)
                        
                except OSError:
                    break
            else:
                # アイドル時間チェック
                if time.time() - last_output_time > idle_threshold:
                    return buffer
        
        return buffer
    
    def _remove_final_prompt(self, text: str) -> str:
        """最後のプロンプト行を削除"""
        lines = text.split('\n')
        if lines and ('›' in lines[-1] or '>' in lines[-1]):
            return '\n'.join(lines[:-1])
        return text
    
    def _clean_output(self, text: str) -> str:
        """ANSIエスケープコードを除去"""
        # ANSI escape sequences を削除
        cleaned = self.ansi_escape.sub('', text)
        
        # エコーバックされた入力行を削除（先頭行が入力そのものの場合）
        lines = cleaned.split('\n')
        if len(lines) > 1:
            return '\n'.join(lines[1:]).strip()
        
        return cleaned.strip()
    
    def is_alive(self) -> bool:
        """プロセスが生きているかチェック"""
        if self.pid is None:
            return False
        
        try:
            os.kill(self.pid, 0)  # シグナル0で存在確認
            return True
        except OSError:
            return False
    
    def restart(self):
        """セッションを再起動"""
        self.close()
        time.sleep(1)
        self._start()
    
    def close(self):
        """セッションを終了"""
        if self.master_fd:
            try:
                os.close(self.master_fd)
            except:
                pass
        
        if self.pid:
            try:
                os.kill(self.pid, 9)  # SIGKILL
                os.waitpid(self.pid, 0)
            except:
                pass
```

### 3.3 セッションマネージャー

```python
from typing import Dict, Optional
import threading
import logging

logger = logging.getLogger(__name__)

class SessionManager:
    """
    複数のPTYセッションを管理
    - claude用セッション
    - codex用セッション
    """
    
    def __init__(self):
        self.sessions: Dict[str, PTYSession] = {}
        self.lock = threading.Lock()
        self._initialize_sessions()
    
    def _initialize_sessions(self):
        """起動時に両方のセッションを作成"""
        try:
            logger.info("Initializing Claude session...")
            self.sessions['claude'] = PTYSession(['claude'], 'claude-main')
            logger.info("Claude session ready")
        except Exception as e:
            logger.error(f"Failed to start Claude session: {e}")
        
        try:
            logger.info("Initializing Codex session...")
            self.sessions['codex'] = PTYSession(['codex'], 'codex-main')
            logger.info("Codex session ready")
        except Exception as e:
            logger.error(f"Failed to start Codex session: {e}")
    
    def send_message(self, runner: str, message: str, timeout: int = 300) -> dict:
        """
        指定されたrunnerにメッセージを送信
        
        Args:
            runner: "claude" or "codex"
            message: 送信するメッセージ
            timeout: タイムアウト（秒）
        
        Returns:
            応答辞書
        """
        with self.lock:
            session = self.sessions.get(runner)
            
            if not session:
                return {
                    'success': False,
                    'output': '',
                    'error': f'No session for runner: {runner}'
                }
            
            # セッションが死んでいたら再起動
            if not session.is_alive():
                logger.warning(f"{runner} session is dead. Restarting...")
                try:
                    session.restart()
                except Exception as e:
                    logger.error(f"Failed to restart {runner}: {e}")
                    return {
                        'success': False,
                        'output': '',
                        'error': f'Session restart failed: {e}'
                    }
            
            # メッセージ送信
            return session.send_message(message, timeout)
    
    def get_session_status(self, runner: str) -> dict:
        """セッションの状態を取得"""
        session = self.sessions.get(runner)
        if not session:
            return {'exists': False, 'alive': False}
        
        return {
            'exists': True,
            'alive': session.is_alive(),
            'ready': session.is_ready
        }
    
    def restart_session(self, runner: str):
        """指定されたセッションを再起動"""
        with self.lock:
            session = self.sessions.get(runner)
            if session:
                session.restart()
    
    def shutdown_all(self):
        """全セッションを終了"""
        for session in self.sessions.values():
            session.close()
```

### 3.4 応答判定ロジックの詳細

#### 完了判定の戦略

1. **プロンプト記号検出**（最優先）
   - Claude: `›` が行末に出現
   - Codex: `>` が行末に出現
   
2. **アイドルタイムアウト**（フォールバック）
   - 5秒間出力がない → 応答完了と判断
   
3. **絶対タイムアウト**（安全装置）
   - 300秒（5分）経過 → 強制終了

#### エラー検出

- プロセス死亡: `is_alive()` が False
- 応答なし: タイムアウト
- パース失敗: ANSIコード除去失敗

---

## 4. MacStudio サーバー詳細仕様

### 4.1 技術スタック

- **言語**: Python 3.10+
- **Webフレームワーク**: FastAPI
- **非同期処理**: asyncio, BackgroundTasks
- **DB**: SQLite3 + SQLAlchemy
- **プッシュ通知**: PyAPNs2
- **プロセス管理**: pty, os, select

### 4.2 ディレクトリ構成

```
~/remote-job-server/
├── main.py                 # FastAPIエントリポイント
├── config.py               # 設定値
├── models.py               # SQLAlchemyモデル
├── database.py             # DB接続管理
├── pty_session.py          # PTYSession, SessionManager
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
from models import Base, Job, Device
from job_manager import JobManager
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
    device_id: Optional[str] = None

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
async def get_sessions():
    """セッション状態を取得"""
    return {
        "claude": job_manager.session_manager.get_session_status("claude"),
        "codex": job_manager.session_manager.get_session_status("codex")
    }

@app.post("/sessions/{runner}/restart")
async def restart_session(runner: str):
    """セッションを再起動"""
    job_manager.session_manager.restart_session(runner)
    return {"status": "restarting", "runner": runner}

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
from pty_session import SessionManager
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
                status="queued",
                created_at=datetime.utcnow()
            )
            
            if device_id:
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
            
            # PTYセッションに送信
            logger.info(f"Sending job {job_id} to {job.runner}")
            result = self.session_manager.send_message(
                runner=job.runner,
                message=job.input_text,
                timeout=300
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

#### sessions テーブル（オプション、監視用）

```sql
CREATE TABLE sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    runner TEXT NOT NULL,               -- "claude" or "codex"
    pid INTEGER,                        -- プロセスID
    status TEXT NOT NULL,               -- "running" / "crashed"
    started_at DATETIME NOT NULL,
    last_heartbeat DATETIME
);
```

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
3. PTYセッションに送信
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

PTYセッションの状態を取得。

**Response:**
```json
{
  "claude": {
    "exists": true,
    "alive": true,
    "ready": true
  },
  "codex": {
    "exists": true,
    "alive": true,
    "ready": true
  }
}
```

---

#### POST /sessions/{runner}/restart

指定されたセッションを再起動。

**Example:**
```
POST /sessions/claude/restart
```

**Response:**
```json
{
  "status": "restarting",
  "runner": "claude"
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
    let deviceId: String?
    
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

#### PTYセッションのエラー

```python
class PTYSessionError(Exception):
    """PTYセッション関連のエラー"""
    pass

class SessionNotReadyError(PTYSessionError):
    """セッションが準備できていない"""
    pass

class SessionCrashedError(PTYSessionError):
    """セッションがクラッシュした"""
    pass
```

#### 自動リカバリー

```python
def _execute_job_with_retry(self, job_id: str, max_retries: int = 3):
    """リトライ機能付きジョブ実行"""
    for attempt in range(max_retries):
        try:
            self._execute_job(job_id)
            break
        except SessionCrashedError:
            logger.warning(f"Session crashed, retrying ({attempt+1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(5)
                self.session_manager.restart_session(runner)
            else:
                raise
```

#### タイムアウト処理

- **絶対タイムアウト**: 300秒（5分）
- **アイドルタイムアウト**: 5秒
- **プロセス起動タイムアウト**: 30秒

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

### Phase 1: PTYプロトタイプ（1-2日）

**目標**: 単一のPTYセッションでclaude/codexと通信できることを確認

**タスク**:
1. `pty_session.py` の基本実装
   - `PTYSession` クラス
   - プロンプト検出ロジック
   - ANSIエスケープ除去
2. テストスクリプト作成
   ```python
   # test_pty.py
   session = PTYSession(['claude'], 'test')
   result = session.send_message("こんにちは")
   print(result)
   ```
3. 両方のCLI（claude/codex）で動作確認

**成功基準**:
- ✅ claudeセッションからの応答取得
- ✅ codexセッションからの応答取得
- ✅ 複数メッセージの連続送信

---

### Phase 2: SessionManager実装（2-3日）

**目標**: 複数セッションを管理し、自動再起動を実装

**タスク**:
1. `SessionManager` クラス実装
2. セッション死活監視
3. 自動再起動ロジック
4. スレッドセーフ対応（lock使用）

**成功基準**:
- ✅ claude/codex両セッション同時稼働
- ✅ セッションクラッシュ時の自動再起動
- ✅ 並行アクセスでのデータ破損なし

---

### Phase 3: FastAPI + DB（3-4日）

**目標**: REST APIとデータベースを統合

**タスク**:
1. SQLAlchemyモデル定義
2. FastAPIエンドポイント実装
   - POST /jobs
   - GET /jobs
   - GET /jobs/{id}
3. `JobManager` でPTYセッションと連携
4. BackgroundTasksでジョブ実行

**成功基準**:
- ✅ curlでジョブ作成・取得可能
- ✅ ジョブがPTYセッションで実行される
- ✅ 結果がDBに保存される

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
# セッション状態API
curl http://100.100.30.35:8000/sessions

# 応答例
{
  "claude": {"exists": true, "alive": true, "ready": true},
  "codex": {"exists": true, "alive": true, "ready": true}
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

# 手動再起動
curl -X POST http://100.100.30.35:8000/sessions/claude/restart
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

## まとめ

この仕様書では、PTY（疑似端末）を使用してClaude CodeとCodex CLIを永続セッションとして維持し、iPhoneとApple Watchから操作可能にするシステムの詳細設計を示しました。

**重要なポイント**:
1. ✅ 定額プラン内で運用（API従量課金なし）
2. ✅ 会話履歴とMCP接続の維持
3. ✅ 両CLIのサポート
4. ✅ プッシュ通知による完了通知
5. ✅ 段階的な実装ロードマップ

実装を進める際は、Phase 1のPTYプロトタイプから始めて、各フェーズの成功基準をクリアしながら進めることをお勧めします。

---

**End of Document**
