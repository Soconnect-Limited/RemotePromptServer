# 非対話モード方式 MacStudio ⇔ iPhone/Apple Watch ジョブ実行システム 詳細技術仕様書

作成日: 2025-11-16
最終更新: 2025-12-03
バージョン: 4.5（AIプロバイダー設定機能）
想定作成者: Nao

**変更履歴**:
- v1.0 (2025-11-16): PTY永続セッション方式での初版
- v2.0 (2025-11-17): 調査結果に基づき非対話モード + セッション管理方式に変更
- v3.0 (2025-11-19): Room-Based Architecture実装に伴う仕様追加 - プロジェクト/ワークスペース別のセッション分離と作業ディレクトリ管理を実現
- v4.0 (2025-11-21): Thread Management実装 - Room内でRunnerごとに独立したスレッドを作成・管理、4次元セッション管理（device_id + room_id + runner + thread_id）を実現
- v4.1 (2025-01-21): Thread Management API拡張 - サーバー側runnerフィルタ実装、limit/offsetページネーション追加、PATCH API device_id必須化、互換モード（thread_id NULL）明記
- v4.2 (2025-01-22): Thread Simplification - Thread.runnerフィールド削除、同一Thread内でrunner自由切替を可能に。iOS SSE修正（メインスレッドブロッキング・入力フリーズ解消）、Codex 0.63.0互換性対応（reasoning_effort: extra-high → xhigh）
- v4.3 (2025-11-23): SSE初期スナップショット送信を必須化、heartbeat(30s)導入、iOS delegateQueueを`.main`固定、SSE接続タイムアウト60秒、iOSバッファ上限1MB、ログ取得手順更新
- v4.4 (2025-12-02): URLSession最適化（タイムアウト短縮・コネクション再利用）、接続ウォームアップ機能追加（TLSハンドシェイク事前実行）、RoomsListViewツールバー統合（Auto Layout警告修正）
- v4.5 (2025-12-03): AIプロバイダー設定機能 - Claude Code/Codex/Geminiの3種類対応、プロバイダー有効化・順序変更・Bashパス設定をサポート

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
10. [Thread Management（スレッド管理）](#10-thread-managementスレッド管理)
11. [セキュリティとエラーハンドリング](#11-セキュリティとエラーハンドリング)
    - 11.1 [セキュリティ対策](#111-セキュリティ対策)
    - 11.2 [エラーハンドリング](#112-エラーハンドリング)
    - 11.3 [ロギング](#113-ロギング)
    - 11.4 [Workspace Trust Model（v3.0で追加）](#114-workspace-trust-modelv30で追加)
12. [実装ロードマップ](#12-実装ロードマップ)
    - 12.1-12.7 [Phase 1-7](#phase-1-非対話モード実装1-2日)
    - 12.8 [Phase 8: v2.0 → v3.0 移行（v3.0で追加）](#phase-8-v20--v30-移行v30で追加)
13. [運用・保守](#13-運用保守)
14. [付録: PTY方式調査結果](#14-付録pty方式調査結果)

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

#### Claude Code権限設定（必須）

**非対話的実行のため、`.claude/settings.local.json`で自動承認設定が必要**

```json
{
  "permissions": {
    "allow": [
      "Bash",
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "mcp__serena__*",
      "mcp__sequential-thinking__*",
      "mcp__context7__*",
      "Task",
      "TodoWrite",
      "NotebookEdit",
      "Skill",
      "SlashCommand",
      "BashOutput",
      "KillShell"
    ],
    "deny": [],
    "ask": []
  }
}
```

**重要事項**:
- この設定がないと、`claude --print`実行時に確認プロンプトが表示され、非対話モードでの実行が失敗する
- 設定変更後はVSCode/Claude Codeセッションの再起動が必須
- プロジェクトローカル設定（`.claude/settings.local.json`）のため、プロジェクトごとに設定が必要
- セキュリティ上、信頼できるプロジェクトのみでこの設定を使用すること

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
│  │ - Room List  │◄────────►│ - Presets    │ ← v3.0   │
│  │ - Room Chat  │          │ - Quick Send │            │
│  │ - Job List   │          └──────────────┘            │
│  │ - Job Detail │                                        │
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
│  │  - /rooms (GET, POST, DELETE)   ← v3.0     │        │
│  │  - /messages (GET)              ← v3.0     │        │
│  │  - /sessions (GET, DELETE)      ← v3.0拡張 │        │
│  │  - /register_device (POST)                  │        │
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
│  │  - rooms table (name, workspace_path) ← v3.0│       │
│  │  - devices table                             │       │
│  │  - device_sessions (device+room+runner) ← v3.0 │    │
│  └──────────────────────────────────────────────┘      │
│                                                          │
│  ┌─────────────────────────────────────────────┐       │
│  │       APNs Client (Push Notification)        │       │
│  └──────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────┘
```

### 2.2 データフロー

#### ジョブ実行フロー（v3.0: Room-Based）

```
1. iPhone → POST /jobs {runner: "claude", input_text: "質問", device_id: "iphone-nao-1", room_id: "abc123"}
2. Server → roomsテーブルからworkspace_pathを取得
3. Server → Job DB に保存 (status: queued, room_id: "abc123")
4. Server → Session Manager: execute_job("claude", "質問", device_id, room_id, workspace_path)
5. Session Manager → device_sessions DBから (device_id, room_id, runner) でセッションIDを取得（初回はNone）
6a. 【初回】Session Manager → UUID生成、subprocess.run(['claude', '--print', '--session-id', <UUID>], input="質問", cwd=workspace_path)
6b. 【2回目以降】Session Manager → subprocess.run(['claude', '--print', '--resume', <session_id>], input="質問", cwd=workspace_path)
7. claude → 処理実行（MCP使用可、workspace_pathで作業）
8. subprocess ← claude: 応答テキスト
9. Session Manager → セッションIDを device_sessions DBに保存 (device_id, room_id, runner, session_id)
10. Server ← 結果を受け取り
11. Job DB → 更新 (status: success, stdout: "応答", finished_at: now)
12. APNs → iPhone へプッシュ通知送信
13. iPhone ← 通知受信 → タップ → GET /jobs/{id} → 結果表示
14. 次回ジョブ → Session Manager が device_sessions DBから (device_id, room_id, runner) で前回セッションIDを取得し、--resumeで継続

※ v3.0の変更点:
- room_idパラメータ追加により、同一デバイスでも複数プロジェクトの独立したセッション管理が可能
- workspace_pathによりルームごとに異なる作業ディレクトリでコマンド実行
- (device_id, room_id, runner)の3次元でセッションを分離
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
    uvicorn.run(app, host="0.0.0.0", port=35000)
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

#### rooms テーブル（v3.0で追加）

プロジェクト/ワークスペースごとのセッション分離を実現。各ルームは独立した作業ディレクトリと会話コンテキストを持つ。

```sql
CREATE TABLE rooms (
    id TEXT PRIMARY KEY,                  -- UUID v4
    device_id TEXT NOT NULL,              -- 所有デバイスID
    name TEXT NOT NULL,                   -- ルーム名（例: "AI Trading Project"）
    workspace_path TEXT NOT NULL,         -- 作業ディレクトリパス（例: "/Users/nao/Projects/AITrading"）
    icon TEXT NOT NULL DEFAULT 'folder',  -- アイコン識別子（例: "folder", "gear", "doc.text"）
    created_at DATETIME NOT NULL,         -- 作成日時
    updated_at DATETIME NOT NULL,         -- 更新日時
    FOREIGN KEY (device_id) REFERENCES devices(device_id)
);

CREATE INDEX idx_rooms_device_id ON rooms(device_id);
CREATE INDEX idx_rooms_updated_at ON rooms(updated_at DESC);
```

**セキュリティ考慮事項**:
- `workspace_path`は§10.4で定義されるホワイトリストによって検証される
- パストラバーサル攻撃を防ぐため`Path.resolve()`で正規化後チェック
- 許可されたディレクトリ以外へのアクセスは拒否される

#### threads テーブル（v4.0で追加）

ルーム内でRunnerごとに独立した会話スレッドを管理。複数の会話コンテキストを並行して維持できる。

```sql
CREATE TABLE threads (
    id TEXT PRIMARY KEY,                  -- UUID v4
    room_id TEXT NOT NULL,                -- 所属ルームID
    name TEXT NOT NULL DEFAULT '無題',    -- スレッド名（例: "認証機能の実装"）
    runner TEXT NOT NULL,                 -- "claude" or "codex"
    device_id TEXT NOT NULL,              -- 作成デバイスID
    created_at DATETIME NOT NULL,         -- 作成日時
    updated_at DATETIME NOT NULL,         -- 更新日時
    FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
);

CREATE INDEX idx_threads_room_runner ON threads(room_id, runner);
CREATE INDEX idx_threads_updated_at ON threads(updated_at DESC);
```

**設計意図**（v4.0 Thread Management）:
- **4次元セッション管理**: device_id + room_id + runner + thread_id でセッションを一意に識別
- **Runner別フィルタリング**: UI上でClaude/Codexを切り替える際、各Runnerのスレッド一覧を独立表示
- **会話コンテキスト分離**: 同じRoomでも複数の並行タスク（例: "バグ修正"/"新機能開発"）を独立管理
- **後方互換性（v4.0互換モード）**: `thread_id`がnilの場合はデフォルトスレッドを使用**[v4.1で詳細明記]**
  - 旧クライアント（v3.x）はthread_idパラメータを送信しない → thread_id=NULLで処理
  - サーバー側ではthread_id=NULLの場合、自動的にデフォルトスレッド扱い
  - v4.0以降のクライアントはthread_idを明示的に指定（またはnil送信で互換モード）

#### jobs テーブル

```sql
CREATE TABLE jobs (
    id TEXT PRIMARY KEY,              -- UUID v4
    runner TEXT NOT NULL,              -- "claude" or "codex"
    input_text TEXT NOT NULL,          -- ユーザー入力
    device_id TEXT NOT NULL,           -- デバイスID (例: "iphone-nao-1")
    room_id TEXT NOT NULL,             -- v3.0: ルームID（必須）
    thread_id TEXT,                    -- v4.0: スレッドID（Optionalで後方互換性確保）
    status TEXT NOT NULL,              -- queued/running/success/failed
    exit_code INTEGER,                 -- 0=成功, 1=失敗
    stdout TEXT,                       -- 標準出力
    stderr TEXT,                       -- エラー出力
    created_at DATETIME NOT NULL,      -- 作成日時
    started_at DATETIME,               -- 実行開始日時
    finished_at DATETIME,              -- 終了日時
    notify_token TEXT,                 -- APNs device token
    FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE SET NULL  -- v4.0: スレッド削除時はNULLに
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at DESC);
CREATE INDEX idx_jobs_device_id ON jobs(device_id);
CREATE INDEX idx_jobs_room_id ON jobs(room_id);                    -- v3.0: ルームIDインデックス
CREATE INDEX idx_jobs_device_room ON jobs(device_id, room_id);     -- v3.0: 複合インデックス
CREATE INDEX idx_jobs_thread_id ON jobs(thread_id);                -- v4.0: スレッドIDインデックス
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
    device_id TEXT NOT NULL,                      -- "iphone-nao-1"
    room_id TEXT NOT NULL,                        -- v3.0: ルームID（必須）
    runner TEXT NOT NULL,                         -- "claude" or "codex"
    thread_id TEXT,                               -- v4.0: スレッドID（Optionalで後方互換性確保）
    session_id TEXT NOT NULL,                     -- Claude/Codex両方のセッションID
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE(device_id, room_id, runner, thread_id), -- v4.0: 4次元管理（デバイス+ルーム+runner+スレッド）
    FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE  -- v4.0: スレッド削除時はカスケード削除
);

CREATE INDEX idx_device_sessions ON device_sessions(device_id, room_id, runner, thread_id); -- v4.0: 4次元インデックス
```

**セッションID管理方式**:
- **Claude Code**: `--session-id <UUID>`で新規作成、`--resume <sessionId>`で継続
- **Codex**: `codex exec`で自動生成、`exec resume <sessionId>`で継続

**v3.0での変更点（Room-Based Architecture）**:
- セッション管理が2次元（device_id + runner）から3次元（device_id + room_id + runner）に拡張

**v4.0での変更点（Thread Management）**:
- セッション管理が3次元から4次元（device_id + room_id + runner + thread_id）に拡張
- 同じRunnerでも複数のスレッドごとに独立したセッションを維持可能
- `thread_id`がNULLの場合は互換モードとしてデフォルトスレッドを使用
- 同じデバイスでも、ルームごとに独立したセッションを維持可能
- 例: iPhone上で "AI Trading" ルームと "Web App" ルームを並行して使用可能
- 各ルームは独立した会話履歴とMCP接続状態を保持

### 5.2 SQLAlchemy モデル

```python
# models.py
from sqlalchemy import Column, Integer, String, DateTime, Text, ForeignKey, UniqueConstraint
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()

class Room(Base):  # v3.0: 新規追加
    """プロジェクト/ワークスペース管理テーブル"""
    __tablename__ = 'rooms'

    id = Column(String(36), primary_key=True)
    device_id = Column(String(100), ForeignKey('devices.device_id'), nullable=False)
    name = Column(String(200), nullable=False)
    workspace_path = Column(String(500), nullable=False)
    icon = Column(String(50), nullable=False, default='folder')
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    threads = relationship("Thread", back_populates="room", cascade="all, delete-orphan")  # v4.0: 追加
    jobs = relationship("Job", back_populates="room", cascade="all, delete-orphan")
    sessions = relationship("DeviceSession", back_populates="room", cascade="all, delete-orphan")

    def to_dict(self):
        return {
            'id': self.id,
            'device_id': self.device_id,
            'name': self.name,
            'workspace_path': self.workspace_path,
            'icon': self.icon,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }

class Thread(Base):  # v4.0: 新規追加
    """スレッド管理テーブル（会話コンテキスト分離）"""
    __tablename__ = 'threads'

    id = Column(String(36), primary_key=True)
    room_id = Column(String(36), ForeignKey('rooms.id', ondelete='CASCADE'), nullable=False)
    name = Column(String(100), nullable=False, default='無題')
    runner = Column(String(20), nullable=False)
    device_id = Column(String(100), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    room = relationship("Room", back_populates="threads")
    jobs = relationship("Job", back_populates="thread", cascade="all, delete-orphan")
    sessions = relationship("DeviceSession", back_populates="thread", cascade="all, delete-orphan")

    def to_dict(self):
        return {
            'id': self.id,
            'room_id': self.room_id,
            'name': self.name,
            'runner': self.runner,
            'device_id': self.device_id,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }

class Job(Base):
    __tablename__ = 'jobs'

    id = Column(String(36), primary_key=True)
    runner = Column(String(20), nullable=False)
    input_text = Column(Text, nullable=False)
    device_id = Column(String(100), nullable=False)
    room_id = Column(String(36), ForeignKey('rooms.id', ondelete='CASCADE'), nullable=False)  # v3.0: 必須化
    thread_id = Column(String(36), ForeignKey('threads.id', ondelete='SET NULL'))  # v4.0: スレッドID（Optional）
    status = Column(String(20), nullable=False)
    exit_code = Column(Integer)
    stdout = Column(Text)
    stderr = Column(Text)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    notify_token = Column(String(255))

    # Relationships
    room = relationship("Room", back_populates="jobs")
    thread = relationship("Thread", back_populates="jobs")  # v4.0: 追加

    def to_dict(self):
        return {
            'id': self.id,
            'runner': self.runner,
            'input_text': self.input_text,
            'device_id': self.device_id,
            'room_id': self.room_id,  # v3.0: 追加
            'thread_id': self.thread_id,  # v4.0: 追加
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

    # Relationships
    rooms = relationship("Room", backref="device")

class DeviceSession(Base):  # v4.0: thread_id追加
    """デバイス・ルーム・runner・スレッドごとのセッション管理"""
    __tablename__ = 'device_sessions'

    id = Column(Integer, primary_key=True, autoincrement=True)
    device_id = Column(String(100), nullable=False)
    room_id = Column(String(36), ForeignKey('rooms.id', ondelete='CASCADE'), nullable=False)  # v3.0: 必須化
    runner = Column(String(20), nullable=False)
    thread_id = Column(String(36), ForeignKey('threads.id', ondelete='CASCADE'))  # v4.0: スレッドID（Optional）
    session_id = Column(String(100), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    # v4.0: 4次元ユニーク制約
    __table_args__ = (
        UniqueConstraint('device_id', 'room_id', 'runner', 'thread_id', name='uix_device_room_runner_thread'),
    )

    # Relationships
    room = relationship("Room", back_populates="sessions")
    thread = relationship("Thread", back_populates="sessions")  # v4.0: 追加

    def to_dict(self):
        return {
            'id': self.id,
            'device_id': self.device_id,
            'room_id': self.room_id,  # v3.0: 追加
            'runner': self.runner,
            'thread_id': self.thread_id,  # v4.0: 追加
            'session_id': self.session_id,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
```

---

## 6. REST API 仕様

### 6.1 ベースURL

```
http://100.100.30.35:35000
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
  "device_id": "iphone-nao-1",
  "room_id": "room-uuid-abc-123",
  "thread_id": "thread-uuid-def-456"
}
```

**v3.0での変更点**:
- `room_id`が必須パラメータになりました
- 指定されたルームの`workspace_path`をcwdとして使用
- セッション管理が(device_id, room_id, runner)の3次元で行われる

**v4.0での変更点**:
- `thread_id`がOptionalパラメータとして追加されました
- thread_idが指定された場合、そのスレッドに紐づけてジョブを記録
- thread_idがnilの場合は互換モードとしてデフォルトスレッドを使用
- セッション管理が(device_id, room_id, runner, thread_id)の4次元で行われる

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "runner": "claude",
  "status": "queued"
}
```

**処理フロー:**
1. DBにジョブレコード作成（status: queued）
2. `room_id`からRoom情報を取得し`workspace_path`を検証（§10.4参照）
3. BackgroundTasksで`_execute_job()`を実行
4. SessionManager経由で非対話モードCLI（`claude --print` / `codex exec`）を起動
   - `cwd`パラメータに`workspace_path`を指定
   - (device_id, room_id, runner)でセッションを検索・継続
5. 結果をDBに保存
6. APNs通知送信

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

デバイス・ルームごとのセッション状態を取得。

**Query Parameters:**
- `device_id`: デバイスID（必須）
- `room_id`: ルームID（必須） ← v3.0で追加

**v3.0での変更点**:
- `room_id`が必須パラメータになりました
- レスポンスは指定されたルーム内のセッション情報のみを返します

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

#### DELETE /sessions

指定されたデバイス・ルーム・runnerのセッションを削除（新規会話開始）。

**Query Parameters:**
- `device_id`: デバイスID（必須）
- `room_id`: ルームID（必須） ← v3.0で追加
- `runner`: "claude" or "codex"（必須） ← v3.0で追加

**v3.0での変更点**:
- パスパラメータからクエリパラメータに変更
- `room_id`が必須になりました
- 削除対象が(device_id, room_id, runner)の3次元で特定されます

**Example:**
```
DELETE /sessions?device_id=iphone-nao-1&room_id=room-uuid-abc-123&runner=claude
```

**Response:**
```json
{
  "status": "deleted",
  "runner": "claude",
  "device_id": "iphone-nao-1",
  "room_id": "room-uuid-abc-123"
}
```

---

#### GET /rooms（v3.0で追加）

デバイスに紐づくルーム一覧を取得。

**Query Parameters:**
- `device_id`: デバイスID（必須）

**Response:**
```json
[
  {
    "id": "room-uuid-1",
    "device_id": "iphone-nao-1",
    "name": "AI Trading Project",
    "workspace_path": "/Users/nao/Projects/AITrading",
    "icon": "folder",
    "created_at": "2025-11-19T10:00:00.123456",
    "updated_at": "2025-11-19T15:30:00.654321"
  },
  {
    "id": "room-uuid-2",
    "device_id": "iphone-nao-1",
    "name": "Web App Development",
    "workspace_path": "/Users/nao/Projects/WebApp",
    "icon": "gear",
    "created_at": "2025-11-18T09:00:00.111111",
    "updated_at": "2025-11-19T12:00:00.222222"
  }
]
```

---

#### POST /rooms（v3.0で追加）

新規ルームを作成。

**Request:**
```json
{
  "device_id": "iphone-nao-1",
  "name": "New Project",
  "workspace_path": "/Users/nao/Projects/NewProject",
  "icon": "doc.text"
}
```

**セキュリティチェック:**
- `workspace_path`は§10.4のホワイトリストで検証
- 不正なパスの場合は400エラーを返す

**Response:**
```json
{
  "id": "room-uuid-new",
  "device_id": "iphone-nao-1",
  "name": "New Project",
  "workspace_path": "/Users/nao/Projects/NewProject",
  "icon": "doc.text",
  "created_at": "2025-11-19T16:00:00.000000",
  "updated_at": "2025-11-19T16:00:00.000000"
}
```

---

#### DELETE /rooms/{room_id}（v3.0で追加）

ルームを削除。

**Query Parameters:**
- `device_id`: デバイスID（必須、認証用）

**Effect:**
- Roomレコード削除（CASCADE）
- 関連するJobレコードも削除
- 関連するDeviceSessionレコードも削除

**Example:**
```
DELETE /rooms/room-uuid-abc-123?device_id=iphone-nao-1
```

**Response:**
```json
{
  "status": "deleted",
  "room_id": "room-uuid-abc-123"
}
```

---

#### Files API `/rooms/{room_id}/files`（v3.0追加）

ルームの `workspace_path` 配下にあるディレクトリと `.md` ファイルへの安全なアクセスを提供する。

**共通セキュリティ**  
- 認証: `device_id` (query) 必須  
- 認可: `room_id` に紐づく `rooms.device_id` と一致すること  
- パストラバーサル防止: `unquote(unquote())` + `\\ -> /` 正規化 + `.resolve()` + `.relative_to(base)`  
- 拡張子制限: `.md` のみ  
- サイズ制限: 500KB 超は `413 Payload Too Large`  
- パスエンコーディング: パスセグメント中の `/` は `%2F` にエンコード（FastAPI `{filepath:path}` ワイルドカードで受ける）

##### GET /rooms/{room_id}/files
ディレクトリ一覧を取得。

Query:
- `device_id` (必須)
- `path` (任意, default=\"\") 相対パス

Response 200:
```json
[
  {
    "name": "Docs",
    "type": "directory",
    "path": "Docs",
    "size": null,
    "modified_at": "2025-11-20T10:30:00Z"
  },
  {
    "name": "README.md",
    "type": "markdown_file",
    "path": "README.md",
    "size": 5234,
    "modified_at": "2025-11-19T15:45:00Z"
  }
]
```

##### GET /rooms/{room_id}/files/{filepath:path}
Markdownファイルを取得。`filepath` は URLエンコード済み相対パス（例: `Docs%2FREADME.md`）。

Query:
- `device_id` (必須)

Response:
- Content-Type: `text/plain; charset=utf-8`
- Body: ファイル内容

##### PUT /rooms/{room_id}/files/{filepath:path}
Markdownファイルを保存（バックアップ1世代 `.bak` 作成）。

Query:
- `device_id` (必須)

Request:
- Content-Type: `text/plain; charset=utf-8`
- Body: 新しい内容（UTF-8）

Response 200:
```json
{
  "message": "File saved",
  "path": "Docs/README.md",
  "size": 5432,
  "backup_created": true
}
```

##### エラーステータス
- 400: 不正パス / 拡張子不正 / UTF-8でない
- 401: x-api-key 不正
- 403: room所有権なし / PermissionError
- 404: ファイル/ディレクトリ不存在
- 413: 500KB超過
- 500: サーバー内部エラー

---

#### Thread Management API（v4.0で追加）

##### GET /rooms/{room_id}/threads

ルーム内のスレッド一覧を取得。

**Query Parameters:**
- `device_id`: デバイスID（必須、認証用）
- `runner`: "claude" または "codex"（Optional、指定時は該当runnerのみフィルタ）**[v4.1: サーバー側フィルタ実装済み]**
- `limit`: 最大取得件数（Optional、デフォルト: 50、最大: 200）**[v4.1で追加]**
- `offset`: オフセット（Optional、デフォルト: 0、ページネーション用）**[v4.1で追加]**

**Response:**
```json
[
  {
    "id": "thread-uuid-def-456",
    "room_id": "room-uuid-abc-123",
    "name": "認証機能の実装",
    "runner": "claude",
    "device_id": "iphone-nao-1",
    "created_at": "2025-11-20T10:00:00Z",
    "updated_at": "2025-11-20T15:30:00Z"
  },
  {
    "id": "thread-uuid-ghi-789",
    "room_id": "room-uuid-abc-123",
    "name": "UIリファクタリング",
    "runner": "claude",
    "device_id": "iphone-nao-1",
    "created_at": "2025-11-19T14:00:00Z",
    "updated_at": "2025-11-19T16:45:00Z"
  }
]
```

**Note:**
- **[v4.1]** サーバー側でrunnerパラメータによるフィルタリング実装済み（WHERE runner = ?）
- **[v4.1]** limit/offsetによるページネーション実装済み（LIMIT ? OFFSET ?）
- スレッドは`updated_at`降順でソートされる（ORDER BY updated_at DESC）
- limitを超えるスレッドがある場合、`offset + limit`で次のページを取得可能

**Example:**
```
# 最新50件取得
GET /rooms/room-uuid-abc-123/threads?device_id=iphone-nao-1&limit=50

# Claudeのスレッドのみ取得
GET /rooms/room-uuid-abc-123/threads?device_id=iphone-nao-1&runner=claude

# 51件目〜100件目を取得（ページネーション）
GET /rooms/room-uuid-abc-123/threads?device_id=iphone-nao-1&limit=50&offset=50
```

---

##### POST /rooms/{room_id}/threads?device_id={device_id}

新しいスレッドを作成。

**Query Parameters:**
- `device_id` (string, required): デバイスID（認証・権限チェック用）

**Request Body:**
```json
{
  "name": "新機能開発",
  "runner": "claude"
}
```

**Response:**
```json
{
  "id": "thread-uuid-new-123",
  "room_id": "room-uuid-abc-123",
  "name": "新機能開発",
  "runner": "claude",
  "device_id": "iphone-nao-1",
  "created_at": "2025-11-21T10:00:00Z",
  "updated_at": "2025-11-21T10:00:00Z"
}
```

---

##### PATCH /threads/{thread_id}

スレッド名を更新。

**Query Parameters:**
- `device_id`: デバイスID（必須、認証用）**[v4.1で明記]**

**Request Body:**
```json
{
  "name": "新しいスレッド名"
}
```

**Response:**
```json
{
  "id": "thread-uuid-def-456",
  "room_id": "room-uuid-abc-123",
  "name": "新しいスレッド名",
  "runner": "claude",
  "device_id": "iphone-nao-1",
  "created_at": "2025-11-20T10:00:00Z",
  "updated_at": "2025-11-21T11:00:00Z"
}
```

**Example:**
```
PATCH /threads/thread-uuid-def-456?device_id=iphone-nao-1
Body: {"name": "新しいスレッド名"}
```

---

##### DELETE /threads/{thread_id}

スレッドを削除。

**Query Parameters:**
- `device_id`: デバイスID（必須、認証用）

**Effect:**
- **Threadレコード削除**（DELETE FROM threads WHERE id = ?）
- **関連するJobレコードの`thread_id`はNULLに設定**（ON DELETE SET NULL）**[v4.1で明記]**
  - Jobsは削除されず、thread_id = NULLとして保持される
  - これによりThread削除後もJob履歴は保持される
- **関連するDeviceSessionレコードは削除**（ON DELETE CASCADE）**[v4.1で明記]**
  - Session情報はThreadと共に削除される

**Example:**
```
DELETE /threads/thread-uuid-def-456?device_id=iphone-nao-1
```

**Response:**
```
204 No Content
```

**Note:**
- **[v4.1]** JobsはCASCADE削除されない。thread_idがNULLになるだけでJob履歴は保持される。
- **[v4.1]** DeviceSessionsはCASCADE削除される。Thread削除後はセッション再確立が必要。

---

#### GET /messages（v3.0で追加）

指定されたルーム内のジョブ履歴を時系列で取得（チャット画面用）。

**Query Parameters:**
- `device_id`: デバイスID（必須）
- `room_id`: ルームID（必須）
- `runner`: "claude" または "codex"（必須）
- `thread_id`: スレッドID（Optional、v4.0で追加）
- `limit`: 最大取得件数（デフォルト: 50）
- `offset`: オフセット（デフォルト: 0、ページネーション用）

**Response:**
```json
[
  {
    "id": "job-uuid-1",
    "runner": "claude",
    "input_text": "Pythonでクイックソートを実装して",
    "stdout": "以下のように実装できます:\n\ndef quicksort(arr):\n    ...",
    "status": "success",
    "created_at": "2025-11-19T10:00:00.000000",
    "finished_at": "2025-11-19T10:02:30.000000"
  },
  {
    "id": "job-uuid-2",
    "runner": "codex",
    "input_text": "このコードをリファクタリングして",
    "stdout": "リファクタリング結果:\n\n...",
    "status": "success",
    "created_at": "2025-11-19T10:05:00.000000",
    "finished_at": "2025-11-19T10:07:15.000000"
  }
]
```

**実装仕様:**
- `jobs`テーブルから`(device_id, room_id, runner)`でフィルタリング
- v4.0: `thread_id`が指定された場合は追加でフィルタリング
- `created_at DESC`でソート
- `offset`からスキップして`limit`件数まで取得
- ページネーション対応（古い履歴の遡り閲覧用）

---

## 7. リアルタイム通知設計

> **2つの通知方式**: バックグラウンド通知（APNs）+ フォアグラウンド更新（SSE）

### 7.1 通知方式の使い分け

| 状況 | 通知方式 | 用途 |
|------|----------|------|
| **アプリがバックグラウンド** | APNs（Push Notification） | ジョブ完了を通知バナーで知らせる |
| **アプリがフォアグラウンド** | SSE（Server-Sent Events） | ジョブ詳細画面でリアルタイム状態更新 |
| **SSE接続失敗時** | ポーリング（GET /jobs/{id}） | フォールバック（5秒間隔） |

### 7.2 APNs設定

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

### 7.4 SSEストリーミング実装

> **フォアグラウンド専用**: アプリがジョブ詳細画面を表示している場合のリアルタイム更新

#### サーバー側エンドポイント

**GET /jobs/{job_id}/stream**

```python
# sse_manager.py
from fastapi import Request
from fastapi.responses import StreamingResponse
from typing import AsyncGenerator
import asyncio
import json

class SSEManager:
    def __init__(self):
        self.connections: dict[str, set[asyncio.Queue]] = {}

    async def subscribe(self, job_id: str) -> AsyncGenerator[str, None]:
        """SSE接続をサブスクライブ"""
        queue = asyncio.Queue()
        if job_id not in self.connections:
            self.connections[job_id] = set()
        self.connections[job_id].add(queue)

        try:
            while True:
                data = await queue.get()
                if data is None:  # 終了シグナル
                    break
                yield f"data: {json.dumps(data)}\n\n"
        finally:
            self.connections[job_id].discard(queue)

    async def broadcast(self, job_id: str, event_data: dict):
        """ジョブ状態変更をブロードキャスト"""
        if job_id in self.connections:
            for queue in self.connections[job_id]:
                await queue.put(event_data)

# main.py
@app.get("/jobs/{job_id}/stream")
async def stream_job_status(job_id: str, request: Request):
    async def event_generator():
        async for message in sse_manager.subscribe(job_id):
            if await request.is_disconnected():
                break
            yield message

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no"
        }
    )
```

#### ジョブ状態イベント

| イベント | タイミング | データ例 |
|----------|------------|----------|
| **job_started** | ジョブ開始時 | `{"status": "running", "started_at": "2025-11-18T10:00:00Z"}` |
| **job_completed** | ジョブ完了時 | `{"status": "success", "finished_at": "2025-11-18T10:05:00Z", "exit_code": 0}` |
| **job_failed** | ジョブ失敗時 | `{"status": "failed", "finished_at": "2025-11-18T10:02:00Z", "exit_code": 1}` |

#### クライアント側実装（Swift）

```swift
// SSEManager.swift
import Foundation

class SSEManager: ObservableObject {
    @Published var jobStatus: String = "queued"
    private var eventSource: EventSource?

    func connect(jobId: String) {
        let url = URL(string: "http://100.100.30.35:35000/jobs/\(jobId)/stream")!
        eventSource = EventSource(url: url)

        eventSource?.onMessage { message in
            if let data = message.data(using: .utf8),
               let json = try? JSONDecoder().decode(JobStatusEvent.self, from: data) {
                DispatchQueue.main.async {
                    self.jobStatus = json.status
                }
            }
        }

        eventSource?.connect()
    }

    func disconnect() {
        eventSource?.disconnect()
    }
}

struct JobStatusEvent: Codable {
    let status: String
    let started_at: String?
    let finished_at: String?
    let exit_code: Int?
}
```

#### フォールバック処理

SSE接続失敗時は従来のポーリングAPIに自動切替：

```swift
func startMonitoring(jobId: String) {
    // まずSSE接続を試行
    sseManager.connect(jobId: jobId)

    // 10秒後にSSE接続状態を確認
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        if !sseManager.isConnected {
            // SSE失敗時はポーリングに切替
            startPolling(jobId: jobId)
        }
    }
}

func startPolling(jobId: String) {
    pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
        Task {
            let job = try await apiClient.fetchJob(id: jobId)
            self.jobStatus = job.status
            if job.status == "success" || job.status == "failed" {
                self.pollingTimer?.invalidate()
            }
        }
    }
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
│   │   ├── Room.swift          ← v3.0: 追加
│   │   └── Device.swift
│   ├── ViewModels/              ← v3.0: 追加
│   │   ├── RoomStore.swift      ← v3.0: Room管理用ViewModel
│   │   └── ChatViewModel.swift  ← v3.0: Room連携チャット画面用
│   ├── Services/
│   │   ├── APIClient.swift
│   │   └── PushNotificationManager.swift
│   ├── Views/
│   │   ├── RoomListView.swift   ← v3.0: ルーム一覧画面
│   │   ├── RoomDetailView.swift ← v3.0: ルーム内チャット画面
│   │   ├── JobsListView.swift
│   │   ├── JobDetailView.swift
│   │   └── NewJobView.swift
│   └── Info.plist
└── RemoteJobClient Watch/
    └── ...
```

### 8.2 データモデル

#### Room.swift（v3.0で追加）

```swift
import Foundation

struct Room: Identifiable, Codable, Hashable {
    let id: String
    var name: String                // v3.0: 編集可能なため var
    var workspacePath: String       // v3.0: 編集可能なため var
    var icon: String                // v3.0: 編集可能なため var
    let deviceId: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case workspacePath = "workspace_path"
        case icon
        case deviceId = "device_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

#### Job.swift

```swift
import Foundation

struct Job: Identifiable, Codable {
    let id: String
    let runner: String
    let inputText: String
    let roomId: String              // v3.0: 必須化（String? → String）
    let status: String
    let exitCode: Int?
    let stdout: String?
    let stderr: String?
    let createdAt: Date?
    let startedAt: Date?
    let finishedAt: Date?

    var isRunning: Bool {
        status == "queued" || status == "running"
    }

    enum CodingKeys: String, CodingKey {
        case id, runner, status, stdout, stderr
        case inputText = "input_text"
        case roomId = "room_id"     // v3.0: 追加
        case exitCode = "exit_code"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

struct CreateJobRequest: Codable {
    let runner: String
    let inputText: String
    let deviceId: String
    let roomId: String              // v3.0: 必須化

    enum CodingKeys: String, CodingKey {
        case runner
        case inputText = "input_text"
        case deviceId = "device_id"
        case roomId = "room_id"     // v3.0: 追加
    }
}
```

### 8.3 API Client

```swift
// APIClient.swift
import Foundation

class APIClient: ObservableObject {
    static let shared = APIClient()
    
    private let baseURL = "http://100.100.30.35:35000"
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
    
    func createJob(runner: String, inputText: String, roomId: String) async throws -> Job {  // v3.0: roomId追加
        let url = URL(string: "\(baseURL)/jobs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateJobRequest(runner: runner, inputText: inputText, deviceId: deviceId, roomId: roomId)  // v3.0: roomId追加
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Job.self, from: data)
    }

    // v3.0: Room management methods
    func fetchRooms(deviceId: String) async throws -> [Room] {
        guard var components = URLComponents(string: "\(baseURL)/rooms") else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
        return try decoder.decode([Room].self, from: data)
    }

    func createRoom(name: String, workspacePath: String, deviceId: String, icon: String = "folder") async throws -> Room {
        let url = URL(string: "\(baseURL)/rooms")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "device_id": deviceId,
            "name": name,
            "workspace_path": workspacePath,
            "icon": icon
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { /* 同上のカスタムdecoder */ }
        return try decoder.decode(Room.self, from: data)
    }

    func deleteRoom(roomId: String, deviceId: String) async throws {
        guard var components = URLComponents(string: "\(baseURL)/rooms/\(roomId)") else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    func fetchMessages(deviceId: String, roomId: String, limit: Int = 50) async throws -> [Job] {
        guard var components = URLComponents(string: "\(baseURL)/messages") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "room_id", value: roomId),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { /* 同上のカスタムdecoder */ }
        return try decoder.decode([Job].self, from: data)
    }
}

enum APIError: Error {
    case requestFailed
    case invalidResponse
    case invalidURL  // v3.0: 追加
}
```

#### 8.3.1 URLSession最適化とウォームアップ（v4.4）

**概要**: アプリ起動時・フォアグラウンド復帰時の接続遅延を軽減するため、URLSession設定の最適化と接続ウォームアップ機能を実装。

**URLSession設定最適化**:
```swift
private func getSession() -> URLSession {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15           // リクエストタイムアウト: 15秒
    config.timeoutIntervalForResource = 30          // リソースタイムアウト: 30秒
    config.httpMaximumConnectionsPerHost = 4        // ホストあたりの最大接続数
    config.waitsForConnectivity = false             // 接続待機しない
    config.urlCache = URLCache(
        memoryCapacity: 10 * 1024 * 1024,           // メモリキャッシュ: 10MB
        diskCapacity: 50 * 1024 * 1024              // ディスクキャッシュ: 50MB
    )
    return URLSession(
        configuration: config,
        delegate: CertificatePinningDelegate.shared,
        delegateQueue: nil
    )
}
```

**接続ウォームアップ機能**:
```swift
/// TLSハンドシェイクを事前に実行してコネクションを確立
func warmupConnection() async {
    guard let url = URL(string: "\(Constants.baseURL)/health") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 5
    _ = try await getSession().data(for: request)
}
```

**呼び出しタイミング**:
- `ContentView.swift`の`.task`内でサーバー設定済みの場合に実行
- フォアグラウンド復帰時に再実行（`scenePhase`監視）

**効果**:
- 初回API呼び出し時のTLSハンドシェイク遅延を排除
- コネクション再利用によるレイテンシ削減

### 8.4 ナビゲーションの注意点（v4.2 hotfix）
- `FileBrowserView` の `.navigationDestination(for: FileItem)` はルートの `NavigationStack` にのみ宣言する。
- 子階層の `FileBrowserView` は destination を再宣言せず、ルートで定義したものを共有してディレクトリ遷移を行う。
- 目的: 重複登録によるビュー階層の肥大化とメモリ急増（iOS強制終了）の防止。
- `isRoot == false` の `FileBrowserView` は必ず NavigationStack 配下で使用する（単独表示では遷移不可）。

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

    let roomId: String  // v3.0: Room contextが必要
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
                    inputText: inputText,
                    roomId: roomId  // v3.0: roomId追加
                )
                dismiss()
            } catch {
                print("Failed to create job: \(error)")
            }
        }
    }
}
```

#### RoomListView.swift（v3.0で追加）

```swift
import SwiftUI

struct RoomListView: View {
    @State private var rooms: [Room] = []
    @State private var isLoading = false
    @State private var showingCreateRoom = false

    private let deviceId = APIClient.getDeviceId()

    var body: some View {
        NavigationView {
            List(rooms) { room in
                NavigationLink(destination: RoomDetailView(room: room)) {
                    RoomRowView(room: room)
                }
            }
            .navigationTitle("Rooms")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCreateRoom = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await loadRooms()
            }
            .task {
                await loadRooms()
            }
            .sheet(isPresented: $showingCreateRoom) {
                CreateRoomView(onCreated: { await loadRooms() })
            }
        }
    }

    func loadRooms() async {
        isLoading = true
        defer { isLoading = false }

        do {
            rooms = try await APIClient.shared.fetchRooms(deviceId: deviceId)
        } catch {
            print("Failed to load rooms: \(error)")
        }
    }
}

struct RoomRowView: View {
    let room: Room

    var body: some View {
        HStack {
            Image(systemName: room.icon)
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(room.name)
                    .font(.headline)
                Text(room.workspacePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

#### RoomDetailView.swift（v3.0で追加）

```swift
import SwiftUI

struct RoomDetailView: View {
    let room: Room
    @State private var messages: [Job] = []
    @State private var isLoading = false
    @State private var showingNewJob = false

    private let deviceId = APIClient.getDeviceId()

    var body: some View {
        VStack {
            // Room info header
            VStack(alignment: .leading, spacing: 4) {
                Text(room.workspacePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))

            // Message list (Jobs in this room)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { job in
                        MessageBubble(job: job)
                    }
                }
                .padding()
            }

            // Input area
            Button(action: { showingNewJob = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("新しいメッセージ")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle(room.name)
        .task {
            await loadMessages()
        }
        .refreshable {
            await loadMessages()
        }
        .sheet(isPresented: $showingNewJob) {
            NewJobView(roomId: room.id)  // v3.0: roomIdを渡す
        }
    }

    func loadMessages() async {
        isLoading = true
        defer { isLoading = false }

        do {
            messages = try await APIClient.shared.fetchMessages(
                deviceId: deviceId,
                roomId: room.id,
                limit: 50
            )
        } catch {
            print("Failed to load messages: \(error)")
        }
    }
}

struct MessageBubble: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // User input
            HStack {
                Spacer()
                Text(job.inputText ?? "")
                    .padding(12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }

            // AI response
            if let stdout = job.stdout, !stdout.isEmpty {
                HStack {
                    Text(stdout)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    Spacer()
                }
            }

            // Status indicator
            HStack {
                Text(job.runner)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(job.status)
                    .font(.caption2)
                    .foregroundColor(job.isRunning ? .orange : .green)
                if let createdAt = job.createdAt {
                    Text(createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
```

#### RoomsViewModel.swift（v3.0で追加）

- `@MainActor` 管理で `rooms`, `isLoading`, `errorMessage` を公開。
- `loadRooms()` は APIキー検証 → `GET /rooms` で取得 → `updated_at`/`created_at` 降順でソート。
- `createRoom` / `updateRoom` / `deleteRoom` は `APIClient` の対応メソッドをラップし、成功時に `rooms` 配列を即時更新。
- すべてのメソッドで `Constants.isAPIKeyConfigured` を確認し、未設定時はユーザーに案内する。

#### MessageStore（v3.0アップデート）

- `(roomId, runner)` をキーにしたインメモリキャッシュを保持し、既定で直近100件のみ保存。
- サーバーが唯一の情報源であるため永続化は廃止し、初期化時に `UserDefaults["chat_messages"]` が存在すれば読み込み→現行フォーマットへ変換→クリアする移行ロジックを実装。
- `setActiveContext` / `replaceAll` / `addMessage` / `updateMessage` / `clear` で対象ルームだけを更新し、他ルームのキャッシュには影響しない。

#### ChatView.swift（v3.0アップデート）

- `ChatView` は `ChatViewModel` を外部注入（`@ObservedObject`）し、`RoomDetailView` からClaude/Codex別インスタンスを共有できる。
- `ScrollViewReader + LazyVStack` の先頭にページングトリガーを設け、初回ロード完了後に上端へスクロールしたタイミングで `loadMoreMessages()` を実行。
- `.refreshable` で `loadLatestMessages()` を呼び出し、サーバー履歴を再取得。
- 入力バーは `viewModel.isLoading` と連動し、送信中はボタンを無効化。エラーは `viewModel.errorMessage` を監視してアラート表示。

#### AppEnvironment / PreviewAPIClient（v3.0補強）

- `Support/AppEnvironment.swift` が `isUITesting` を公開し、`-UITestMode` 引数でUIテスト専用モードに切り替え可能。
- `PreviewAPIClient`（`APIClientProtocol` 準拠）がインメモリデータを返し、ネットワークやAPIキーに依存しないE2Eテスト/プレビューを実現。
- `RoomsListView`/`RoomDetailView`/`ChatViewModel` は環境に応じて API クライアント・SSE・APIキー検証を切り替えるイニシャライザを持つ。
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
### 8.7 Markdownレンダリング要件

- `Views/MarkdownView.swift` は `MarkdownUI` がリンク可能な環境では `Markdown(content)` を使用し、GitHub互換テーマでの描画とフォント指定を行う。
- `MarkdownUI` がビルド対象から除外される watchOS / 一部CI構成に対応するため、`Support/MarkdownRenderer` を介して `AttributedString` を生成し、`ScrollView + Text` で確実に描画する。
- `MarkdownRenderer.render(_:)` は `AttributedString(markdown:)` を実行し、例外時はプレーンテキストへフォールバックする。依存性注入可能な `Parser` 引数を持ち、ユニットテストで異常系を再現できる。
- テスト要件: `RemotePromptTests/MarkdownRendererTests.swift` で (1) Markdown構文の変換、(2) 強制失敗時のフォールバック、(3) 空文字の取り扱いを `Testing` フレームワークで検証する。

#### 8.7.1 コードブロック専用UI実装（Phase B Refactor-13完了）

**実装日**: 2025-11-24

**概要**: チャットメッセージ内のMarkdownコードブロック（```言語名\nコード\n```）を専用UIで表示する機能を実装。

**主要コンポーネント**:
- `ChatListRepresentable.swift`:
  - `CodeBlockView`: コードブロック専用UIコンポーネント
    - ヘッダー: 言語名表示（大文字）+ コピーボタン
    - シンタックスハイライト: Swift/Python/JavaScript/Java/Go/Rust/C/C++対応
    - カラーリング: キーワード（紫）、文字列（赤）、コメント（緑）、数値（青）、関数名（青緑）、パラメータ名（オレンジ）
  - `MessageParser`: Markdownパーサー
    - コードブロックと通常テキストの分離
    - セグメント上限20個（DoS防止）
    - 100KB以上のメッセージで性能計測ログ出力
    - Markdown構文エラー時のフォールバック（プレーンテキスト表示）
  - `ChatMessageCell`: UIStackViewベースの混在レイアウト
    - UITextView（通常テキスト）とCodeBlockView（コードブロック）の動的配置
    - 1000文字以上の長文折りたたみ機能（expandButton）
    - セル再利用時の適切なクリーンアップ

**テスト**:
- `RemotePromptTests/MessageParserTests.swift`: パース機能のユニットテスト（8件）
- `RemotePromptTests/CodeBlockViewTests.swift`: CodeBlockViewのユニットテスト（5件）
- `RemotePromptUITests/ChatCodeBlockUITests.swift`: UI統合テスト（4件）

**性能**:
- 100KBメッセージのパース処理: <100ms（目標達成）
- スクロール性能: カクつきなし（実機確認済み）

**実装計画**: `Docs/Implementation_plans/BugFix/Plans/Phase_B_Refactor-13_CodeBlock_UIStackView_Implementation_Plan.md`

### 8.8 APIキー設定と構成値解決

- `Support/AppConfiguration.swift` が Info.plist → `Support/RemotePromptConfig.plist` → 環境変数 (`REMOTE_PROMPT_BASE_URL` / `REMOTE_PROMPT_API_KEY`) の順で値を解決し、`Constants` から `baseURL` と `apiKey` を提供する。
- `Support/RemotePromptConfig.plist` はリポジトリに雛形を含め、ローカル開発者がAPIキーやカスタムBaseURLを直接編集できる。CIでは環境変数で上書きする。
- APIキーは未設定の場合 `AppConfiguration.apiKey` が `nil` を返し、`Constants.isAPIKeyConfigured` で状態確認できる。`x-api-key` ヘッダーは送信されず、アプリ内でユーザー通知を行う。
- `RemotePromptTests/AppConfigurationTests.swift` で Info > Config > Env の優先順位とフォールバック、APIキー未設定時の`nil`返却を `Testing` フレームワークで検証する。
- `ChatViewModel` は送信時にAPIキー未設定を検出すると送信処理を中断し、`errorMessage` アラートで「RemotePromptConfig.plist / Info.plist / 環境変数を設定して再実行」と案内する。

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

## 10. Thread Management（スレッド管理）

### 10.1 概要

Thread Management（v4.0）は、Room内で独立した会話スレッドを作成・管理する機能です。複数の並行タスクを独立した会話コンテキストで処理できます。

**v4.2での重要な変更:**
- Thread.runnerフィールド削除 → 同一Thread内でrunner自由切替が可能に
- Thread = 純粋な会話履歴コンテナとして機能
- Runnerは各Jobで独立して指定（Thread作成時に固定不要）

**主要機能:**
- スレッド一覧表示
- 新規スレッド作成（runnerフィールドなし）
- スレッド名編集
- スレッド削除
- スレッド別メッセージ履歴の取得
- **同一Thread内でClaudeとCodexを混在可能**（v4.2）

### 10.2 アーキテクチャ

#### 4次元セッション管理

```
Device ID → Room ID → Runner → Thread ID → Session ID
  │           │         │          │
  │           │         │          └─ 会話コンテキスト（例: "認証機能実装"）
  │           │         └─ AI CLI（claude / codex）
  │           └─ プロジェクト/ワークスペース（例: "AITradingプロジェクト"）
  └─ デバイス（例: "iPhone-nao-1"）
```

**設計意図:**
- **Room**: プロジェクト/ワークスペース単位で作業環境を分離
- **Runner**: Claude Code / Codex を切り替え可能
- **Thread**: 同じRoomとRunner内で複数の並行タスクを管理
- **Session**: 各Thread固有の会話履歴とMCP接続を維持

#### UI階層構造

```
Room一覧
  └─ Room詳細
      └─ Runner選択（Claude / Codex タブ）
          └─ Thread一覧
              └─ Chat画面（スレッド固有の会話）
```

### 10.3 クライアント実装（iOS/SwiftUI）

#### Runner別フィルタリング

**仕様:**
- サーバー側 `GET /rooms/{room_id}/threads` は`runner`パラメータ未対応
- クライアント側で全件取得後にフィルタリング実施

**実装例（ThreadListViewModel.swift）:**
```swift
func fetchThreads() async {
    let allThreads = try await apiClient.fetchThreads(
        roomId: roomId,
        deviceId: deviceId,
        runner: nil  // サーバーはrunnerフィルタ未対応のため全件取得
    )
    // クライアント側でrunnerフィルタリング
    threads = allThreads.filter { $0.runner == runner }
}
```

#### Runner タブの保持

**設計判断:**
- 当初計画ではRunnerタブ削除を検討
- 実装では**Runnerタブを保持**してUXを改善
- Room → Runner選択 → Thread一覧 → Chat という明確な階層構造

**理由:**
- Claude/Codex を切り替える際のUX改善
- 各Runnerごとにスレッドを管理できる明確な構造
- Thread一覧でRunnerが混在しない

### 10.4 後方互換性

#### 互換モード（THREADS_COMPAT_MODE）

**目的:**
- Thread機能未対応の旧クライアントとの互換性維持
- 段階的なマイグレーション実現

**動作:**
1. `thread_id`が`nil`の場合、サーバーがデフォルトスレッドを自動選択
2. デフォルトスレッド名: "Default Thread"
3. 旧クライアントは従来通り動作（Threadを意識しない）

**データベース設計:**
- `jobs.thread_id`: `NULL`許容（`ON DELETE SET NULL`）
- `device_sessions.thread_id`: `NULL`許容（`ON DELETE CASCADE`）

### 10.5 ユースケース

#### ユースケース1: 並行開発タスク

**シナリオ:**
開発者が同じプロジェクト（Room）で、認証機能とUIリファクタリングを並行作業

**フロー:**
1. Room "WebAppプロジェクト" を選択
2. Runner "Claude" を選択
3. Thread一覧で「認証機能実装」スレッドを作成
4. Chatで認証に関する質問・実装を進行
5. Thread一覧に戻り「UIリファクタリング」スレッドを作成
6. 別の会話コンテキストでUI改善を進行

**メリット:**
- 会話が混在しない（認証の話題とUIの話題が分離）
- セッション履歴が独立（各タスクの文脈を保持）

#### ユースケース2: Runner別の使い分け

**シナリオ:**
同じプロジェクトでClaude（コード生成）とCodex（リファクタリング）を使い分け

**フロー:**
1. Room "AITradingプロジェクト" を選択
2. Runner "Claude" タブでThread「新機能開発」を選択してコード生成
3. Runner "Codex" タブに切り替え
4. Thread「コード最適化」を選択してリファクタリング

**メリット:**
- 各Runnerの得意分野を活用
- Runner切り替えが直感的

### 10.6 エラーハンドリング

#### スレッド削除時の動作

**データベースカスケード:**
- `threads`削除 → `jobs.thread_id` を `NULL` に設定（メッセージ履歴は保持）
- `threads`削除 → `device_sessions` も削除（セッションはリセット）

**UI動作:**
- スレッド削除後、Thread一覧画面に自動遷移
- 削除確認ダイアログを表示（誤削除防止）

#### API エラー処理

**ThreadListViewModel:**
```swift
@Published var errorMessage: String?

func deleteThread(threadId: String) async {
    do {
        try await apiClient.deleteThread(threadId: threadId, deviceId: deviceId)
        threads.removeAll { $0.id == threadId }
    } catch {
        errorMessage = "スレッド削除失敗: \(error.localizedDescription)"
    }
}
```

**Alert表示:**
```swift
.alert("エラー", isPresented: Binding(
    get: { viewModel.errorMessage != nil },
    set: { if !$0 { viewModel.errorMessage = nil } }
)) {
    Button("OK", role: .cancel) {
        viewModel.errorMessage = nil
    }
} message: {
    if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
    }
}
```

### 10.7 今後の拡張性

#### サーバー側Runnerフィルタ実装

**現状:**
- クライアント側で全件取得後にフィルタリング
- スレッド数が少ない場合は問題なし

**将来の改善:**
```python
# main.py
@app.get("/rooms/{room_id}/threads", response_model=List[ThreadResponse])
async def get_threads(
    room_id: str,
    device_id: str = Query(...),
    runner: Optional[str] = Query(None)  # Runnerフィルタ追加
):
    query = select(Thread).where(Thread.room_id == room_id)
    if runner:
        query = query.where(Thread.runner == runner)
    # ...
```

**メリット:**
- ネットワーク帯域削減
- クライアント処理負荷軽減

---

## 11. セキュリティとエラーハンドリング

### 11.1 セキュリティ対策

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

### 11.2 エラーハンドリング

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

### 11.3 ロギング

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

### 11.4 Workspace Trust Model（v3.0で追加）

Room-Based Architectureでは各ルームが独自の`workspace_path`を持ち、CLIはそのディレクトリで実行されます。パストラバーサル攻撃を防ぐため、以下のセキュリティモデルを実装します。

#### ホワイトリスト方式

```python
# security.py
from pathlib import Path
from typing import List
from fastapi import HTTPException

# 許可されたベースディレクトリのリスト
TRUSTED_BASE_DIRECTORIES: List[Path] = [
    Path("/Users/nao/Projects"),
    Path("/Users/nao/workspace"),
    Path("/Users/nao/Development")
]

def validate_workspace_path(workspace_path: str) -> Path:
    """
    workspace_pathがホワイトリストに含まれるか検証する

    Args:
        workspace_path: 検証対象のパス文字列

    Returns:
        正規化されたPathオブジェクト

    Raises:
        HTTPException: 不正なパスの場合
    """
    try:
        # 相対パス解決・シンボリックリンク解決
        resolved_path = Path(workspace_path).resolve(strict=False)
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid path format: {workspace_path}"
        )

    # ホワイトリストチェック
    for trusted_base in TRUSTED_BASE_DIRECTORIES:
        try:
            # resolved_pathがtrusted_baseの配下にあるか確認
            resolved_path.relative_to(trusted_base)
            return resolved_path  # 許可されたパス
        except ValueError:
            continue  # このベースディレクトリ配下ではない

    # どのホワイトリストにも該当しない
    raise HTTPException(
        status_code=403,
        detail=f"Workspace path not in trusted directories: {workspace_path}"
    )
```

#### POST /roomsでの適用

```python
# main.py
from security import validate_workspace_path

@app.post("/rooms")
async def create_room(
    device_id: str,
    name: str,
    workspace_path: str,
    icon: str = "folder"
):
    # ワークスペースパスの検証
    validated_path = validate_workspace_path(workspace_path)

    # 検証済みパスでRoomを作成
    room = Room(
        id=str(uuid.uuid4()),
        device_id=device_id,
        name=name,
        workspace_path=str(validated_path),  # 正規化されたパスを保存
        icon=icon,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow()
    )

    db.add(room)
    db.commit()
    return room.to_dict()
```

#### ジョブ実行時の適用

```python
# job_manager.py
from security import validate_workspace_path

def _execute_job(self, job_id: str):
    job = self.db.query(Job).filter_by(id=job_id).first()
    room = self.db.query(Room).filter_by(id=job.room_id).first()

    # 実行前に再度検証（DB改ざん対策）
    validated_cwd = validate_workspace_path(room.workspace_path)

    # 検証済みディレクトリでCLI実行
    result = subprocess.run(
        ["claude", "--print", prompt],
        cwd=str(validated_cwd),  # 検証済みパス
        capture_output=True,
        text=True,
        timeout=300
    )
```

#### セキュリティ特性

- **パストラバーサル防止**: `Path.resolve()`で`../`や symlink を解決後、ホワイトリストチェック
- **DB改ざん対策**: ジョブ実行時に毎回再検証
- **エラーメッセージ**: 攻撃者に有用な情報を与えない（パス詳細は返さない）
- **設定の柔軟性**: `TRUSTED_BASE_DIRECTORIES`は環境変数から読み込み可能

---

## 12. 実装ロードマップ

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

### Phase 8: v2.0 → v3.0 移行（v3.0で追加）

v2.0（デバイス別セッション管理）からv3.0（Room-Based Architecture）への移行手順。

#### 移行前の確認事項

1. **バックアップ取得**
   ```bash
   cp remote_jobs.db remote_jobs_v2_backup_$(date +%Y%m%d).db
   ```

2. **既存セッションの確認**
   ```sql
   SELECT device_id, runner, session_id FROM device_sessions;
   ```

#### データベースマイグレーション

```python
# migration_v2_to_v3.py
from sqlalchemy import create_engine, text
from datetime import datetime
import uuid

engine = create_engine('sqlite:///remote_jobs.db')

with engine.connect() as conn:
    # 1. roomsテーブル作成
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS rooms (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            name TEXT NOT NULL,
            workspace_path TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT 'folder',
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            FOREIGN KEY (device_id) REFERENCES devices(device_id)
        )
    """))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_rooms_device_id ON rooms(device_id)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_rooms_updated_at ON rooms(updated_at DESC)"))

    # 2. デバイスごとにデフォルトRoomを作成
    devices = conn.execute(text("SELECT DISTINCT device_id FROM device_sessions")).fetchall()
    default_rooms = {}

    for (device_id,) in devices:
        room_id = str(uuid.uuid4())
        now = datetime.utcnow()
        conn.execute(text("""
            INSERT INTO rooms (id, device_id, name, workspace_path, icon, created_at, updated_at)
            VALUES (:id, :device_id, :name, :workspace_path, :icon, :created_at, :updated_at)
        """), {
            "id": room_id,
            "device_id": device_id,
            "name": "Default Workspace",
            "workspace_path": "/Users/nao/workspace",  # v2.0のデフォルトパス
            "icon": "folder",
            "created_at": now,
            "updated_at": now
        })
        default_rooms[device_id] = room_id

    # 3. device_sessionsテーブルにroom_id追加
    conn.execute(text("ALTER TABLE device_sessions ADD COLUMN room_id TEXT"))

    # 4. 既存セッションにデフォルトroom_idを設定
    for device_id, room_id in default_rooms.items():
        conn.execute(text("""
            UPDATE device_sessions
            SET room_id = :room_id
            WHERE device_id = :device_id
        """), {"room_id": room_id, "device_id": device_id})

    # 5. room_idをNOT NULLに変更（SQLiteでは新テーブル作成+データコピーが必要）
    conn.execute(text("""
        CREATE TABLE device_sessions_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            runner TEXT NOT NULL,
            session_id TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            UNIQUE(device_id, room_id, runner),
            FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
        )
    """))

    conn.execute(text("""
        INSERT INTO device_sessions_new
        SELECT id, device_id, room_id, runner, session_id, created_at, updated_at
        FROM device_sessions
    """))

    conn.execute(text("DROP TABLE device_sessions"))
    conn.execute(text("ALTER TABLE device_sessions_new RENAME TO device_sessions"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_device_sessions ON device_sessions(device_id, room_id, runner)"))

    # 6. jobsテーブルにroom_id追加
    conn.execute(text("ALTER TABLE jobs ADD COLUMN room_id TEXT"))

    # 7. 既存ジョブにroom_idを設定
    for device_id, room_id in default_rooms.items():
        conn.execute(text("""
            UPDATE jobs
            SET room_id = :room_id
            WHERE device_id = :device_id
        """), {"room_id": room_id, "device_id": device_id})

    # 8. jobsテーブルのroom_idをNOT NULLに変更
    conn.execute(text("""
        CREATE TABLE jobs_new (
            id TEXT PRIMARY KEY,
            runner TEXT NOT NULL,
            input_text TEXT NOT NULL,
            device_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            status TEXT NOT NULL,
            exit_code INTEGER,
            stdout TEXT,
            stderr TEXT,
            created_at DATETIME NOT NULL,
            started_at DATETIME,
            finished_at DATETIME,
            notify_token TEXT,
            FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
        )
    """))

    conn.execute(text("""
        INSERT INTO jobs_new
        SELECT id, runner, input_text, device_id, room_id, status, exit_code,
               stdout, stderr, created_at, started_at, finished_at, notify_token
        FROM jobs
    """))

    conn.execute(text("DROP TABLE jobs"))
    conn.execute(text("ALTER TABLE jobs_new RENAME TO jobs"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at DESC)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_jobs_device_id ON jobs(device_id)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_jobs_room_id ON jobs(room_id)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_jobs_device_room ON jobs(device_id, room_id)"))

    conn.commit()
    print("✅ Migration completed: v2.0 → v3.0")
```

#### 実行手順

```bash
# 1. サーバー停止
systemctl stop remote-job-server

# 2. バックアップ
cp remote_jobs.db remote_jobs_v2_backup.db

# 3. マイグレーション実行
python3 migration_v2_to_v3.py

# 4. サーバー再起動
systemctl start remote-job-server

# 5. 動作確認
curl http://localhost:35000/rooms?device_id=iphone-nao-1
```

#### 移行後の確認

```sql
-- Roomsが作成されているか確認
SELECT * FROM rooms;

-- device_sessionsのroom_id確認
SELECT device_id, room_id, runner, session_id FROM device_sessions;

-- jobsのroom_id確認
SELECT id, device_id, room_id, status FROM jobs LIMIT 5;
```

#### iOSアプリの更新

1. 新バージョンをApp Storeまたは TestFlight経由で配信
2. 初回起動時に`GET /rooms`でデフォルトRoomを表示
3. 既存のジョブ履歴は"Default Workspace"に関連付けられて表示される

---

## 13. 運用・保守

### 13.1 サーバー起動

#### 手動起動（開発環境 - HTTP）
```bash
cd ~/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

#### 手動起動（本番環境 - HTTPS/SSL）
```bash
cd ~/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8443 \
  --ssl-keyfile=certs/config/live/remoteprompt.soconnect.co.jp/privkey.pem \
  --ssl-certfile=certs/config/live/remoteprompt.soconnect.co.jp/fullchain.pem
```

#### バックグラウンド起動（SSL）
```bash
cd ~/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8443 \
  --ssl-keyfile=certs/config/live/remoteprompt.soconnect.co.jp/privkey.pem \
  --ssl-certfile=certs/config/live/remoteprompt.soconnect.co.jp/fullchain.pem \
  > logs/server_ssl.log 2>&1 &
```

#### systemd（自動起動 - macOS非対応、Linux用）

```ini
# /etc/systemd/system/remote-job-server.service
[Unit]
Description=Remote Job Server (HTTPS)
After=network.target

[Service]
Type=simple
User=macstudio
WorkingDirectory=/Users/macstudio/Projects/RemotePrompt/remote-job-server
ExecStart=/Users/macstudio/Projects/RemotePrompt/remote-job-server/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8443 --ssl-keyfile=certs/config/live/remoteprompt.soconnect.co.jp/privkey.pem --ssl-certfile=certs/config/live/remoteprompt.soconnect.co.jp/fullchain.pem
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
curl "http://100.100.30.35:35000/sessions?device_id=iphone-nao-1"

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
curl -X DELETE "http://100.100.30.35:35000/sessions/claude?device_id=iphone-nao-1"
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
    PORT: int = 35000
    
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

## 14. 付録: PTY方式調査結果

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

## 15. v4.2 変更点詳細（2025-01-22）

### 15.1 Thread Simplification

#### 概要
Thread.runnerフィールドを削除し、Threadを純粋な会話履歴コンテナとして再定義。同一Thread内で異なるRunner（ClaudeとCodex）を自由に切り替え可能に。

#### データベース変更
```sql
-- threads テーブル from runnerカラム削除
-- Before (v4.1)
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    room_id TEXT NOT NULL,
    name TEXT NOT NULL,
    runner TEXT NOT NULL,  -- ← 削除
    device_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(room_id) REFERENCES rooms(id) ON DELETE CASCADE
);

-- After (v4.2)
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    room_id TEXT NOT NULL,
    name TEXT NOT NULL,
    device_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(room_id) REFERENCES rooms(id) ON DELETE CASCADE
);
```

#### API変更

**POST /rooms/{room_id}/threads - Thread作成**
```json
// v4.1 Request
{
  "name": "新機能開発",
  "runner": "claude"  // ← 削除
}

// v4.2 Request
{
  "name": "新機能開発"
}

// v4.2 Response
{
  "id": "thread-123",
  "room_id": "room-456",
  "name": "新機能開発",
  "device_id": "device-789",
  "created_at": "2025-01-22T10:00:00Z",
  "updated_at": "2025-01-22T10:00:00Z"
  // runner フィールドなし
}
```

**GET /rooms/{room_id}/threads - Thread一覧取得**
```
// v4.1
GET /rooms/{room_id}/threads?runner=claude

// v4.2
GET /rooms/{room_id}/threads
// runnerパラメータ削除、全Thread返却
// クライアント側でフィルタリング実施
```

#### iOS実装変更

**Thread.swift**
```swift
// v4.1
struct Thread: Codable {
    let id: String
    let roomId: String
    let name: String
    let runner: String  // ← 削除
    let deviceId: String
    let createdAt: Date
    let updatedAt: Date
}

// v4.2
struct Thread: Codable {
    let id: String
    let roomId: String
    let name: String
    let deviceId: String
    let createdAt: Date
    let updatedAt: Date
}
```

**MessageStore.swift - 3次元キー対応**
```swift
// v4.1: 2次元キー
struct Context: Hashable {
    let roomId: String
    let runner: String
}

// v4.2: 3次元キー
struct Context: Hashable {
    let roomId: String
    let runner: String
    let threadId: String  // ← 追加
}
```

#### 期待される効果
- ✅ 同一Thread内でClaudeとCodexを自由に切替
- ✅ Threadは会話履歴のみを保持、Runnerは各Jobで独立指定
- ✅ iOS実装がシンプル化（updateRunner()で完結）
- ✅ 4次元履歴管理達成: `(device_id, room_id, runner, thread_id)`

---

### 15.2 iOS SSE修正

#### 問題
1. **メインスレッドブロッキング**: URLSession delegateがbackground threadで実行され、DispatchQueue.main.asyncでデッドロック発生
2. **推論中入力フリーズ**: isLoading=trueが推論完了まで継続、入力フィールド無効化
3. **メモリリーク**: SSE接続がJob完了後もクリーンアップされず蓄積

#### 修正内容

**SSEManager.swift - URLSession delegateQueue修正**
```swift
// Before
session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
// → デリゲートはbackground threadで実行

// After
session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
// → デリゲートはmain threadで直接実行
```

**ChatViewModel.swift - isLoading管理修正**
```swift
// Job作成成功後、すぐに入力フィールドを有効化（推論中でも入力可能にする）
isLoading = false
print("DEBUG: sendMessage() - isLoading set to false after job creation")
```

**ChatViewModel.swift - SSEクリーンアップ追加**
```swift
// 完了ステータス受信時、最終結果を取得してからSSE接続をクリーンアップ
if isTerminalStatus, let jobId = message.jobId {
    Task { @MainActor in
        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
        self.cleanupConnection(for: jobId)
    }
}
```

#### 修正結果
- ✅ 推論中も画面レスポンシブ
- ✅ 推論中テキスト入力可能
- ✅ Claude/Codex応答が正常表示
- ✅ メモリ警告・クラッシュなし

---

### 15.3 Codex 0.63.0互換性対応

#### 問題
Codex 0.63.0が`reasoning_effort: extra-high`を認識せず、`xhigh`への変更が必要。

#### 修正内容

**cli_builder.py - reasoning_effort mapping**
```python
if "reasoning_effort" in cfg:
    effort = cfg["reasoning_effort"]
    # Codex 0.63.0+ supports: none, minimal, low, medium, high, xhigh
    # Map extra-high to xhigh for compatibility
    if effort == "extra-high":
        effort = "xhigh"
    cmd.extend(["-c", f"model_reasoning_effort={effort}"])
```

**RoomSettingsView.swift - 条件付きオプション表示**
```swift
private var reasoningEffortOptions: [String] {
    // gpt-5.1-codex-max のみ extra-high をサポート
    if viewModel.settings.codex.model == "gpt-5.1-codex-max" {
        return ["low", "medium", "high", "extra-high"]
    } else {
        return ["low", "medium", "high"]
    }
}
```

#### 修正結果
- ✅ Codex 0.63.0でextra-high設定時にxhighへ自動変換
- ✅ gpt-5.1-codex-maxのみUIでextra-highを選択可能
- ✅ 他モデルではextra-highを非表示

---

## 16. v4.5 変更点詳細（2025-12-03）

### 16.1 AIプロバイダー設定機能

#### 概要
サーバー設定画面にAIプロバイダー（Claude Code, Codex, Gemini）の選択・設定機能を追加。ユーザーがプロバイダーの有効化/無効化、表示順序の変更、Gemini用のBashパス設定を行えるようになった。

#### 新規ファイル

**AIProvider.swift**
```swift
/// AIプロバイダー定義
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }
    var displayName: String { ... }
    var systemImage: String { ... }
    var defaultBashCommand: String? { ... }
}

/// AIプロバイダー個別設定
struct AIProviderConfiguration: Codable, Identifiable, Equatable, Hashable {
    let provider: AIProvider
    var isEnabled: Bool
    var bashPath: String?  // カスタムBashパス（Gemini用など）
    var sortOrder: Int
}
```

#### ServerConfiguration拡張

```swift
struct ServerConfiguration {
    // 既存プロパティ...
    var aiProviders: [AIProviderConfiguration]

    /// 有効なAIプロバイダーをソート順で取得
    var enabledAIProviders: [AIProviderConfiguration]

    /// 指定プロバイダーのBashパスを取得
    func bashPath(for provider: AIProvider) -> String?
}
```

#### UI実装

**サーバー設定画面（ServerSettingsView.swift）**
- AI設定セクションを追加
- プロバイダーごとの有効化トグル
- ドラッグ＆ドロップによる表示順序変更（EditButton連携）
- Gemini有効時のBashパス入力フィールド

**チャット画面（RoomDetailView.swift）**
- RunnerTab enumを削除、AIProviderを直接使用
- enabledProvidersから動的にタブを生成
- 設定された順序でタブを表示

#### データ永続化

AIプロバイダー設定はServerConfiguration内に含まれ、既存の永続化機構（UserDefaults + Keychain）で保存される。

```json
{
  "ai_providers": [
    {"provider": "claude", "is_enabled": true, "bash_path": "claude", "sort_order": 0},
    {"provider": "gemini", "is_enabled": true, "bash_path": "/usr/local/bin/gemini", "sort_order": 1},
    {"provider": "codex", "is_enabled": false, "bash_path": "codex", "sort_order": 2}
  ]
}
```

#### 後方互換性

- `aiProviders`が空または未設定の場合、デフォルト設定（Claude/Codex有効、Gemini無効）を自動生成
- 既存のclaude/codex runner指定はそのまま動作

#### 期待される効果
- ✅ Claude Code / Codex / Geminiの3種類のAIプロバイダーをサポート
- ✅ プロバイダーごとの有効化/無効化設定
- ✅ ドラッグによる表示順序のカスタマイズ
- ✅ Gemini用のBashパス設定（カスタムインストールパス対応）
- ✅ チャット画面のタブが設定順序を反映

### 16.2 メモリリーク対策

#### 概要
長時間使用時にOSによるアプリ強制終了（メモリ不足）が発生していた問題を解決。ビュープール機構とパースキャッシュを導入し、メモリ使用量を大幅に削減。

#### 問題の原因
1. **UITextView/CodeBlockViewの過剰生成** - セルが再利用されるたびに新規ビューを生成
2. **NSAttributedStringの重複パース** - 同じメッセージを何度もMarkdownパース
3. **MemoryPressureMonitorの設計問題** - 最初のViewModelのコールバックのみ保持

#### 修正内容

**1. ParsedMessageCache（新規追加）**

```swift
/// パース済みメッセージのキャッシュ（NSCacheで自動メモリ管理）
final class ParsedMessageCache {
    static let shared = ParsedMessageCache()
    private let cache = NSCache<NSString, ParsedMessageEntry>()

    init() {
        cache.countLimit = 50        // 最大50件
        cache.totalCostLimit = 10 * 1024 * 1024  // 10MB上限
    }

    func get(for messageId: String, contentHash: Int) -> [MessageContentSegment]?
    func set(_ segments: [MessageContentSegment], for messageId: String, contentHash: Int)
    func clear()
}
```

**2. ChatMessageCellビュープール**

```swift
final class ChatMessageCell: UITableViewCell {
    // ビュープール（再利用可能なビューを保持）
    private var reusableTextViews: [UITextView] = []
    private var reusableCodeBlockViews: [CodeBlockView] = []
    private static let maxPoolSize = 5

    /// プールからビューを取得または新規作成
    private func dequeueTextView(with attributedString: NSAttributedString, isUser: Bool) -> UITextView
    private func dequeueCodeBlockView(code: String, language: String?) -> CodeBlockView

    /// ビューをプールに回収
    private func recycleViewsToPool()
}
```

**3. MemoryPressureMonitor改善**

```swift
final class MemoryPressureMonitor {
    // 複数コールバック対応
    private var warningCallbacks: [() -> Void] = []
    private var criticalCallbacks: [() -> Void] = []
    private let lock = NSLock()

    func start(onWarning: @escaping () -> Void, onCritical: @escaping () -> Void) {
        // 既存コールバックに追加（複数ViewModelから登録可能）
        warningCallbacks.append(onWarning)
        criticalCallbacks.append(onCritical)
        // ...
        // メモリ警告時にParsedMessageCacheを自動クリア
        ParsedMessageCache.shared.clear()
    }
}
```

**4. ChatViewModel修正**

```swift
// 静的フラグを削除（各ViewModelが独自にコールバック登録）
// Before: private static var memoryMonitorStarted = false
// After: （削除）
```

#### 修正ファイル
- `iOS_WatchOS/RemotePrompt/RemotePrompt/UIKit/ChatListRepresentable.swift`
- `iOS_WatchOS/RemotePrompt/RemotePrompt/Support/MemoryPressureMonitor.swift`
- `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ChatViewModel.swift`

#### 期待される効果
- ✅ UITextView/CodeBlockViewの生成削減（プールから再利用）
- ✅ NSAttributedStringパース回数削減（キャッシュヒット）
- ✅ メモリ警告時の自動クリーンアップ
- ✅ 長時間使用時のメモリ蓄積防止
- ✅ OS killによるアプリ強制終了の防止

---

**End of Document**
