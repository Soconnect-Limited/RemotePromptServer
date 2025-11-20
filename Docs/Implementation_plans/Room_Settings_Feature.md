# ルームごとのCLI設定機能 実装計画

**バージョン**: v1.6（値表記統一・テスト整備版）
**作成日**: 2025-11-20
**更新日**: 2025-11-20
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
- モデル選択: GPT-5.1 / GPT-5.1-Codex / GPT-5.1-Codex-Mini / GPT-5.1-Codex-Max等
- Reasoning Effort選択: low / medium / high / extra-high

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
    "model": "gpt-5.1-codex",
    "sandbox": "workspace-write",
    "approval_policy": "on-failure",
    "reasoning_effort": "medium",
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
    - Model選択: GPT-5.1 / GPT-5.1-Codex / GPT-5.1-Codex-Mini / GPT-5.1-Codex-Max
    - Sandbox: read-only / workspace-write / danger-full-access
    - Approval Policy: untrusted / on-failure / on-request / never
    - Reasoning Effort: low / medium / high / extra-high (Picker選択肢、そのまま送信)
    - Custom Flags: テキストフィールド（カンマ区切り）

#### FR-5: サーバー側CLI実行
- job作成時に`rooms.settings`から設定を読み込み
- CLIコマンドラインに設定を反映:
  - Claude Code: `claude --model sonnet --permission-mode default --tools Bash,Edit ...`
  - Codex: `codex -m gpt-5.1-codex -s workspace-write -a on-failure ...`
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
      "model": "gpt-5.1-codex",
      "sandbox": "workspace-write",
      "approval_policy": "on-failure",
      "reasoning_effort": "medium",
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

**注意**: `settings: null`の場合、クライアントはデフォルト設定を使用する。

**エラーレスポンス**:
| コード | 条件 | レスポンス |
|--------|------|------------|
| 401 | device_id不正 | `{"error": "Unauthorized", "message": "Invalid device_id"}` |
| 403 | room所有権なし | `{"error": "Forbidden", "message": "No ownership of this room"}` |
| 404 | room_id不在 | `{"error": "Not Found", "message": "Room not found"}` |
| 413 | JSONサイズ超過 | `{"error": "Payload Too Large", "message": "Settings JSON exceeds 10KB limit"}` |
| 500 | サーバーエラー | `{"error": "Internal Server Error", "message": "..."}` |

#### PUT /rooms/{room_id}/settings

**リクエスト例1（設定更新）**:
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
    "model": "gpt-5.1-codex-max",
    "sandbox": "workspace-write",
    "approval_policy": "untrusted",
    "reasoning_effort": "high",
    "custom_flags": []
  }
}
```

**リクエスト例2（デフォルトにリセット）**:
```
PUT /rooms/{room_id}/settings?device_id={device_id}
Content-Type: application/json

null
```
**注意**: `null`をボディに送信すると、`settings`列がNULLに更新され、デフォルト設定が適用される。

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

**エラーレスポンス**: GET /settingsと同様（401/403/404/413/500）

**サイズ制限の実装**:
```python
@app.put("/rooms/{room_id}/settings")
async def update_settings(room_id: str, request: Request, device_id: str = Query(...)):
    # リクエストボディサイズチェック（10KB制限）
    body = await request.body()
    if len(body) > 10_240:  # 10KB
        raise HTTPException(413, detail="Settings JSON exceeds 10KB limit")

    # 以下、既存処理（パース、バリデーション、DB更新）
    ...
```

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
        "model": ["gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-codex-max"],
        "sandbox": ["read-only", "workspace-write", "danger-full-access"],
        "approval_policy": ["untrusted", "on-failure", "on-request", "never"],
        "reasoning_effort": ["low", "medium", "high", "extra-high"],
    }
}
```

#### custom_flags検証

- 最大10個まで
- 各フラグは`--`または`-`で始まる
- **予約オプション（設定済みパラメータ）は禁止**: `--model`, `--tools`, `-s`, `-a`等を`custom_flags`に含めると、設定を迂回できてしまう
- 危険なフラグ（`--exec`, `--eval`, `--unsafe`等）は拒否
- シェルメタ文字（`;`, `|`, `&`, `$`等）を含むフラグは拒否
- 最大長: 各フラグ100文字

```python
# 予約済みオプション（custom_flagsで指定不可）
RESERVED_FLAGS = {
    "claude": ["--model", "--permission-mode", "--tools"],
    "codex": ["-m", "--model", "-s", "--sandbox", "-a", "--ask-for-approval", "-r", "--reasoning-effort"]
}

DANGEROUS_FLAGS = [
    "--exec", "--eval", "--unsafe", "--allow-root",
    "--disable-sandbox", "--no-verify", "--rm", "--delete"
]

SHELL_META_CHARS = [";", "|", "&", "$", "`", "(", ")", "<", ">", "\n", "\r"]

def validate_custom_flags(flags: list[str], ai_type: str) -> None:
    """
    custom_flagsのバリデーション

    Args:
        flags: カスタムフラグのリスト
        ai_type: "claude" または "codex"

    Raises:
        ValueError: バリデーションエラー
    """
    if len(flags) > 10:
        raise ValueError("Too many custom flags (max 10)")

    reserved = RESERVED_FLAGS.get(ai_type, [])

    for flag in flags:
        # 形式チェック
        if not flag.startswith("-"):
            raise ValueError(f"Invalid flag format: {flag}")

        # 長さチェック
        if len(flag) > 100:
            raise ValueError(f"Flag too long: {flag}")

        # フラグ名部分を抽出（値部分を除外）
        # 例: "--model=opus" → "--model", "-s workspace-write" → "-s"
        flag_name = flag.split("=")[0].split()[0]

        # 予約オプションチェック
        if flag_name in reserved:
            raise ValueError(
                f"Reserved flag cannot be used in custom_flags: {flag_name}. "
                f"Use the dedicated setting field instead."
            )

        # 危険フラグチェック
        if any(dangerous in flag.lower() for dangerous in DANGEROUS_FLAGS):
            raise ValueError(f"Dangerous flag detected: {flag}")

        # シェルメタ文字チェック
        if any(char in flag for char in SHELL_META_CHARS):
            raise ValueError(f"Invalid character in flag: {flag}")
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

        # Reasoning effort
        if "reasoning_effort" in cfg:
            cmd.extend(["-r", cfg["reasoning_effort"]])

        # Custom flags（予約オプションは既にバリデーションで排除済み）
        if "custom_flags" in cfg:
            cmd.extend(cfg["custom_flags"])

    return cmd
```

**注意**: `enable_search`フィールドは削除されました。Web search機能が必要な場合は`custom_flags`に`["--search"]`を追加してください（ただし、Codex CLIで`--search`が実際に存在するか要確認）。

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
    var reasoningEffort: String
    var customFlags: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case sandbox
        case approvalPolicy = "approval_policy"
        case reasoningEffort = "reasoning_effort"
        case customFlags = "custom_flags"
    }

    static var `default`: CodexSettings {
        CodexSettings(
            model: "gpt-5.1-codex",
            sandbox: "workspace-write",
            approvalPolicy: "on-failure",
            reasoningEffort: "medium",
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
- [x] マイグレーションスクリプト作成（`ALTER TABLE rooms ADD COLUMN settings TEXT`）
- [x] 開発環境でマイグレーション実行・動作確認
- [x] ロールバックスクリプト作成

#### 1.2 バリデーションロジック
- [x] `ALLOWED_VALUES`定義
- [x] `RESERVED_FLAGS`定義（予約オプション）
- [x] `DANGEROUS_FLAGS`定義
- [x] `SHELL_META_CHARS`定義
- [x] `validate_settings(settings: dict | None) -> None`関数実装
  - [x] **settings=Noneの場合は即座にreturn（デフォルト設定を使用）**
  - [x] model名検証（ALLOWED_VALUESリスト照合）
  - [x] permission_mode/sandbox/approval_policy/reasoning_effort等の値検証
  - [x] tools配列検証（ALLOWED_VALUESリスト照合）
  - [x] custom_flags検証:
    - [x] 予約オプション拒否（`validate_custom_flags(flags, ai_type)`）
    - [x] 危険フラグ拒否
    - [x] シェルメタ文字拒否
    - [x] 長さ・個数制限
- [x] ユニットテスト作成（**24ケース、上記V1-V24に対応**）

#### 1.3 REST API実装
- [x] `GET /rooms/{room_id}/settings`エンドポイント
  - [x] device_id認証
  - [x] room所有権チェック
  - [x] settings列読み取り（NULL時はnull返却）
  - [x] JSONレスポンス返却
- [x] `PUT /rooms/{room_id}/settings`エンドポイント
  - [x] device_id認証
  - [x] room所有権チェック
  - [x] **リクエストボディサイズチェック（10KB制限、413返却）**
  - [x] リクエストボディパース（`null`の場合も対応）
  - [x] バリデーション実行（`validate_settings()`）
  - [x] settings列更新（`null`の場合はDB列をNULLに更新）
  - [x] JSONレスポンス返却
- [x] エラーハンドリング（401/403/404/400/413/500）
- [x] API統合テスト作成

#### 1.4 CLI実行ロジック変更
- [x] `build_claude_command(prompt, settings)`実装
- [x] `build_codex_command(prompt, settings)`実装
- [x] job作成処理でsettings読み込み・CLI構築
- [x] 既存機能（settings=NULL）の動作確認

---

### Phase 2: iOS データ層 (4-6時間)

#### 2.1 モデル定義
- [x] `RoomSettings`構造体
- [x] `ClaudeSettings`構造体（CodingKeys含む）
- [x] `CodexSettings`構造体（CodingKeys含む）
- [ ] `GetSettingsResponse`構造体
- [ ] `UpdateSettingsRequest`構造体
- [x] デフォルト値定義（`.default`）
- [x] Equatable適合確認

#### 2.2 API Service拡張
- [x] `APIService`に`getSettings(roomId:deviceId:)`メソッド追加
- [x] `APIService`に`updateSettings(roomId:deviceId:settings:)`メソッド追加
- [ ] エラーハンドリング（`APIError.unauthorized`, `.forbidden`, `.validationError`等）
- [ ] ユニットテスト（モックレスポンスで動作確認）

#### 2.3 ViewModelロジック
- [ ] `RoomDetailViewModel`に`@Published var settings: RoomSettings?`追加
- [x] `loadSettings()`メソッド実装（`RoomSettingsViewModel`で対応）
- [x] `updateSettings(_:)`メソッド実装（save/ reset メソッドで対応）
- [x] エラー状態管理（`@Published var settingsError: String?`相当=errorMessage）

---

### Phase 3: iOS UI実装 (8-12時間)

#### 3.1 設定画面ナビゲーション
- [x] `RoomDetailView`にToolbarItem「設定」ボタン追加（InputBar経由）
- [x] `.sheet`で`RoomSettingsView`へ遷移
- [x] `RoomSettingsView`に`runner: String`パラメータを追加
- [x] **Runner別表示**: 選択中のrunner（Claude/Codex）の設定のみ表示
  - [x] `RoomDetailView`から`selectedTab.rawValue`を渡す
  - [x] ナビゲーションタイトルを動的変更（"Claude設定" or "Codex設定"）

#### 3.2 Claude Settings UI
- [x] Section("Claude")内にClaude設定を配置
- [x] Model選択: `Picker`（Sonnet/Opus/Haiku）
- [x] Permission Mode選択: `Picker`（Default/Ask/Deny）
- [x] Tools選択: `ToolsEditor`（Toggle方式）
- [x] Custom Flags: `CustomFlagsEditor`（カンマ区切り入力）
  - [x] 配列⇔文字列変換ロジック

#### 3.3 Codex Settings UI
- [x] Section("Codex")内にCodex設定を配置
- [x] Model選択: `Picker`（GPT-5.1/GPT-5.1-Codex/GPT-5.1-Codex-Mini/GPT-5.1-Codex-Max）
- [x] Sandbox選択: `Picker`（read-only/workspace-write/danger-full-access）
- [x] Approval Policy選択: `Picker`（untrusted/on-failure/on-request/never）
- [x] Reasoning Effort選択: `Picker`（low/medium/high/extra-high）
- [x] Custom Flags: `CustomFlagsEditor`（カンマ区切り入力）

#### 3.4 保存・リセット機能
- [x] Toolbarに「保存」ボタン
  - [x] `save()`呼び出し（サーバーから最新設定取得→マージ→保存）
  - [x] 成功時画面を閉じる
  - [x] 失敗時エラーアラート表示
- [x] 「デフォルトに戻す」ボタン（bottomBar）
  - [x] `setDefaultToServer()`呼び出し（settings=nullで送信）
  - [x] 成功時画面を閉じる

#### 3.5 ローディング・エラー表示
- [x] 画面表示時`load()`呼び出し（.task修飾子）
- [x] ローディング中`ProgressView`表示（.overlay）
- [x] エラー時エラーアラート表示
- [x] settings=nullの場合デフォルト値で初期化

#### 3.6 Runner別設定マージロジック
- [x] `RoomSettingsViewModel`に`runner: String`を追加
- [x] `save()`メソッドで保存時の設定マージを実装:
  ```swift
  let currentSettings = try await getRoomSettings() ?? .default
  let mergedSettings = runner == "claude"
      ? RoomSettings(claude: settings.claude, codex: currentSettings.codex)
      : RoomSettings(claude: currentSettings.claude, codex: settings.codex)
  ```
- [x] これにより、Claude設定を編集してもCodex設定は保持される

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
- [ ] バリデーション単体テスト（**24ケース、上記V1-V24に対応**）
  - [ ] 正常系: 全パターンの許可値（model, sandbox, approval_policy, reasoning_effort等）
  - [ ] 異常系: 不正なmodel名、危険フラグ、**予約オプション（-r含む）**、長すぎるフラグ等
  - [ ] 境界値: custom_flags 10個/11個、JSON 10KB/10KB+1等
  - [ ] **settings=null処理（デフォルト設定適用確認）**
- [ ] API統合テスト（**10ケース以上**）
  - [ ] GET /settings: 認証成功/失敗、所有権あり/なし、settings有/無
  - [ ] PUT /settings: 更新成功、バリデーションエラー、認証失敗、**413サイズ超過**、**null更新**等
- [ ] CLI構築テスト（**12ケース、上記C1-C12に対応**）
  - [ ] `build_claude_command()`出力確認
  - [ ] `build_codex_command()`出力確認（**-rオプション含む**）
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
| R1 | custom_flagsによるコマンドインジェクション | 高 | 予約オプション禁止、危険フラグブラックリスト、シェルメタ文字拒否、subprocess引数リスト渡し |
| R2 | custom_flagsで予約オプション迂回（設定上書き） | **高** | **RESERVED_FLAGSリストで`--model`/`-s`/`-a`等を禁止、バリデーションで拒否** |
| R3 | 巨大なsettings JSONによるDB負荷・OOM | 中 | **リクエストボディサイズ10KB制限（FastAPI層で即座にチェック）、413エラー返却** |
| R4 | 不正なmodel名によるCLI実行失敗 | 中 | 許可値リストでバリデーション、job失敗時エラーログ記録 |
| R5 | 複数デバイスの設定競合 | 低 | Last-Write-Wins方式、楽観的ロック（将来的にversion列追加） |
| R6 | 既存機能への影響（settings=NULL処理） | 中 | フォールバック処理、既存機能の回帰テスト |
| R7 | watchOS画面サイズでUI崩れ | 低 | シンプルなList+NavigationLink構成、実機テスト |

### 対策詳細

#### R1対策: コマンドインジェクション & R2対策: 予約オプション迂回
```python
# 予約済みオプション（custom_flagsで指定不可）
RESERVED_FLAGS = {
    "claude": ["--model", "--permission-mode", "--tools"],
    "codex": ["-m", "--model", "-s", "--sandbox", "-a", "--ask-for-approval", "-r", "--reasoning-effort"]
}

# 危険フラグのブラックリスト
DANGEROUS_FLAGS = [
    "--exec", "--eval", "--unsafe", "--allow-root",
    "--disable-sandbox", "--no-verify", "--rm", "--delete"
]

# シェルメタ文字のチェック
SHELL_META_CHARS = [";", "|", "&", "$", "`", "(", ")", "<", ">", "\n", "\r"]

def validate_custom_flags(flags: list[str], ai_type: str) -> None:
    reserved = RESERVED_FLAGS.get(ai_type, [])

    for flag in flags:
        # フラグ名部分を抽出（値部分を除外）
        flag_name = flag.split("=")[0].split()[0]

        # 予約オプションチェック（R2対策）
        if flag_name in reserved:
            raise ValueError(
                f"Reserved flag cannot be used in custom_flags: {flag_name}. "
                f"Use the dedicated setting field instead."
            )

        # 危険フラグ（R1対策）
        if any(d in flag.lower() for d in DANGEROUS_FLAGS):
            raise ValueError(f"Dangerous flag: {flag}")

        # シェルメタ文字（R1対策）
        if any(c in flag for c in SHELL_META_CHARS):
            raise ValueError(f"Invalid character in flag: {flag}")
```

**重要**: 予約オプション（`--model`, `-s`, `-a`等）を`custom_flags`に入れることは禁止。これにより、ユーザーが設定済みのパラメータを`custom_flags`で上書きして迂回する攻撃を防ぎます。

#### R3対策: 10KBサイズ制限の強制
```python
@app.put("/rooms/{room_id}/settings")
async def update_settings(room_id: str, request: Request, device_id: str = Query(...)):
    # リクエストボディサイズチェック（10KB制限）
    body = await request.body()
    if len(body) > 10_240:  # 10KB
        raise HTTPException(413, detail="Settings JSON exceeds 10KB limit")

    # 以下、既存処理（パース、バリデーション、DB更新）
    ...
```

**重要**: FastAPI層で`request.body()`取得直後にサイズチェックを実施することで、巨大なJSONによるOOM攻撃を防ぎます。

#### R5対策: 設定競合
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
| V3 | 正常: Codex model=gpt-5.1-codex | `{"codex": {"model": "gpt-5.1-codex"}}` | 受理 |
| V4 | 異常: 不正なmodel名 | `{"claude": {"model": "gpt-10"}}` | 400 Bad Request |
| V5 | 異常: 危険フラグ --exec | `{"claude": {"custom_flags": ["--exec"]}}` | 400 Bad Request |
| V6 | 異常: シェルメタ文字 ; | `{"claude": {"custom_flags": ["--flag;rm -rf"]}}` | 400 Bad Request |
| V7 | **異常: 予約オプション --model** | `{"claude": {"custom_flags": ["--model", "opus"]}}` | **400 Bad Request** |
| V8 | **異常: 予約オプション -s** | `{"codex": {"custom_flags": ["-s", "danger-full-access"]}}` | **400 Bad Request** |
| V9 | 境界値: custom_flags 10個 | `{"custom_flags": ["--a", ..., "--j"]}` (10個) | 受理 |
| V10 | 境界値: custom_flags 11個 | `{"custom_flags": ["--a", ..., "--k"]}` (11個) | 400 Bad Request |
| V11 | 境界値: JSON 10KB | 10240バイトのJSON | 受理 |
| V12 | 境界値: JSON 10KB+1 | 10241バイトのJSON | **413 Payload Too Large** |
| V13 | 異常: 不正なpermission_mode | `{"claude": {"permission_mode": "hoge"}}` | 400 Bad Request |
| V14 | 異常: 不正なsandbox値 | `{"codex": {"sandbox": "isolated"}}` | **400 Bad Request**（正しくは`read-only/workspace-write/danger-full-access`） |
| V15 | 異常: 不正なapproval_policy値 | `{"codex": {"approval_policy": "always"}}` | **400 Bad Request**（正しくは`untrusted/on-failure/on-request/never`） |
| V16 | 異常: 不正なtools名 | `{"claude": {"tools": ["UnknownTool"]}}` | 400 Bad Request |
| V17 | 正常: tools空配列 | `{"claude": {"tools": []}}` | 受理 |
| V18 | 異常: custom_flag長すぎる | `{"custom_flags": ["--" + "a"*200]}` (101文字) | 400 Bad Request |
| V19 | 正常: settings=null | `PUT /settings` with `null` body | settings列をNULLに更新 |
| V20 | 正常: Codex sandbox=danger-full-access | `{"codex": {"sandbox": "danger-full-access"}}` | 受理 |
| V21 | 正常: Codex reasoning_effort=high | `{"codex": {"reasoning_effort": "high"}}` | 受理 |
| V22 | 正常: Codex reasoning_effort=extra-high | `{"codex": {"reasoning_effort": "extra-high"}}` | 受理 |
| V23 | 異常: 不正なreasoning_effort値 | `{"codex": {"reasoning_effort": "ultra"}}` | 400 Bad Request（正しくは`low/medium/high/extra-high`） |
| V24 | **異常: 予約オプション -r** | `{"codex": {"custom_flags": ["-r", "high"]}}` | **400 Bad Request** |

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
| C7 | Codex model=gpt-5.1-codex-max | `{"codex": {"model": "gpt-5.1-codex-max"}}` | `["codex", "-m", "gpt-5.1-codex-max"]` |
| C8 | Codex sandbox=workspace-write | `{"codex": {"sandbox": "workspace-write"}}` | `["codex", "-s", "workspace-write"]` |
| C9 | Codex approval_policy=untrusted | `{"codex": {"approval_policy": "untrusted"}}` | `["codex", "-a", "untrusted"]` |
| C10 | Codex 複合 | model+sandbox+approval_policy | `["codex", "-m", "gpt-5.1-codex", "-s", "workspace-write", "-a", "on-failure"]` |
| C11 | Codex reasoning_effort=high | `{"codex": {"reasoning_effort": "high"}}` | `["codex", "-r", "high"]` |
| C12 | Codex 複合+reasoning | model+sandbox+approval_policy+reasoning_effort | `["codex", "-m", "gpt-5.1-codex-max", "-s", "workspace-write", "-a", "on-failure", "-r", "extra-high"]` |

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
- [ ] 全テストケース合格（**バリデーション24件、API 10件、CLI 12件、UI 10件**）
- [ ] E2Eテスト成功（iOS/watchOS→サーバー→CLI実行→設定反映）
- [ ] 既存機能の回帰テストパス（チャット、ファイルブラウザ等）
- [ ] Master_Specification.md更新完了
- [ ] コードレビュー承認（**セキュリティレビュー含む：予約オプション迂回対策（-r含む）、10KBサイズ制限確認**）

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
  -m, --model [gpt-5.1|gpt-5.1-codex|gpt-5.1-codex-mini|gpt-5.1-codex-max]
  -s, --sandbox [read-only|workspace-write|danger-full-access]
  -a, --ask-for-approval [untrusted|on-failure|on-request|never]
  -r, --reasoning-effort [low|medium|high|extra-high]
```

**注意**:
- v1.0で記載していた`--search`フラグは削除されました（Codex CLIに該当オプションが存在しない可能性があるため、必要な場合は`custom_flags`に追加）。
- GPT-5.1モデルファミリー（2025年11月19日リリース）:
  - `gpt-5.1`: 標準モデル
  - `gpt-5.1-codex`: コーディング最適化モデル
  - `gpt-5.1-codex-mini`: 軽量版
  - `gpt-5.1-codex-max`: 最高品質（77.9% SWE-Bench Verified、30%トークン削減、compaction技術搭載）

### 関連ドキュメント

- [Master_Specification.md](../Specifications/Master_Specification.md) - システム全体仕様
- [File_Browser_and_Markdown_Editor.md](./File_Browser_and_Markdown_Editor.md) - ファイルブラウザ実装計画（セキュリティ参考）

---

## 🔄 変更履歴

| 日付 | バージョン | 変更内容 | 担当 |
|------|---------|---------|------|
| 2025-11-20 | 1.0 | 初版作成 | Claude |
| 2025-11-20 | 1.1 | レビュー1反映（重大な仕様ギャップ修正）:<br>・**予約オプション迂回対策**: `RESERVED_FLAGS`リスト追加、`custom_flags`で`--model`/`-s`/`-a`等を禁止<br>・**10KBサイズ制限の強制**: FastAPI層で`request.body()`取得直後にサイズチェック、413返却<br>・**settings=null処理の明確化**: PUT時に`null`ボディ送信でDB列をNULL更新、デフォルト設定適用<br>・**Codex CLI仕様修正**: `sandbox`は`read-only/workspace-write/danger-full-access`、`approval_policy`は`untrusted/on-failure/on-request/never`<br>・**enable_search削除**: Codex設定から`enable_search`フィールドを削除（該当CLIオプション不在）<br>・バリデーションテスト数を20件に統一（V7-V8で予約オプションテスト追加、V14-V15でCodex許可値テスト追加）<br>・リスクR2追加（予約オプション迂回）、R3対策詳細追加（10KB制限実装例） | Claude |
| 2025-11-20 | 1.2 | レビュー2反映（旧仕様残存の修正）:<br>・**FR-4からWeb Searchトグル削除**（enable_search削除に伴う整合性確保）<br>・**CLIテスト表C8-C10修正**: `sandbox=isolated`→`workspace-write`、`--search`削除、`approval_policy`追加<br>・**Phase 1.2テスト件数統一**: 「各15ケース以上」→「20ケース、V1-V20対応」に修正<br>・テスト観点の整合性確保（V14とC8の矛盾解消） | Claude |
| 2025-11-20 | 1.3 | GPT-3.5削除（ユーザー要望）:<br>・FR-4、ALLOWED_VALUES、Phase 3.3 UI、参考情報から`gpt-3.5-turbo`を削除<br>・モデル選択肢: `gpt-4`, `gpt-4-turbo`, `o1-preview`, `o1-mini`に統一 | Claude |
| 2025-11-20 | 1.4 | GPT-5.1モデルファミリー対応（ユーザー指摘）:<br>・Codexモデルリストを最新版に更新: `gpt-5.1`, `gpt-5.1-codex`, `gpt-5.1-codex-mini`, `gpt-5.1-codex-max`<br>・デフォルトモデルを`gpt-5.1-codex`に変更<br>・ALLOWED_VALUES、FR-4 UI、Phase 3.3 UI、参考情報、テストケース（V3, C7, C10）を更新<br>・GPT-5.1ファミリーの説明追加（2025年11月19日リリース、77.9% SWE-Bench Verified、compaction技術） | Claude |
| 2025-11-20 | 1.5 | Reasoning Effort対応（ユーザー指摘）:<br>・Codex設定に`reasoning_effort`フィールド追加（`low`, `medium`, `high`, `extra-high`）<br>・デフォルト値を`medium`に設定<br>・FR-2、FR-4、ALLOWED_VALUES、CodexSettings構造体、Phase 3.3 UI、Codex CLI仕様を更新<br>・`build_codex_command()`に`-r`/`--reasoning-effort`オプション追加<br>・RESERVED_FLAGSに`-r`/`--reasoning-effort`を追加（custom_flags迂回防止） | Claude |
| 2025-11-20 | 1.6 | 値表記ゆれ修正・テスト整備（ユーザー指摘）:<br>・**UI表記統一**: 「Extra high」→「extra-high」に修正（ALLOWED_VALUESと一致、400エラー防止）<br>・**バリデーションテスト追加**: V21-V24追加（reasoning_effort正常/異常/予約オプション -r 検証）、件数を24件に更新<br>・**CLIテスト追加**: C11-C12追加（-r単体・複合検証）、件数を12件に更新<br>・Phase 1.2、Phase 5.1、完了条件のテスト件数を更新<br>・FR-4に「そのまま送信」の注記追加 | Claude |
| 2025-11-20 | 1.7 | Runner別UI表示・設定マージ実装（Phase 3完了）:<br>・**Runner別表示**: `RoomSettingsView`に`runner: String`パラメータ追加、選択中のrunner設定のみ表示<br>・**APIClient CodingKeys修正**: `SettingsResponse`に`room_id`マッピング追加（デコードエラー解消）<br>・**設定マージロジック**: `save()`で最新設定取得→編集runner部分のみ更新→未編集runner保持<br>・**ナビゲーション**: `RoomDetailView`から`selectedTab.rawValue`を渡す、タイトル動的変更<br>・Phase 3.1-3.6を完了にマーク | Claude |

---

**実装計画 v1.7 完成**
**Phase 3 (iOS UI実装) 完了**
**次のステップ**: Phase 4 (watchOS対応) → Phase 5 (テスト)
