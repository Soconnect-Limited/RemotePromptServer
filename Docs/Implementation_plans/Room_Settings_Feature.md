# ルームごとのCLI設定機能 実装計画

**バージョン**: v1.0
**作成日**: 2025-11-20
**対象**: RemotePrompt iOS/watchOS アプリケーション
**要件**: ルームごとにClaude Code及びCodexのCLI設定（モデル、パーミッション、ツール等）を管理可能にする

---

## 目次

1. [概要](#概要)
2. [要件定義](#要件定義)
3. [設計仕様](#設計仕様)
4. [実装フェーズ](#実装フェーズ)
5. [リスク管理](#リスク管理)
6. [テスト計画](#テスト計画)
7. [完了条件](#完了条件)

---

## 概要

### 背景

現在、RemotePromptではルームごとにworkspace_pathやAIタイプ（Claude/Codex）を設定できるが、CLIレベルの詳細設定（モデル選択、パーミッションモード、ツール有効/無効等）はサーバー側で固定されている。

Codexには以下の設定オプションがある：
- モード選択: Agent (full access) / Chat
- モデル選択: GPT-4 / GPT-3.5等
- Reasoning effort選択

Claude Codeにも以下のオプションがある：
- `--model`: sonnet / opus
- `--permission-mode`: default / ask / deny
- `--tools`: 特定ツールの有効/無効

これらをルームごとに設定可能にすることで、用途に応じた柔軟なAI操作環境を実現する。

### 目標

- ルームごとにClaude Code及びCodexのCLI設定を保存・管理
- iOS/watchOS UIで設定を編集可能
- サーバー側でCLI実行時に設定を反映
- 既存機能（チャット、ファイルブラウザ等）への影響を最小化

---

## 要件定義

### 機能要件

#### FR-1: DB Schema拡張
- `rooms`テーブルに`settings` TEXT列を追加（JSON形式）
- NULLの場合はデフォルト設定を適用

#### FR-2: 設定データ構造
```json
{
  "claude": {
    "model": "sonnet",
    "permission_mode": "default",
    "tools": ["Bash", "Edit", "Read", "Write", "Grep", "Glob"],
    "custom_flags": []
  },
  "codex": {
    "model": "gpt-4",
    "sandbox": "workspace-write",
    "approval_policy": "on-failure",
    "enable_search": false,
    "custom_flags": []
  }
}
```

#### FR-3: REST API
- `GET /rooms/{room_id}/settings?device_id={device_id}`: 設定取得
- `PUT /rooms/{room_id}/settings?device_id={device_id}`: 設定更新
- 認証: 既存のdevice_id認証を使用
- 認可: room所有権チェック（device_sessions経由）

#### FR-4: iOS/watchOS UI
- ルーム詳細画面に「設定」ボタンを追加
- 設定画面でAIタイプ別に以下を表示/編集:
  - **Claude Code**:
    - Model選択: Sonnet / Opus
    - Permission Mode: Default / Ask / Deny
    - Tools: チェックボックスリスト（Bash, Edit, Read, Write, Grep, Glob等）
    - Custom Flags: テキストフィールド（カンマ区切り）
  - **Codex**:
    - Model選択: GPT-4 / GPT-3.5 / GPT-4 Turbo等
    - Sandbox: workspace-write / workspace-read / isolated等
    - Approval Policy: on-failure / always / never
    - Web Search: トグルスイッチ
    - Custom Flags: テキストフィールド（カンマ区切り）

#### FR-5: サーバー側CLI実行
- job作成時に`rooms.settings`から設定を読み込み
- CLIコマンドラインに設定を反映:
  - Claude Code: `claude --model sonnet --permission-mode default --tools Bash,Edit ...`
  - Codex: `codex -m gpt-4 -s workspace-write -a on-failure --search ...`
- 設定がNULLの場合はデフォルト動作

### 非機能要件

#### NFR-1: パフォーマンス
- 設定取得APIレスポンス: 200ms以内
- 設定更新APIレスポンス: 500ms以内

#### NFR-2: セキュリティ
- 設定JSONのバリデーション（許可されたモデル名・フラグのみ）
- 悪意あるcustom_flagsの検証（コマンドインジェクション対策）
- device_id認証 + room所有権チェック

#### NFR-3: 互換性
- iOS 18.0以降
- watchOS 10.0以降
- 既存roomsテーブルへの後方互換性（settings列がNULLでも動作）

---

## 設計仕様

### データベーススキーマ変更

#### rooms テーブル拡張

```sql
-- 既存テーブルに列追加
ALTER TABLE rooms ADD COLUMN settings TEXT DEFAULT NULL;

-- settings列のフォーマット例（JSON文字列）
-- {
--   "claude": {...},
--   "codex": {...}
-- }
```

**制約**:
- TEXT型（JSON文字列として保存）
- NULL許可（デフォルト設定を使用）
- 最大サイズ: 10KB（巨大な設定を防ぐ）

### REST API仕様

#### GET /rooms/{room_id}/settings

**リクエスト**:
```
GET /rooms/{room_id}/settings?device_id={device_id}
```

**レスポンス** (200 OK):
```json
{
  "room_id": "room-123",
  "settings": {
    "claude": {
      "model": "sonnet",
      "permission_mode": "default",
      "tools": ["Bash", "Edit", "Read"],
      "custom_flags": []
    },
    "codex": {
      "model": "gpt-4",
      "sandbox": "workspace-write",
      "approval_policy": "on-failure",
      "enable_search": false,
      "custom_flags": []
    }
  }
}
```

**設定がNULLの場合**:
```json
{
  "room_id": "room-123",
  "settings": null
}
```

**エラーレスポンス**:
| コード | 条件 | レスポンス |
|--------|------|------------|
| 401 | device_id不正 | `{"error": "Unauthorized", "message": "Invalid device_id"}` |
| 403 | room所有権なし | `{"error": "Forbidden", "message": "No ownership of this room"}` |
| 404 | room_id不在 | `{"error": "Not Found", "message": "Room not found"}` |
| 500 | サーバーエラー | `{"error": "Internal Server Error", "message": "..."}` |

#### PUT /rooms/{room_id}/settings

**リクエスト**:
```
PUT /rooms/{room_id}/settings?device_id={device_id}
Content-Type: application/json

{
  "claude": {
    "model": "opus",
    "permission_mode": "ask",
    "tools": ["Bash", "Edit"],
    "custom_flags": ["--verbose"]
  },
  "codex": {
    "model": "gpt-4-turbo",
    "sandbox": "isolated",
    "approval_policy": "always",
    "enable_search": true,
    "custom_flags": []
  }
}
```

**レスポンス** (200 OK):
```json
{
  "room_id": "room-123",
  "settings": {
    "claude": {...},
    "codex": {...}
  }
}
```

**バリデーションエラー** (400 Bad Request):
```json
{
  "error": "Bad Request",
  "message": "Invalid model name: gpt-10",
  "field": "codex.model"
}
```

**エラーレスポンス**: GET /settingsと同様（401/403/404/500）

### バリデーション仕様

#### 許可値リスト

```python
ALLOWED_VALUES = {
    "claude": {
        "model": ["sonnet", "opus", "haiku"],
        "permission_mode": ["default", "ask", "deny"],
        "tools": [
            "Bash", "Edit", "Read", "Write", "Grep", "Glob",
            "Task", "WebFetch", "WebSearch", "NotebookEdit",
            "TodoWrite", "SlashCommand", "Skill"
        ],
    },
    "codex": {
        "model": ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "o1-preview", "o1-mini"],
        "sandbox": ["workspace-write", "workspace-read", "isolated", "full-access"],
        "approval_policy": ["on-failure", "always", "never"],
    }
}
```

#### custom_flags検証

- 最大10個まで
- 各フラグは`--`または`-`で始まる
- 危険なフラグ（`--exec`, `--eval`, `--unsafe`等）は拒否
- 最大長: 各フラグ100文字

```python
DANGEROUS_FLAGS = [
    "--exec", "--eval", "--unsafe", "--allow-root",
    "--disable-sandbox", "--no-verify"
]

def validate_custom_flags(flags: list[str]) -> None:
    if len(flags) > 10:
        raise ValueError("Too many custom flags (max 10)")

    for flag in flags:
        if not flag.startswith("-"):
            raise ValueError(f"Invalid flag format: {flag}")
        if len(flag) > 100:
            raise ValueError(f"Flag too long: {flag}")
        if any(dangerous in flag.lower() for dangerous in DANGEROUS_FLAGS):
            raise ValueError(f"Dangerous flag detected: {flag}")
```

### CLI実行時の設定反映

#### Claude Code

```python
def build_claude_command(prompt: str, settings: dict | None) -> list[str]:
    """Claude Code CLIコマンドを構築"""
    cmd = ["claude", "--print"]

    if settings and "claude" in settings:
        cfg = settings["claude"]

        # Model
        if "model" in cfg:
            cmd.extend(["--model", cfg["model"]])

        # Permission mode
        if "permission_mode" in cfg:
            cmd.extend(["--permission-mode", cfg["permission_mode"]])

        # Tools
        if "tools" in cfg and cfg["tools"]:
            tools = ",".join(cfg["tools"])
            cmd.extend(["--tools", tools])

        # Custom flags
        if "custom_flags" in cfg:
            cmd.extend(cfg["custom_flags"])

    return cmd
```

#### Codex

```python
def build_codex_command(prompt: str, settings: dict | None) -> list[str]:
    """Codex CLIコマンドを構築"""
    cmd = ["codex"]

    if settings and "codex" in settings:
        cfg = settings["codex"]

        # Model
        if "model" in cfg:
            cmd.extend(["-m", cfg["model"]])

        # Sandbox
        if "sandbox" in cfg:
            cmd.extend(["-s", cfg["sandbox"]])

        # Approval policy
        if "approval_policy" in cfg:
            cmd.extend(["-a", cfg["approval_policy"]])

        # Web search
        if cfg.get("enable_search", False):
            cmd.append("--search")

        # Custom flags
        if "custom_flags" in cfg:
            cmd.extend(cfg["custom_flags"])

    return cmd
```

### iOS/watchOS データモデル

#### RoomSettings

```swift
struct RoomSettings: Codable, Equatable {
    var claude: ClaudeSettings
    var codex: CodexSettings

    static var `default`: RoomSettings {
        RoomSettings(
            claude: ClaudeSettings.default,
            codex: CodexSettings.default
        )
    }
}

struct ClaudeSettings: Codable, Equatable {
    var model: String
    var permissionMode: String
    var tools: [String]
    var customFlags: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case permissionMode = "permission_mode"
        case tools
        case customFlags = "custom_flags"
    }

    static var `default`: ClaudeSettings {
        ClaudeSettings(
            model: "sonnet",
            permissionMode: "default",
            tools: ["Bash", "Edit", "Read", "Write", "Grep", "Glob"],
            customFlags: []
        )
    }
}

struct CodexSettings: Codable, Equatable {
    var model: String
    var sandbox: String
    var approvalPolicy: String
    var enableSearch: Bool
    var customFlags: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case sandbox
        case approvalPolicy = "approval_policy"
        case enableSearch = "enable_search"
        case customFlags = "custom_flags"
    }

    static var `default`: CodexSettings {
        CodexSettings(
            model: "gpt-4",
            sandbox: "workspace-write",
            approvalPolicy: "on-failure",
            enableSearch: false,
            customFlags: []
        )
    }
}
```

#### API Request/Response

```swift
struct GetSettingsResponse: Codable {
    let roomId: String
    let settings: RoomSettings?

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case settings
    }
}

struct UpdateSettingsRequest: Codable {
    let claude: ClaudeSettings
    let codex: CodexSettings
}
```

### セキュリティ仕様

#### 1. 認証・認可

- **認証**: 既存のdevice_id認証を使用
- **認可**: device_sessions経由でroom所有権をチェック
```python
def check_room_ownership(device_id: str, room_id: str) -> bool:
    """device_idがroom_idを所有しているか確認"""
    session = db.query(DeviceSession).filter_by(
        device_id=device_id,
        room_id=room_id
    ).first()
    return session is not None
```

#### 2. 入力バリデーション

- **設定JSONサイズ制限**: 10KB以内
- **許可値チェック**: `ALLOWED_VALUES`リスト照合
- **custom_flags検証**: 危険フラグ拒否、長さ制限

#### 3. コマンドインジェクション対策

- `subprocess.run()`で引数リストとして渡す（文字列結合しない）
```python
# ❌ 危険な例
os.system(f"claude {prompt} {custom_flag}")

# ✅ 安全な例
subprocess.run(["claude", "--print", "--model", model, custom_flag], ...)
```

- シェルメタ文字（`;`, `|`, `&`, `$()`, `` ` ``等）を含むフラグは拒否

#### 4. JSONインジェクション対策

- `json.loads()`でパース後、スキーマバリデーション
- 想定外のキーは無視（ホワイトリスト方式）

---

## 実装フェーズ

### Phase 1: サーバー側基盤 (8-10時間)

#### 1.1 DBスキーマ変更
- [ ] マイグレーションスクリプト作成（`ALTER TABLE rooms ADD COLUMN settings TEXT`）
- [ ] 開発環境でマイグレーション実行・動作確認
- [ ] ロールバックスクリプト作成

#### 1.2 バリデーションロジック
- [ ] `ALLOWED_VALUES`定義
- [ ] `DANGEROUS_FLAGS`定義
- [ ] `validate_settings(settings: dict) -> None`関数実装
  - [ ] model名検証
  - [ ] permission_mode/sandbox等の値検証
  - [ ] tools配列検証
  - [ ] custom_flags検証（危険フラグ、長さ、個数）
  - [ ] JSONサイズ検証（10KB以内）
- [ ] ユニットテスト作成（正常系・異常系各10ケース以上）

#### 1.3 REST API実装
- [ ] `GET /rooms/{room_id}/settings`エンドポイント
  - [ ] device_id認証
  - [ ] room所有権チェック
  - [ ] settings列読み取り（NULL時はnull返却）
  - [ ] JSONレスポンス返却
- [ ] `PUT /rooms/{room_id}/settings`エンドポイント
  - [ ] device_id認証
  - [ ] room所有権チェック
  - [ ] リクエストボディパース
  - [ ] バリデーション実行
  - [ ] settings列更新
  - [ ] JSONレスポンス返却
- [ ] エラーハンドリング（401/403/404/400/500）
- [ ] API統合テスト作成

#### 1.4 CLI実行ロジック変更
- [ ] `build_claude_command(prompt, settings)`実装
- [ ] `build_codex_command(prompt, settings)`実装
- [ ] job作成処理でsettings読み込み・CLI構築
- [ ] 既存機能（settings=NULL）の動作確認

---

### Phase 2: iOS データ層 (4-6時間)

#### 2.1 モデル定義
- [ ] `RoomSettings`構造体
- [ ] `ClaudeSettings`構造体（CodingKeys含む）
- [ ] `CodexSettings`構造体（CodingKeys含む）
- [ ] `GetSettingsResponse`構造体
- [ ] `UpdateSettingsRequest`構造体
- [ ] デフォルト値定義（`.default`）
- [ ] Equatable適合確認

#### 2.2 API Service拡張
- [ ] `APIService`に`getSettings(roomId:deviceId:)`メソッド追加
- [ ] `APIService`に`updateSettings(roomId:deviceId:settings:)`メソッド追加
- [ ] エラーハンドリング（`APIError.unauthorized`, `.forbidden`, `.validationError`等）
- [ ] ユニットテスト（モックレスポンスで動作確認）

#### 2.3 ViewModelロジック
- [ ] `RoomDetailViewModel`に`@Published var settings: RoomSettings?`追加
- [ ] `loadSettings()`メソッド実装
- [ ] `updateSettings(_:)`メソッド実装
- [ ] エラー状態管理（`@Published var settingsError: String?`）

---

### Phase 3: iOS UI実装 (8-12時間)

#### 3.1 設定画面ナビゲーション
- [ ] `RoomDetailView`にToolbarItem「設定」ボタン追加
- [ ] `NavigationLink`で`RoomSettingsView`へ遷移
- [ ] `RoomSettingsView`スケルトン作成

#### 3.2 Claude Settings UI
- [ ] `ClaudeSettingsSection`コンポーネント作成
- [ ] Model選択: `Picker`（Sonnet/Opus/Haiku）
- [ ] Permission Mode選択: `Picker`（Default/Ask/Deny）
- [ ] Tools選択: `List`+`Toggle`（Bash, Edit, Read等）
- [ ] Custom Flags: `TextField`（カンマ区切り入力）
  - [ ] 配列⇔文字列変換ロジック
  - [ ] バリデーション表示（10個以上でエラー）

#### 3.3 Codex Settings UI
- [ ] `CodexSettingsSection`コンポーネント作成
- [ ] Model選択: `Picker`（GPT-4/GPT-4 Turbo/GPT-3.5/o1等）
- [ ] Sandbox選択: `Picker`（workspace-write/read/isolated/full-access）
- [ ] Approval Policy選択: `Picker`（on-failure/always/never）
- [ ] Web Search: `Toggle`
- [ ] Custom Flags: `TextField`（カンマ区切り入力）

#### 3.4 保存・リセット機能
- [ ] Toolbarに「保存」ボタン
  - [ ] `updateSettings()`呼び出し
  - [ ] 成功時トースト表示・画面閉じる
  - [ ] 失敗時エラーアラート表示
- [ ] 「デフォルトに戻す」ボタン
  - [ ] 確認アラート表示
  - [ ] `RoomSettings.default`で上書き・保存

#### 3.5 ローディング・エラー表示
- [ ] 画面表示時`loadSettings()`呼び出し
- [ ] ローディング中`ProgressView`表示
- [ ] エラー時エラーメッセージ+リトライボタン
- [ ] settings=nullの場合デフォルト値で初期化

---

### Phase 4: watchOS対応 (4-6時間)

#### 4.1 watchOS UI調整
- [ ] `RoomSettingsView`をwatchOS向けに簡略化
  - [ ] スクロール可能な`List`ベース
  - [ ] `Picker`を`NavigationLink`→サブ画面に変更
  - [ ] Custom Flagsは省略（iOSのみ）
- [ ] `ClaudeSettingsSection` watchOS版
- [ ] `CodexSettingsSection` watchOS版

#### 4.2 動作確認
- [ ] watchOSシミュレータで設定画面表示
- [ ] 各Picker動作確認
- [ ] 保存→サーバー反映確認
- [ ] iOS↔watchOS間の設定同期確認

---

### Phase 5: テスト (6-8時間)

#### 5.1 サーバー側テスト
- [ ] バリデーション単体テスト（30ケース以上）
  - [ ] 正常系: 全パターンの許可値
  - [ ] 異常系: 不正なmodel名、危険フラグ、長すぎるフラグ等
  - [ ] 境界値: custom_flags 10個/11個、JSON 10KB/10KB+1等
- [ ] API統合テスト（15ケース以上）
  - [ ] GET /settings: 認証成功/失敗、所有権あり/なし、settings有/無
  - [ ] PUT /settings: 更新成功、バリデーションエラー、認証失敗等
- [ ] CLI構築テスト
  - [ ] `build_claude_command()`出力確認
  - [ ] `build_codex_command()`出力確認
  - [ ] settings=NULLの場合のデフォルト動作確認

#### 5.2 iOS/watchOS UI テスト
- [ ] 設定画面表示テスト（iOS/watchOS）
- [ ] 各入力フィールド動作確認
- [ ] 保存→API呼び出し→成功/エラー表示確認
- [ ] デフォルトに戻す→確認アラート→保存確認
- [ ] 長いパス名・エラーメッセージの表示崩れチェック

#### 5.3 E2E テスト
- [ ] iOS→設定変更→保存→job作成→CLI実行→設定反映確認
- [ ] watchOS→設定変更→保存→iOS側で同期確認
- [ ] 複数デバイス→同一room→設定共有確認
- [ ] 既存機能（チャット、ファイルブラウザ）影響なし確認

---

### Phase 6: ドキュメント作成 (2-3時間)

#### 6.1 API仕様書更新
- [ ] `Docs/Specifications/Master_Specification.md`に以下を追記:
  - [ ] rooms.settings列仕様
  - [ ] GET/PUT /settings API仕様
  - [ ] バリデーションルール
  - [ ] CLI構築ロジック

#### 6.2 ユーザー向け説明
- [ ] README.md更新（新機能の説明）
- [ ] 設定画面スクリーンショット追加
- [ ] Custom Flagsの使い方例

#### 6.3 開発者向けドキュメント
- [ ] CLAUDE.md更新（新機能の実装概要）
- [ ] コード内docstring確認・追加

---

## リスク管理

### リスク一覧

| ID | リスク内容 | 影響度 | 対策 |
|----|-----------|-------|------|
| R1 | custom_flagsによるコマンドインジェクション | 高 | 危険フラグブラックリスト、シェルメタ文字拒否、subprocess引数リスト渡し |
| R2 | 巨大なsettings JSONによるDB負荷 | 中 | 10KBサイズ制限、413エラー返却 |
| R3 | 不正なmodel名によるCLI実行失敗 | 中 | 許可値リストでバリデーション、job失敗時エラーログ記録 |
| R4 | 複数デバイスの設定競合 | 低 | Last-Write-Wins方式、楽観的ロック（将来的にversion列追加） |
| R5 | 既存機能への影響（settings=NULL処理） | 中 | フォールバック処理、既存機能の回帰テスト |
| R6 | watchOS画面サイズでUI崩れ | 低 | シンプルなList+NavigationLink構成、実機テスト |

### 対策詳細

#### R1対策: コマンドインジェクション
```python
# 危険フラグのブラックリスト
DANGEROUS_FLAGS = [
    "--exec", "--eval", "--unsafe", "--allow-root",
    "--disable-sandbox", "--no-verify", "--rm", "--delete"
]

# シェルメタ文字のチェック
SHELL_META_CHARS = [";", "|", "&", "$", "`", "(", ")", "<", ">", "\n", "\r"]

def validate_custom_flags(flags: list[str]) -> None:
    for flag in flags:
        # 危険フラグ
        if any(d in flag.lower() for d in DANGEROUS_FLAGS):
            raise ValueError(f"Dangerous flag: {flag}")
        # シェルメタ文字
        if any(c in flag for c in SHELL_META_CHARS):
            raise ValueError(f"Invalid character in flag: {flag}")
```

#### R4対策: 設定競合
**Phase 1実装**: Last-Write-Wins（最後の更新が勝つ）
**Phase 2計画**: 楽観的ロック
```sql
ALTER TABLE rooms ADD COLUMN settings_version INTEGER DEFAULT 1;
```
```python
# PUT時にversionチェック
if current_version != request_version:
    return 409 Conflict
```

---

## テスト計画

### テスト観点表

#### バリデーションテスト

| No | テスト項目 | 入力値 | 期待結果 |
|----|-----------|-------|---------|
| V1 | 正常: Claude model=sonnet | `{"claude": {"model": "sonnet"}}` | 受理 |
| V2 | 正常: Claude model=opus | `{"claude": {"model": "opus"}}` | 受理 |
| V3 | 正常: Codex model=gpt-4 | `{"codex": {"model": "gpt-4"}}` | 受理 |
| V4 | 異常: 不正なmodel名 | `{"claude": {"model": "gpt-10"}}` | 400 Bad Request |
| V5 | 異常: 危険フラグ --exec | `{"claude": {"custom_flags": ["--exec"]}}` | 400 Bad Request |
| V6 | 異常: シェルメタ文字 ; | `{"claude": {"custom_flags": ["--flag;rm -rf"]}}` | 400 Bad Request |
| V7 | 境界値: custom_flags 10個 | `{"custom_flags": ["--a", ..., "--j"]}` (10個) | 受理 |
| V8 | 境界値: custom_flags 11個 | `{"custom_flags": ["--a", ..., "--k"]}` (11個) | 400 Bad Request |
| V9 | 境界値: JSON 10KB | 10240バイトのJSON | 受理 |
| V10 | 境界値: JSON 10KB+1 | 10241バイトのJSON | 400 Bad Request |
| V11 | 異常: 不正なpermission_mode | `{"claude": {"permission_mode": "hoge"}}` | 400 Bad Request |
| V12 | 異常: 不正なtools名 | `{"claude": {"tools": ["UnknownTool"]}}` | 400 Bad Request |
| V13 | 正常: tools空配列 | `{"claude": {"tools": []}}` | 受理 |
| V14 | 異常: custom_flag長すぎる | `{"custom_flags": ["--" + "a"*200]}` (101文字) | 400 Bad Request |
| V15 | 正常: settings=null | `PUT /settings` with `null` body | settings列をNULLに更新 |

#### API認証・認可テスト

| No | テスト項目 | device_id | room所有権 | 期待結果 |
|----|-----------|-----------|-----------|---------|
| A1 | 認証成功・所有権あり | 正常 | あり | 200 OK |
| A2 | 認証失敗 | 不正 | - | 401 Unauthorized |
| A3 | 認証成功・所有権なし | 正常 | なし | 403 Forbidden |
| A4 | room_id不在 | 正常 | - | 404 Not Found |

#### CLI構築テスト

| No | テスト項目 | 入力settings | 期待CLI |
|----|-----------|-------------|---------|
| C1 | Claude デフォルト | `null` | `["claude", "--print"]` |
| C2 | Claude model=opus | `{"claude": {"model": "opus"}}` | `["claude", "--print", "--model", "opus"]` |
| C3 | Claude permission_mode=ask | `{"claude": {"permission_mode": "ask"}}` | `["claude", "--print", "--permission-mode", "ask"]` |
| C4 | Claude tools指定 | `{"claude": {"tools": ["Bash", "Edit"]}}` | `["claude", "--print", "--tools", "Bash,Edit"]` |
| C5 | Claude custom_flags | `{"claude": {"custom_flags": ["--verbose"]}}` | `["claude", "--print", "--verbose"]` |
| C6 | Codex デフォルト | `null` | `["codex"]` |
| C7 | Codex model=gpt-4-turbo | `{"codex": {"model": "gpt-4-turbo"}}` | `["codex", "-m", "gpt-4-turbo"]` |
| C8 | Codex sandbox=isolated | `{"codex": {"sandbox": "isolated"}}` | `["codex", "-s", "isolated"]` |
| C9 | Codex enable_search=true | `{"codex": {"enable_search": true}}` | `["codex", "--search"]` |
| C10 | Codex 複合 | model+sandbox+search | `["codex", "-m", "gpt-4", "-s", "isolated", "--search"]` |

#### UI動作テスト

| No | テスト項目 | 操作 | 期待結果 |
|----|-----------|-----|---------|
| U1 | 設定画面表示 | RoomDetailViewで「設定」タップ | RoomSettingsView表示、設定読み込み |
| U2 | Model変更 | Picker操作 | ローカル状態更新 |
| U3 | Tools変更 | Toggleタップ | ローカル配列更新 |
| U4 | Custom Flags入力 | TextField入力 | カンマ区切りで配列変換 |
| U5 | 保存成功 | 「保存」タップ | API呼び出し→成功トースト→画面閉じる |
| U6 | 保存失敗 | バリデーションエラー | エラーアラート表示 |
| U7 | デフォルトに戻す | ボタンタップ→確認 | デフォルト値で更新→保存 |
| U8 | ローディング表示 | 画面表示時 | ProgressView表示→データ取得後消える |
| U9 | エラー表示 | API失敗時 | エラーメッセージ+リトライボタン |
| U10 | watchOS簡略UI | watchOS設定画面表示 | NavigationLink形式Picker、Custom Flagsなし |

---

## 完了条件

### 必須条件

- [ ] 全実装フェーズ完了（Phase 1-6）
- [ ] 全テストケース合格（バリデーション15件、API 4件、CLI 10件、UI 10件）
- [ ] E2Eテスト成功（iOS/watchOS→サーバー→CLI実行→設定反映）
- [ ] 既存機能の回帰テストパス（チャット、ファイルブラウザ等）
- [ ] Master_Specification.md更新完了
- [ ] コードレビュー承認

### 推奨条件

- [ ] パフォーマンステスト（設定API 200ms/500ms以内）
- [ ] セキュリティレビュー（コマンドインジェクション対策確認）
- [ ] ユーザビリティテスト（設定画面の使いやすさ確認）

---

## 見積もり

### 工数見積もり

| フェーズ | 工数 |
|---------|------|
| Phase 1: サーバー側基盤 | 8-10時間 |
| Phase 2: iOS データ層 | 4-6時間 |
| Phase 3: iOS UI実装 | 8-12時間 |
| Phase 4: watchOS対応 | 4-6時間 |
| Phase 5: テスト | 6-8時間 |
| Phase 6: ドキュメント | 2-3時間 |
| **合計** | **32-45時間** |

### スケジュール例（1日8時間作業）

- Day 1-2: Phase 1 (サーバー側基盤)
- Day 3: Phase 2 (iOS データ層)
- Day 4-5: Phase 3 (iOS UI実装)
- Day 6: Phase 4 (watchOS対応) + Phase 5 (テスト開始)
- Day 7: Phase 5 (テスト完了) + Phase 6 (ドキュメント)

**総期間**: 約7営業日（1.5週間）

---

## 参考情報

### Claude Code CLI オプション

```
claude --help
  --model [sonnet|opus|haiku]
  --permission-mode [default|ask|deny]
  --tools [comma-separated list]
```

### Codex CLI オプション

```
codex --help
  -m, --model [gpt-4|gpt-4-turbo|gpt-3.5-turbo|o1-preview|o1-mini]
  -s, --sandbox [workspace-write|workspace-read|isolated|full-access]
  -a, --ask-for-approval [on-failure|always|never]
  --search (enable web search)
```

### 関連ドキュメント

- [Master_Specification.md](../Specifications/Master_Specification.md) - システム全体仕様
- [File_Browser_and_Markdown_Editor.md](./File_Browser_and_Markdown_Editor.md) - ファイルブラウザ実装計画（セキュリティ参考）

---

**実装計画 v1.0 完成**
**次のステップ**: ユーザーレビュー → 修正 → Phase 1実装開始
