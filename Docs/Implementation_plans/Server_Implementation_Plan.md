# サーバー側実装計画（MacStudio FastAPI Server）

作成日: 2025-11-17
最終更新: 2025-11-18
バージョン: 1.2
対象: Phase 1 〜 Phase 5（非対話モード実装 → FastAPI + DB統合 → APNsプッシュ通知 → 統合テスト）

**変更履歴**:
- v1.0 (2025-11-17): Phase 1-4 初版作成
- v1.1 (2025-11-18): **Phase 5 APNsプッシュ通知実装を追加**（システム中核機能）
- v1.2 (2025-11-18): **Phase順序変更: Phase 4とPhase 5を入れ替え**（統合テストで通知機能を検証するため）

---

## 実装フロー概要

```
Phase 1: データベース基盤 + セッション管理（2-3日）
  ↓
Phase 2: ジョブ管理モデル拡張（1日）
  ↓
Phase 3: FastAPI REST API層（2-3日）
  ↓
Phase 4: APNsプッシュ通知実装（1-2日）← **必須機能（v1.2で統合テスト前に移動）**
  ↓
Phase 5: 統合テスト・動作確認（1日）
```

---

## Phase 1: データベース基盤 + セッション管理（2-3日）

> 実装ディレクトリ: `/Users/macstudio/Projects/RemotePrompt/remote-job-server`（計画時の `~/remote-job-server` から統一）

### 目標
SQLite + SQLAlchemyでDB基盤を構築し、subprocess経由でCLIと通信するセッション管理を実装する
（注：MASTER_SPECIFICATIONではdevice_sessionsテーブルでの永続管理が必須要件のため、最初からDB実装とする）

### 1.1 プロジェクトセットアップ

- [x] プロジェクトディレクトリ作成
  ```bash
  mkdir -p /Users/macstudio/Projects/RemotePrompt/remote-job-server/{data,logs,tests}
  cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
  ```

- [x] Python仮想環境作成
  ```bash
  python3 -m venv .venv
  source .venv/bin/activate
  ```

- [x] requirements.txt作成
  ```txt
  fastapi==0.104.1
  uvicorn[standard]==0.24.0
  sqlalchemy==2.0.23
  pydantic==2.5.0
  pydantic-settings==2.1.0
  python-dotenv==1.0.0
  PyAPNs2==2.0.0
  ```

- [x] 依存関係インストール
  ```bash
  pip install -r requirements.txt
  ```

- [x] .gitignore作成
  ```
  .venv/
  __pycache__/
  *.pyc
  .env
  data/*.db
  logs/*.log
  .DS_Store
  ```

---

### 1.2 データベース設定

**ファイル**: `database.py`

- [x] SessionLocal設定
  ```python
  import os
  from sqlalchemy import create_engine
  from sqlalchemy.orm import sessionmaker

  DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./data/jobs.db")
  engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
  SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
  ```

- [x] データベース初期化関数
  ```python
  def init_db():
      Base.metadata.create_all(bind=engine)
  ```

---

### 1.3 SQLAlchemyモデル定義

**ファイル**: `models.py`

- [x] Base定義
  ```python
  # db/base.py
  from sqlalchemy.orm import DeclarativeBase

  class Base(DeclarativeBase):
      pass
  ```

- [x] DeviceSessionモデル実装（Phase 1で最優先）
  - [x] id: Integer, primary_key, autoincrement
  - [x] device_id: String, nullable=False
  - [x] runner: String, nullable=False
  - [x] session_id: String, nullable=False
  - [x] created_at: DateTime, nullable=False
  - [x] updated_at: DateTime, nullable=False
  - [x] UNIQUE制約: (device_id, runner)
  - [x] インデックス: (device_id, runner)

- [x] Deviceモデル実装（Phase 1で簡易実装）
  - [x] id: Integer, primary_key, autoincrement
  - [x] device_id: String, unique, nullable=False
  - [x] device_token: String, nullable=False
  - [x] created_at: DateTime, nullable=False
  - [x] updated_at: DateTime, nullable=False

- [x] Jobモデル実装（Phase 2計画分も先行実装）
  - [x] id: String(36), primary_key
  - [x] runner: String(20), nullable=False
  - [x] input_text: Text, nullable=False
  - [x] device_id: String(100), nullable=False
  - [x] status: String(20), nullable=False
  - [x] stdout/stderr/exit_code/started_at/finished_at/notify_token/created_at まで実装済み

---

### 1.4 DB初期化スクリプト

**ファイル**: `init_db.py`

- [x] スクリプト作成
  ```python
  from database import init_db, SessionLocal
  from models import Device, utcnow

  def create_initial_data():
      db = SessionLocal()
      try:
          device = Device(
              device_id="test-device-1",
              device_token="dummy-token",
              created_at=utcnow(),
              updated_at=utcnow()
          )
          db.add(device)
          db.commit()
          print("Initial data created")
      finally:
          db.close()

  if __name__ == "__main__":
      init_db()
      create_initial_data()
  ```

- [x] 実行確認
  ```bash
  python init_db.py
  sqlite3 data/jobs.db ".schema"
  ```

---

### 1.5 ClaudeSessionManager実装（DB統合版）

**ファイル**: `session_manager.py`

- [x] 基本クラス定義
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
      def __init__(self):
          self.trusted_directory = "/Users/nao/workspace"
  ```

- [x] `_get_session_id_from_db()` メソッド実装（DB版）
  - [x] SessionLocal() でDB接続
  - [x] DeviceSession.query().filter_by(device_id, runner='claude')
  - [x] session_id返却 or None
  - [x] 引数: `device_id: str`
  - [x] 戻り値: `Optional[str]`

- [x] `_save_session_id_to_db()` メソッド実装（DB版）
  - [x] SessionLocal() でDB接続
  - [x] 既存レコード検索
  - [x] UPDATE（session_id, updated_at） or INSERT
  - [x] commit()
  - [x] 引数: `device_id: str, session_id: str`

- [x] `execute_job()` メソッド実装
  - [x] UUID生成ロジック（新規セッション時）
  - [x] `--session-id` オプション付きコマンド実行
  - [x] `--resume` オプション付きコマンド実行
  - [x] subprocess.run() タイムアウト設定（300秒）
  - [x] 例外処理（TimeoutExpired, 一般例外）
  - [x] 戻り値辞書：success, output, session_id, error

- [x] ロギング設定
  - [x] logging.getLogger() 設定
  - [x] INFO/ERROR レベルログ出力

---

### 1.6 CodexSessionManager実装（DB統合版）

**ファイル**: `session_manager.py`（同一ファイル内）

- [x] 基本クラス定義
  ```python
  class CodexSessionManager:
      def __init__(self):
          pass
  ```

- [x] `_get_session_id_from_db()` メソッド実装（DB版）
  - [x] SessionLocal() でDB接続
  - [x] DeviceSession.query().filter_by(device_id, runner='codex')
  - [x] session_id返却 or None
  - [x] 引数: `device_id: str`
  - [x] 戻り値: `Optional[str]`

- [x] `_save_session_id_to_db()` メソッド実装（DB版）
  - [x] SessionLocal() でDB接続
  - [x] 既存レコード検索
  - [x] UPDATE（session_id, updated_at） or INSERT
  - [x] commit()
  - [x] 引数: `device_id: str, session_id: str`

- [x] `execute_job()` メソッド実装
  - [x] `codex exec` コマンド実行
  - [x] `codex exec resume <session_id>` コマンド実行
  - [x] セッションID抽出（正規表現: `r'session id: ([a-f0-9\-]+)'`）
  - [x] 出力フィルタリング（メタデータ行除去）
  - [x] subprocess.run() タイムアウト設定（300秒）
  - [x] 例外処理（TimeoutExpired, 一般例外）
  - [x] 戻り値辞書：success, output, session_id, error

- [x] ロギング設定
  - [x] logging.getLogger() 設定
  - [x] INFO/ERROR レベルログ出力

---

### 1.7 統合SessionManager実装

**ファイル**: `session_manager.py`（同一ファイル内）

- [x] SessionManagerクラス定義
  ```python
  class SessionManager:
      def __init__(self):
          self.claude_manager = ClaudeSessionManager()
          self.codex_manager = CodexSessionManager()
  ```

- [x] `execute_job()` メソッド実装
  - [x] runner引数による分岐（claude/codex）
  - [x] 各マネージャーへの委譲
  - [x] 未知runnerのエラーハンドリング

- [x] `get_session_status()` メソッド実装
  - [x] DBからセッションID取得
  - [x] exists/session_id形式の辞書返却

---

### 1.8 ローカルテスト実装

**ファイル**: `tests/test_session_manager.py`

- [x] テストスクリプト作成
  ```python
  from session_manager import ClaudeSessionManager, CodexSessionManager

  def test_claude_session():
      mgr = ClaudeSessionManager()
      result = mgr.execute_job("こんにちは", "test-device-1", continue_session=True)
      print(f"Success: {result['success']}")
      print(f"Output: {result['output'][:100]}")
      print(f"Session ID: {result['session_id']}")

  def test_codex_session():
      mgr = CodexSessionManager()
      result = mgr.execute_job("What is 5 * 7?", "test-device-2", continue_session=True)
      print(f"Success: {result['success']}")
      print(f"Output: {result['output'][:100]}")
      print(f"Session ID: {result['session_id']}")
  ```

- [x] Claude Code動作確認
  - [x] 初回実行（--session-id）
  - [x] 継続実行（--resume）
  - [x] セッションID保存確認（DB）
  - [x] device_sessions テーブル確認

- [x] Codex動作確認
  - [x] 初回実行（exec）
  - [x] 継続実行（exec resume）
  - [x] セッションID抽出確認
  - [x] device_sessions テーブル確認

- [x] DB永続化テスト
  - [x] sqlite3 data/jobs.db "SELECT * FROM device_sessions;"
  - [x] セッションID保存確認
  - [x] UNIQUE制約確認（device_id, runner）

- [x] MCP動作確認
  - [x] Claude + Serena MCPテスト（`mcp__serena__list_dir`動作確認済み）
  - [x] Codex + Serena MCPテスト（MCPツール一覧68件取得成功、Serena特定ツールはCLAUDE.md制約により部分的動作）

---

### Phase 1 完了条件

- [x] データベース基盤: SQLite + SQLAlchemy設定完了
- [x] DeviceSessionモデル: device_sessions テーブル作成成功
- [x] ClaudeSessionManager: 応答取得成功 + DB永続化確認
- [x] CodexSessionManager: 応答取得成功 + DB永続化確認
- [x] セッション継続: 会話履歴が保持される（DB経由）
- [x] セッションID保存: device_sessions テーブルに保存確認
- [x] エラーハンドリング: タイムアウト・例外を適切に処理

---

## Phase 2: ジョブ管理モデル拡張（1日）

> **🎯 実装状況**: ✅ Phase 1実装時に完了済み（スキップ）
>
> Phase 1のレビュー過程でJobモデルの全フィールド（exit_code, stderr, started_at, finished_at, notify_token）を実装済みのため、Phase 2の作業は不要となりました。

### 目標
Phase 1のDB基盤にJobモデルの詳細実装を追加し、ジョブ管理機能を完成させる

### 2.1 Jobモデル拡張 / アプリケーション層前倒し

**ファイル**: `models.py`（Phase 1のJobモデルを拡張）

- [x] Jobモデル拡張実装（✅ Phase 1で完了）
  - [x] exit_code: Integer（追加）
  - [x] stderr: Text（追加）
  - [x] started_at: DateTime（追加）
  - [x] finished_at: DateTime（追加）
  - [x] notify_token: String(255)（追加）
  - [x] `to_dict()` メソッド実装（Phase 1で完了）
  - [x] JobManager/API層で利用する追加フィールド（exit_code等）をPhase 2で正式採用
    ```python
    def to_dict(self):
        return {
            "id": self.id,
            "runner": self.runner,
            "input_text": self.input_text,
            "device_id": self.device_id,
            "status": self.status,
            "exit_code": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "finished_at": self.finished_at.isoformat() if self.finished_at else None,
        }
    ```

---

### 2.2 マイグレーション実行

- [x] データベーステーブル再作成（✅ Phase 1で完了）
  ```bash
  rm -f data/jobs.db  # 既存DBを削除
  python init_db.py    # 新スキーマで再作成
  ```

- [x] スキーマ確認（✅ Phase 1で完了）
  ```bash
  sqlite3 data/jobs.db ".schema jobs"
  ```

---

### 2.3 DBテスト + JobManager追加実装

**ファイル**: `tests/test_database.py`

- [x] Job拡張フィールドテスト
  - [x] exit_code, stderr, started_at, finished_at保存確認
  - [x] to_dict() メソッド動作確認
  - [x] JSON変換確認

- [x] Job CRUD テスト
  - [x] INSERT テスト（全フィールド）
  - [x] SELECT テスト（status filter）
  - [x] UPDATE テスト（status変更 + タイムスタンプ）

### 2.4 JobManager / Config 実装（Phase 3項目の前倒し）

- [x] `job_manager.py` を追加し、`create_job`/`_execute_job`/`get_jobs`/`get_job` を実装
- [x] `config.py` を追加し、pydantic-settingsベースの `Settings` + `setup_logging()` を提供
- [x] `tests/test_job_manager.py` で成功/失敗/フィルタリングシナリオをモック付きで検証

---

### Phase 2 完了条件

- [x] Jobモデル拡張完了（全フィールド実装）
- [x] to_dict() メソッド動作確認
- [x] Job CRUD動作確認
- [x] マイグレーション成功

---

## Phase 3: FastAPI REST API層（2-3日）

### 目標
REST APIエンドポイントを実装し、ジョブ管理・セッション管理をHTTP経由で操作可能にする

### 3.1 設定ファイル

**ファイル**: `config.py`

- [x] 設定クラス定義
  ```python
  from pydantic_settings import BaseSettings

  class Settings(BaseSettings):
      API_KEY: str = "your-secret-key"
      DATABASE_URL: str = "sqlite:///./data/jobs.db"
      LOG_LEVEL: str = "INFO"

      class Config:
          env_file = ".env"

  settings = Settings()
  ```

- [ ] .env ファイル作成
  ```
  API_KEY=test-api-key-123
  DATABASE_URL=sqlite:///./data/jobs.db
  LOG_LEVEL=DEBUG
  ```

---

### 3.2 ロギング設定

**ファイル**: `config.py`（追記）

- [x] ログ設定関数実装
  ```python
  import logging
  from logging.handlers import RotatingFileHandler

  def setup_logging():
      logger = logging.getLogger()
      logger.setLevel(logging.DEBUG)

      # ファイルハンドラ
      fh = RotatingFileHandler('logs/server.log', maxBytes=10*1024*1024, backupCount=5)
      fh.setLevel(logging.DEBUG)

      # コンソールハンドラ
      ch = logging.StreamHandler()
      ch.setLevel(logging.INFO)

      # フォーマッタ
      formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
      fh.setFormatter(formatter)
      ch.setFormatter(formatter)

      logger.addHandler(fh)
      logger.addHandler(ch)
  ```

---

### 3.3 JobManager実装

**ファイル**: `job_manager.py`

- [x] JobManagerクラス定義
  ```python
  class JobManager:
      def __init__(self):
          self.session_manager = SessionManager()
  ```

- [x] `create_job()` メソッド実装
  - [x] Job レコード作成（UUID生成）
  - [x] device_token取得（Device テーブル）
  - [x] DB保存（status: queued）
  - [x] BackgroundTasksで`_execute_job()`登録
  - [x] 戻り値: {id, status}

- [x] `_execute_job()` メソッド実装
  - [x] Job取得（job_id）
  - [x] status更新: running
  - [x] SessionManager.execute_job() 呼び出し
  - [x] 結果保存（success/failed, stdout/stderr）
  - [x] finished_at更新
  - [x] APNs通知送信（後回し可）

- [x] `get_jobs()` メソッド実装
  - [x] ページネーション（limit, offset）
  - [x] status フィルタ
  - [x] device_id フィルタ
  - [x] 戻り値: List[Job]

- [x] `get_job()` メソッド実装
  - [x] job_id検索
  - [x] 戻り値: Job or 404

---

### 3.4 FastAPI メインアプリ

**ファイル**: `main.py`

- [x] FastAPIアプリ初期化
  ```python
  from fastapi import FastAPI, BackgroundTasks, HTTPException
  from fastapi.middleware.cors import CORSMiddleware

  app = FastAPI(title="Remote Job Server")

  # CORS設定
  app.add_middleware(
      CORSMiddleware,
      allow_origins=["*"],  # 本番環境では制限推奨
      allow_credentials=True,
      allow_methods=["*"],
      allow_headers=["*"],
  )
  ```

- [x] DB初期化（起動時）
  ```python
  from database import Base, engine

  @app.on_event("startup")
  def startup_event():
      Base.metadata.create_all(bind=engine)
      setup_logging()
  ```

- [x] JobManagerインスタンス作成
  ```python
  job_manager = JobManager()
  ```

---

### 3.5 Pydanticモデル定義

**ファイル**: `main.py`（または `schemas.py`）

- [x] CreateJobRequest
  ```python
  class CreateJobRequest(BaseModel):
      runner: str
      input_text: str
      device_id: str
  ```

- [x] RegisterDeviceRequest
  ```python
  class RegisterDeviceRequest(BaseModel):
      device_id: str
      device_token: str
  ```

---

### 3.6 エンドポイント実装

**ファイル**: `main.py`

#### POST /register_device

- [x] エンドポイント実装
  - [x] Device INSERT or UPDATE
  - [x] updated_at更新
  - [x] 戻り値: {status: "registered"}

#### POST /jobs

- [x] エンドポイント実装
  - [x] JobManager.create_job() 呼び出し
  - [x] BackgroundTasks 登録
  - [x] 戻り値: {id, status}

#### GET /jobs

- [x] エンドポイント実装
  - [x] Query Parameters: limit, status, device_id
  - [x] JobManager.get_jobs() 呼び出し
  - [x] 戻り値: List[Job]

#### GET /jobs/{job_id}

- [x] エンドポイント実装
  - [x] JobManager.get_job() 呼び出し
  - [x] 戻り値: Job or 404

#### GET /sessions

- [x] エンドポイント実装
  - [x] Query Parameters: device_id（必須）
  - [x] SessionManager.get_session_status() 呼び出し
  - [x] 戻り値: {claude: {...}, codex: {...}}

#### DELETE /sessions/{runner}

- [x] エンドポイント実装
  - [x] Query Parameters: device_id（必須）
  - [x] DeviceSession DELETE
  - [x] 戻り値: {status: "deleted", runner, device_id}

#### GET /health

- [x] エンドポイント実装
  - [x] 戻り値: {status: "ok"}

---

### 3.7 エラーハンドリング

- [x] 方針: FastAPI標準の `HTTPException`/`BackgroundTasks` で例外を処理し、カスタム例外は現状不要（SessionManager側で例外捕捉済み）

### 3.8 認証 / CORS 設定

- [x] `config.py` の API_KEY と allowed_origins をFastAPIに適用
- [x] `verify_api_key` 依存を全エンドポイント（/health以外）に追加
- [x] 環境変数 `ALLOWED_ORIGINS` でCORSを制御可能にする

### 3.9 ローカルサーバー起動テスト

- [x] サーバー起動（uvicorn main:app --reload）
  ```bash
  uvicorn main:app --reload --host 0.0.0.0 --port 8000
  ```

- [x] ヘルスチェック
  ```bash
  curl http://localhost:35000/health
  ```

- [x] デバイス登録テスト
  ```bash
  curl -X POST http://localhost:35000/register_device \
    -H "Content-Type: application/json" \
    -d '{"device_id": "test-device-1", "device_token": "dummy-token"}'
  ```

- [x] ジョブ作成テスト（Claude）
  ```bash
  curl -X POST http://localhost:35000/jobs \
    -H "Content-Type: application/json" \
    -d '{"runner": "claude", "input_text": "こんにちは", "device_id": "test-device-1"}'
  ```

- [x] ジョブ取得テスト
  ```bash
  JOB_ID="..." # 上記で取得したID
  curl http://localhost:35000/jobs/$JOB_ID
  ```

- [x] セッション状態確認
  ```bash
  curl "http://localhost:35000/sessions?device_id=test-device-1"
  ```

- [x] セッション削除テスト
  ```bash
  curl -X DELETE "http://localhost:35000/sessions/claude?device_id=test-device-1"
  ```

---

### Phase 3 完了条件

- [x] 全エンドポイント実装完了
- [x] curlでジョブ作成・取得可能
- [x] ジョブがSessionManagerで実行される
- [x] 結果がDBに保存される
- [x] セッションIDがdevice_sessionsテーブルに保存される
- [x] エラーハンドリング動作確認

---

## Phase 4: APNsプッシュ通知実装（1-2日）

### 目標
ジョブ完了時にiPhone/Apple WatchへAPNsプッシュ通知を送信する機能を実装する

### 4.1 PyAPNs2インストール確認

**ファイル**: `requirements.txt`

- [ ] PyAPNs2依存関係確認
  ```bash
  cat requirements.txt | grep PyAPNs2
  # PyAPNs2==2.0.0 が含まれていることを確認
  ```

- [ ] 未インストールの場合は追加
  ```bash
  echo "PyAPNs2==2.0.0" >> requirements.txt
  pip install PyAPNs2==2.0.0
  ```

---

### 4.2 APNs認証キー取得（Apple Developer Portal）

**前提**: iOSアプリ開発チームがAPNs認証キーを取得済み

- [ ] APNs認証キー情報の確認
  - [ ] `.p8` ファイルのパス確認
  - [ ] Key ID確認（10文字の英数字）
  - [ ] Team ID確認（10文字の英数字）
  - [ ] Bundle ID確認（例: `com.example.remoteprompt`）
  - [ ] 環境確認（Development: Sandbox / Production）

- [ ] ⚠️ **重要**: `.p8` ファイルをサーバーに配置
  ```bash
  mkdir -p /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs
  # .p8 ファイルを certs/ にコピー
  # 例: certs/AuthKey_XXXXXXXXXX.p8
  ```

- [ ] `.gitignore` に証明書ディレクトリ追加
  ```bash
  echo "certs/" >> .gitignore
  ```

---

### 4.3 環境変数設定

**ファイル**: `.env`

- [ ] APNs設定を `.env` に追加
  ```bash
  # APNs設定（既存の設定の下に追記）
  APNS_KEY_PATH=/Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/AuthKey_XXXXXXXXXX.p8
  APNS_KEY_ID=XXXXXXXXXX
  APNS_TEAM_ID=YYYYYYYYYY
  APNS_BUNDLE_ID=com.example.remoteprompt
  APNS_USE_SANDBOX=true  # 開発環境はtrue、本番はfalse
  ```

- [ ] 環境変数の検証
  ```bash
  cat .env | grep APNS
  ```

---

### 4.4 config.py更新

**ファイル**: `config.py`

- [ ] Settings クラスにAPNs設定追加
  ```python
  from pydantic_settings import BaseSettings
  from typing import List

  class Settings(BaseSettings):
      # 既存の設定...
      api_key: str = "dev-api-key"
      database_url: str = "sqlite:///./data/jobs.db"
      log_level: str = "INFO"
      allowed_origins: List[str] = ["http://100.100.30.35:35000"]

      # APNs設定（追加）
      apns_key_path: str = ""
      apns_key_id: str = ""
      apns_team_id: str = ""
      apns_bundle_id: str = "com.example.remoteprompt"
      apns_use_sandbox: bool = True

      class Config:
          env_file = ".env"

  settings = Settings()
  ```

- [ ] APNs設定のバリデーション追加
  ```python
  def validate_apns_config() -> bool:
      """APNs設定が有効かチェック"""
      import os
      if not settings.apns_key_path:
          return False
      if not os.path.exists(settings.apns_key_path):
          LOGGER.warning("APNs key file not found: %s", settings.apns_key_path)
          return False
      if not settings.apns_key_id or not settings.apns_team_id:
          return False
      return True
  ```

---

### 4.5 notify.py実装

**ファイル**: `notify.py`

- [ ] notify.pyファイル作成
  ```bash
  touch notify.py
  ```

- [ ] インポート定義
  ```python
  import logging
  from typing import Optional
  from apns2.client import APNsClient
  from apns2.payload import Payload
  from apns2.errors import APNsException
  from config import settings, validate_apns_config

  LOGGER = logging.getLogger(__name__)
  ```

- [ ] APNsClientシングルトン実装
  ```python
  _apns_client: Optional[APNsClient] = None

  def get_apns_client() -> Optional[APNsClient]:
      """APNsクライアントを取得（シングルトン）"""
      global _apns_client

      if not validate_apns_config():
          LOGGER.warning("APNs configuration is invalid, notifications disabled")
          return None

      if _apns_client is None:
          try:
              _apns_client = APNsClient(
                  credentials=settings.apns_key_path,
                  use_sandbox=settings.apns_use_sandbox
              )
              LOGGER.info("APNs client initialized (sandbox: %s)", settings.apns_use_sandbox)
          except Exception as e:
              LOGGER.error("Failed to initialize APNs client: %s", e)
              return None

      return _apns_client
  ```

- [ ] send_push_notification関数実装
  ```python
  def send_push_notification(
      device_token: str,
      job_id: str,
      runner: str,
      status: str
  ) -> bool:
      """
      APNs経由でプッシュ通知を送信

      Args:
          device_token: デバイストークン（64文字の16進数文字列）
          job_id: ジョブID（UUID）
          runner: "claude" or "codex"
          status: "success" or "failed"

      Returns:
          送信成功時True、失敗時False
      """
      client = get_apns_client()
      if client is None:
          LOGGER.warning("APNs client not available, skipping notification")
          return False

      try:
          # 通知タイトル・本文作成
          title = "ジョブ完了" if status == "success" else "ジョブ失敗"
          body = f"[{runner}] {job_id[:8]}: {status}"

          # Payloadオブジェクト作成
          payload = Payload(
              alert={
                  "title": title,
                  "body": body
              },
              sound="default",
              badge=1,
              custom={
                  "job_id": job_id,
                  "runner": runner,
                  "status": status
              }
          )

          # APNs送信
          client.send_notification(
              device_token,
              payload,
              topic=settings.apns_bundle_id
          )

          LOGGER.info(
              "Push notification sent: job=%s, device=%s, status=%s",
              job_id[:8], device_token[:16], status
          )
          return True

      except APNsException as e:
          LOGGER.error("APNs error: %s (job=%s)", e, job_id)
          return False
      except Exception as e:
          LOGGER.error("Failed to send push notification: %s (job=%s)", e, job_id)
          return False
  ```

---

### 4.6 job_manager.py更新

**ファイル**: `job_manager.py`

- [ ] notify.pyインポート追加
  ```python
  from notify import send_push_notification
  ```

- [ ] _execute_job()メソッド更新（プッシュ通知送信処理追加）
  - [ ] 成功時の通知送信処理追加（`job.status = "success"` の後）
    ```python
    if result.get("success"):
        job.status = "success"
        job.exit_code = 0
        job.stdout = result.get("output", "")
        job.stderr = ""
    else:
        job.status = "failed"
        job.exit_code = 1
        job.stdout = result.get("output", "")
        job.stderr = result.get("error", "")

    job.finished_at = utcnow()
    db.commit()

    # ✅ プッシュ通知送信処理を追加
    if job.notify_token:
        try:
            send_push_notification(
                device_token=job.notify_token,
                job_id=job.id,
                runner=job.runner,
                status=job.status
            )
            LOGGER.info("Push notification sent for job %s", job_id)
        except Exception as e:
            LOGGER.error("Failed to send push notification for job %s: %s", job_id, e)
    else:
        LOGGER.debug("No device token for job %s, skipping notification", job_id)
    ```

  - [ ] 例外処理時の通知送信処理追加（`except Exception` ブロック内）
    ```python
    except Exception:
        LOGGER.exception("Job %s execution failed", job_id)
        job = db.query(Job).filter_by(id=job_id).first()
        if job:
            job.status = "failed"
            job.exit_code = 1
            job.stderr = "Internal error"
            job.finished_at = utcnow()
            db.commit()

            # ✅ 失敗時もプッシュ通知送信
            if job.notify_token:
                try:
                    send_push_notification(
                        device_token=job.notify_token,
                        job_id=job.id,
                        runner=job.runner,
                        status=job.status
                    )
                except Exception as e:
                    LOGGER.error("Failed to send failure notification: %s", e)
    ```

---

### 4.7 テスト実装

**ファイル**: `tests/test_notify.py`

- [ ] テストファイル作成
  ```bash
  touch tests/test_notify.py
  ```

- [ ] テストケース実装
  ```python
  import unittest
  from unittest.mock import patch, MagicMock
  from notify import send_push_notification, get_apns_client

  class TestNotify(unittest.TestCase):
      @patch('notify.get_apns_client')
      def test_send_push_notification_success(self, mock_get_client):
          """正常系: プッシュ通知送信成功"""
          mock_client = MagicMock()
          mock_get_client.return_value = mock_client

          result = send_push_notification(
              device_token="a" * 64,
              job_id="test-job-123",
              runner="claude",
              status="success"
          )

          self.assertTrue(result)
          mock_client.send_notification.assert_called_once()

      @patch('notify.validate_apns_config')
      def test_get_apns_client_invalid_config(self, mock_validate):
          """異常系: APNs設定が無効な場合"""
          mock_validate.return_value = False

          client = get_apns_client()

          self.assertIsNone(client)

      @patch('notify.get_apns_client')
      def test_send_push_notification_client_unavailable(self, mock_get_client):
          """異常系: APNsクライアントが利用不可"""
          mock_get_client.return_value = None

          result = send_push_notification(
              device_token="a" * 64,
              job_id="test-job-456",
              runner="codex",
              status="failed"
          )

          self.assertFalse(result)
  ```

- [ ] テスト実行
  ```bash
  python -m unittest tests.test_notify
  ```

---

### 4.8 統合テスト

**ファイル**: `tests/test_job_manager_with_notify.py`

- [ ] JobManager + 通知送信の統合テスト実装
  ```python
  import unittest
  from unittest.mock import patch, MagicMock
  from job_manager import JobManager
  from database import SessionLocal, init_db
  from models import Job, Device

  class TestJobManagerWithNotify(unittest.TestCase):
      def setUp(self):
          init_db()
          self.db = SessionLocal()

          # テスト用デバイス登録
          device = Device(
              device_id="test-device-notify",
              device_token="a" * 64,
              created_at=datetime.utcnow(),
              updated_at=datetime.utcnow()
          )
          self.db.add(device)
          self.db.commit()

      @patch('job_manager.send_push_notification')
      @patch('job_manager.SessionManager')
      def test_job_completion_sends_notification(self, mock_session_mgr, mock_send_push):
          """ジョブ完了時にプッシュ通知が送信される"""
          # SessionManagerのモック設定
          mock_mgr = MagicMock()
          mock_mgr.execute_job.return_value = {
              'success': True,
              'output': 'Test output',
              'session_id': 'test-session',
              'error': ''
          }
          mock_session_mgr.return_value = mock_mgr

          # ジョブ実行
          job_manager = JobManager(session_manager=mock_mgr)
          job_dict = job_manager.create_job(
              runner="claude",
              input_text="Test prompt",
              device_id="test-device-notify",
              background_tasks=None
          )

          # プッシュ通知送信確認
          mock_send_push.assert_called_once()
          call_args = mock_send_push.call_args[1]
          self.assertEqual(call_args['job_id'], job_dict['id'])
          self.assertEqual(call_args['runner'], 'claude')
          self.assertEqual(call_args['status'], 'success')
          self.assertEqual(call_args['device_token'], "a" * 64)
  ```

- [ ] 統合テスト実行
  ```bash
  python -m unittest tests.test_job_manager_with_notify
  ```

---

### 4.9 手動E2Eテスト（実機iOS必須）

- [ ] 前提条件確認
  - [ ] iOSアプリでAPNs登録完了
  - [ ] デバイストークン取得済み
  - [ ] サーバーの `/register_device` でデバイス登録済み

- [ ] E2Eテストシナリオ実行
  - [ ] シナリオ1: iPhoneからジョブ投稿→完了通知受信
    ```bash
    # 1. iPhoneアプリからジョブ作成
    # 2. サーバーログでプッシュ通知送信確認
    tail -f logs/server.log | grep "Push notification sent"
    # 3. iPhoneで通知バナー表示確認
    # 4. 通知タップ→ジョブ詳細画面表示確認
    ```

  - [ ] シナリオ2: 失敗ジョブの通知
    ```bash
    # 1. 意図的に失敗するプロンプトでジョブ作成
    # 2. "ジョブ失敗" 通知受信確認
    ```

  - [ ] シナリオ3: フォアグラウンド通知
    ```bash
    # 1. iPhoneアプリを開いた状態でジョブ投稿
    # 2. フォアグラウンドでも通知バナー表示確認
    ```

---

### 4.10 エラーハンドリング強化

**ファイル**: `notify.py`

- [ ] リトライ機構追加（オプション）
  ```python
  from tenacity import retry, stop_after_attempt, wait_exponential

  @retry(
      stop=stop_after_attempt(3),
      wait=wait_exponential(multiplier=1, min=1, max=10)
  )
  def send_push_notification_with_retry(
      device_token: str,
      job_id: str,
      runner: str,
      status: str
  ) -> bool:
      """リトライ機構付きプッシュ通知送信"""
      return send_push_notification(device_token, job_id, runner, status)
  ```

- [ ] 無効なデバイストークンの処理
  ```python
  def send_push_notification(device_token, job_id, runner, status) -> bool:
      # 既存のコード...

      try:
          client.send_notification(...)
      except APNsException as e:
          if "Unregistered" in str(e) or "BadDeviceToken" in str(e):
              LOGGER.warning("Invalid device token: %s, removing from DB", device_token[:16])
              # TODO: デバイストークンをDBから削除する処理を追加
          raise
  ```

---

### Phase 4 完了条件

- [ ] PyAPNs2インストール完了
- [ ] APNs認証キー配置完了
- [ ] .env に APNs設定追加完了
- [ ] config.py 更新完了
- [ ] notify.py 実装完了
- [ ] job_manager.py 更新完了（プッシュ通知送信処理追加）
- [ ] ユニットテスト成功（test_notify.py）
- [ ] 統合テスト成功（test_job_manager_with_notify.py）
- [ ] 実機E2Eテスト成功（iPhone実機で通知受信確認）

---

## Phase 5: 統合テスト・動作確認（1日）

### 目標
実際のCLI実行を含む統合テストで全体動作を確認する（APNsプッシュ通知機能を含む）

### 5.1 統合テストシナリオ

**ファイル**: `tests/test_integration.py`

- [ ] シナリオ1: Claude初回→継続実行
  - [ ] POST /jobs (初回)
  - [ ] セッションID保存確認
  - [ ] POST /jobs (継続)
  - [ ] 会話履歴継続確認

- [ ] シナリオ2: Codex初回→継続実行
  - [ ] POST /jobs (初回)
  - [ ] セッションID抽出確認
  - [ ] POST /jobs (継続)
  - [ ] 会話履歴継続確認

- [ ] シナリオ3: セッション削除→再作成
  - [ ] DELETE /sessions/claude
  - [ ] POST /jobs (新規セッション)
  - [ ] 新しいセッションID確認

- [ ] シナリオ4: 複数デバイス同時実行
  - [ ] device_id: test-device-1
  - [ ] device_id: test-device-2
  - [ ] セッション混線なし確認

- [ ] シナリオ5: プッシュ通知統合テスト
  - [ ] ジョブ完了時のプッシュ通知送信確認
  - [ ] ジョブ失敗時のプッシュ通知送信確認
  - [ ] notify_tokenなしの場合の正常動作確認

---

### 5.2 パフォーマンステスト

- [ ] 同時ジョブ実行テスト
  - [ ] 3ジョブ並列投稿
  - [ ] 全ジョブ完了確認
  - [ ] タイムアウトなし確認

- [ ] 長時間実行テスト
  - [ ] 5分間のプロンプト実行
  - [ ] タイムアウト動作確認

---

### 5.3 エラーケーステスト

- [ ] 不正なrunner指定
  - [ ] runner: "invalid"
  - [ ] エラーレスポンス確認

- [ ] 存在しないジョブID
  - [ ] GET /jobs/invalid-id
  - [ ] 404確認

- [ ] セッションタイムアウト
  - [ ] 300秒超過プロンプト
  - [ ] Timeout エラー確認

- [ ] プッシュ通知エラーハンドリング
  - [ ] APNs設定なしでのジョブ実行成功確認
  - [ ] 無効なデバイストークンでのエラーログ確認

---

### 5.4 ログ・モニタリング確認

- [ ] ログファイル確認
  ```bash
  tail -f logs/server.log
  ```

- [ ] エラーログフィルタ
  ```bash
  grep ERROR logs/server.log
  ```

- [ ] プッシュ通知ログ確認
  ```bash
  grep "Push notification" logs/server.log
  ```

- [ ] DB整合性確認
  ```bash
  sqlite3 data/jobs.db "SELECT * FROM device_sessions;"
  sqlite3 data/jobs.db "SELECT id, status, runner FROM jobs ORDER BY created_at DESC LIMIT 10;"
  ```

---

### Phase 5 完了条件

- [ ] 全統合テストシナリオ成功（プッシュ通知含む）
- [ ] パフォーマンステスト合格
- [ ] エラーケース正常処理
- [ ] ログ出力正常
- [ ] DB整合性確認
- [ ] プッシュ通知機能の動作確認（モック／実機）

---

## サーバー実装完了チェックリスト

### 最終確認項目

- [x] Phase 1完了（データベース基盤 + セッション管理）
- [x] Phase 2完了（ジョブ管理モデル拡張）
- [x] Phase 3完了（FastAPI REST API層）
- [ ] **Phase 4完了（APNsプッシュ通知実装）** ← **必須機能（v1.2で統合テスト前に移動）**
- [ ] Phase 5完了（統合テスト・動作確認）

### 本番環境準備

- [x] Tailscale接続確認（ユーザー設定済み）
- [x] MacStudio IPアドレス固定（100.100.30.35）（ユーザー設定済み）
- [x] ファイアウォール設定（Tailscale 環境では不要）
- [x] .env ファイル作成（API キー: `jg3uIg7w753xDmbH1XV1...`）
- [x] 本番ポート(35000)起動確認（localhost 動作確認済み）
- [x] launchd サービス登録（`com.remoteprompt.jobserver.plist`）
- [x] 自動起動設定（launchd で設定済み）
- [x] バックアップスクリプト設定（`scripts/backup_database.sh`、7日間保持）

**launchd サービス管理コマンド**:
```bash
# サービス登録
launchctl load ~/Library/LaunchAgents/com.remoteprompt.jobserver.plist

# サービス起動
launchctl start com.remoteprompt.jobserver

# サービス停止
launchctl stop com.remoteprompt.jobserver

# サービス登録解除
launchctl unload ~/Library/LaunchAgents/com.remoteprompt.jobserver.plist

# サービス状態確認
launchctl list | grep remoteprompt
```

**バックアップコマンド**:
```bash
# 手動バックアップ実行
/Users/macstudio/Projects/RemotePrompt/remote-job-server/scripts/backup_database.sh

# cron で毎日午前3時に自動バックアップ（オプション）
# crontab -e で以下を追加:
# 0 3 * * * /Users/macstudio/Projects/RemotePrompt/remote-job-server/scripts/backup_database.sh >> /Users/macstudio/Projects/RemotePrompt/remote-job-server/logs/backup.log 2>&1
```

---

## トラブルシューティング

### よくある問題

1. **Claude Code信頼ダイアログ**
   - 対処: `cwd=self.trusted_directory` 設定
   - 事前に手動でディレクトリを信頼済みにする

2. **Codex セッションID抽出失敗**
   - 対処: 正規表現パターン確認
   - ログ出力で実際の出力形式確認

3. **DBロック**
   - 対処: `check_same_thread=False` 設定確認
   - セッション適切にclose()

4. **タイムアウト頻発**
   - 対処: timeout値調整（300秒 → 600秒）
   - プロンプト内容簡素化

---

## 次のステップ

サーバー実装完了後：
1. iOS クライアントアプリ実装計画策定
2. APNs プッシュ通知実装
3. Apple Watch アプリ実装

---

**End of Implementation Plan**
