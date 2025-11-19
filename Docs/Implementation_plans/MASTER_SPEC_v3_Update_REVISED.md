# MASTER_SPECIFICATION.md v3.0 更新計画（改訂版）

**作成日**: 2025-11-19
**対象ファイル**: `Docs/Specifications/Master_Specification.md`
**現行状態**: ヘッダーのみv3.0、本文はv2.0のまま
**更新理由**: Room-Based Architecture実装済み内容を仕様書に反映

---

## 現状分析

### ✅ 完了済み（実装とヘッダー更新）
- ヘッダー: バージョン3.0、最終更新日2025-11-19、変更履歴追記済み
- サーバー実装: rooms テーブル、room_id統合、workspace_path対応、REST API拡張
- iOS部分実装: Room.swift, Job.roomId必須化、APIClient拡張

### ❌ 未完了（仕様書本文がv2.0のまま）
- §5 データベース設計: roomsテーブル未記載、device_sessions/jobsのroom_id欠落
- §6 REST API: /rooms, /messages, DELETE /sessions 未記載、POST /jobsのroom_id未反映
- §8 iOS設計: Room関連モデル・ViewModel・View未記載
- §10 セキュリティ: workspace信頼モデル未記載
- §11 実装ロードマップ: v2→v3移行手順未記載

### ⚠️ 章番号の競合
- 計画案の新章10「セキュリティとバリデーション」は既存§10と重複
- 計画案の新章11「データ移行」は既存§11と重複
- **解決策**: 既存章を拡張する形で統合（新章追加ではなく既存章のサブセクション追加）

---

## 更新方針（Codex提案ベース・修正版）

### 方針1: ヘッダーはスキップ（完了済み）
Phase 1（ヘッダー・変更履歴）は実施済みのためスキップ

### 方針2: 既存章との統合を明文化
- §5: 既存テーブル定義の後にroomsテーブル追加、device_sessions/jobsに"(v3.0更新)"脚注
- §6: 既存API定義の後に新規エンドポイント追加
- §8: 既存iOS画面構成の後にRoom関連追加
- §10: 既存「10.2 入力バリデーション」の後に「10.3 ワークスペース信頼モデル」追加
- §11: 既存ロードマップの後に「11.X v2→v3移行手順」追加

### 方針3: 反映箇所の行番号を明記
- 各変更箇所に「Master_Specification.md:行番号」を記載し、差し替え範囲を明示

---

## Phase 1: §5 データベース設計の更新（v3.0反映）

### ☐ 1.1 既存DB章の位置確認

**対象箇所**: `Master_Specification.md:line 883-933` 付近（§5 データベース設計）

**現状**:
- 5.1 概要
- 5.2 jobs テーブル
- 5.3 devices テーブル
- 5.4 device_sessions テーブル

**追加先**: 5.4の後に「5.5 rooms テーブル (v3.0追加)」を挿入

### ☐ 1.2 roomsテーブル定義追加

**挿入位置**: `Master_Specification.md:line 933` 付近（device_sessionsテーブル定義の直後）

**追加内容**:
```markdown
### 5.5 rooms テーブル (v3.0追加)

**目的**: プロジェクト/ワークスペース別のセッション管理を実現

| カラム名 | 型 | 制約 | 説明 |
|---------|-----|------|------|
| id | String(36) | PRIMARY KEY | UUID |
| name | String(100) | NOT NULL | ルーム名（例: "RemotePrompt"） |
| workspace_path | String(500) | NOT NULL | 作業ディレクトリ（例: "/Users/macstudio/Projects/RemotePrompt"） |
| icon | String(50) | DEFAULT "folder" | アイコン（folder, 🚀, 💻等） |
| device_id | String(100) | NOT NULL | 所有者デバイスID |
| created_at | DateTime | NOT NULL | 作成日時 |
| updated_at | DateTime | NOT NULL | 更新日時 |

**セキュリティ制約**:
- `workspace_path` は `utils/path_validator.py` でホワイトリスト検証を実施
- 許可ベースパス: `/Users/macstudio/Projects`, `/Users/macstudio/Documents`
- 禁止パス: `/System`, `/Library`, `/private`, `/etc`, `/bin`

**v3.0での役割**:
- デバイスごとに複数のプロジェクト/ワークスペースを管理
- セッション分離の単位として (device_id, room_id, runner) の3次元管理を実現
- ジョブ実行時の `cwd` パラメータとして `workspace_path` を使用
```

### ☐ 1.3 device_sessionsテーブルにroom_id追加の脚注

**変更箇所**: `Master_Specification.md:line 920` 付近（device_sessionsテーブル定義）

**修正前**:
```markdown
### 5.4 device_sessions テーブル

| カラム名 | 型 | 制約 | 説明 |
|---------|-----|------|------|
| device_id | String(100) | PRIMARY KEY | デバイスID |
| runner | String(20) | PRIMARY KEY | "claude" or "codex" |
| session_id | String(100) | NOT NULL | セッションID |
| created_at | DateTime | NOT NULL | 作成日時 |
| updated_at | DateTime | NOT NULL | 更新日時 |
```

**修正後**:
```markdown
### 5.4 device_sessions テーブル

| カラム名 | 型 | 制約 | 説明 |
|---------|-----|------|------|
| device_id | String(100) | NOT NULL | デバイスID |
| room_id | String(36) | NOT NULL | ルームID (v3.0追加) |
| runner | String(20) | NOT NULL | "claude" or "codex" |
| session_id | String(100) | NOT NULL | セッションID |
| created_at | DateTime | NOT NULL | 作成日時 |
| updated_at | DateTime | NOT NULL | 更新日時 |

**制約** (v3.0更新):
- UNIQUE(device_id, room_id, runner) - 3次元セッション分離
- INDEX(device_id, room_id, runner)

**v3.0での変更点**:
- v2.0: device_id + runner でセッション管理（全プロジェクト共有）
- v3.0: device_id + room_id + runner でセッション管理（ルームごとに独立）
```

### ☐ 1.4 jobsテーブルにroom_id追加の脚注

**変更箇所**: `Master_Specification.md:line 890-905` 付近（jobsテーブル定義）

**修正対象行**: `room_id` カラムを追加

**追加内容**:
```markdown
| room_id | String(36) | NOT NULL | ルームID (v3.0追加) |
```

**脚注追加**:
```markdown
**v3.0での変更点**:
- `room_id` カラム追加: ジョブが属するルームを識別
- ジョブ実行時に `room.workspace_path` を `cwd` として使用
```

---

## Phase 2: §6 REST API仕様の拡張

### ☐ 2.1 既存API章の位置確認

**対象箇所**: `Master_Specification.md:line 1000-1140` 付近（§6 REST API仕様）

**現状**:
- 6.1 認証
- 6.2 デバイス登録 (POST /register_device)
- 6.3 ジョブ管理 (POST /jobs, GET /jobs, GET /jobs/{id})
- 6.4 セッション管理 (GET /sessions/{device_id}/{runner}, DELETE /sessions)
- 6.5 ヘルスチェック (GET /health)

**追加先**: 6.5の後に「6.6 ルーム管理API (v3.0追加)」「6.7 メッセージ履歴API (v3.0追加)」を挿入

### ☐ 2.2 POST /jobs にroom_id追加の脚注

**変更箇所**: `Master_Specification.md:line 1040` 付近（POST /jobs定義）

**修正前**:
```markdown
#### POST /jobs

**リクエストボディ**:
```json
{
  "runner": "claude",
  "input_text": "プロジェクトの概要を教えて",
  "device_id": "iphone-test-1"
}
```
```

**修正後**:
```markdown
#### POST /jobs

**リクエストボディ** (v3.0更新):
```json
{
  "runner": "claude",
  "input_text": "プロジェクトの概要を教えて",
  "device_id": "iphone-test-1",
  "room_id": "12345678-1234-1234-1234-123456789012"
}
```

**v3.0での変更点**:
- `room_id` フィールドを必須化
- バックグラウンドタスクで `room.workspace_path` を `cwd` として渡す
- v2.0互換モード（後方互換性の項を参照）では room_id 未指定時にデフォルトルーム使用
```

### ☐ 2.3 ルーム管理API追加

**挿入位置**: `Master_Specification.md:line 1130` 付近（6.5 ヘルスチェックの後）

**追加内容**:
```markdown
### 6.6 ルーム管理API (v3.0追加)

#### GET /rooms

**目的**: デバイスが所有する全ルームを取得

**認証**: x-api-key ヘッダー必須

**クエリパラメータ**:
| パラメータ | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| device_id | string | ✅ | デバイスID |

**レスポンス例**:
```json
[
  {
    "id": "12345678-1234-1234-1234-123456789012",
    "name": "RemotePrompt",
    "workspace_path": "/Users/macstudio/Projects/RemotePrompt",
    "icon": "folder",
    "device_id": "iphone-test-1",
    "created_at": "2025-11-19T12:00:00.000000",
    "updated_at": "2025-11-19T12:00:00.000000"
  }
]
```

**ステータスコード**:
- 200: 成功
- 400: device_id パラメータ不足
- 401: APIキー認証失敗

---

#### POST /rooms

**目的**: 新規ルーム作成

**認証**: x-api-key ヘッダー必須

**リクエストボディ**:
```json
{
  "device_id": "iphone-test-1",
  "name": "MyNewProject",
  "workspace_path": "/Users/macstudio/Projects/MyNewProject",
  "icon": "🚀"
}
```

**バリデーション**:
- `workspace_path` は `utils/path_validator.py` でセキュリティ検証（§10.3参照）
- 許可されたベースパス内に存在すること
- システムディレクトリへのアクセスは拒否

**レスポンス例**:
```json
{
  "id": "87654321-4321-4321-4321-210987654321",
  "name": "MyNewProject",
  "workspace_path": "/Users/macstudio/Projects/MyNewProject",
  "icon": "🚀",
  "device_id": "iphone-test-1",
  "created_at": "2025-11-19T13:00:00.000000",
  "updated_at": "2025-11-19T13:00:00.000000"
}
```

**ステータスコード**:
- 201: 作成成功
- 400: バリデーションエラー（不正なworkspace_path、必須フィールド不足）
- 401: APIキー認証失敗

---

#### DELETE /rooms/{room_id}

**目的**: ルーム削除（関連セッション・ジョブも削除）

**認証**: x-api-key ヘッダー必須

**パスパラメータ**:
| パラメータ | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| room_id | string | ✅ | 削除対象ルームのUUID |

**クエリパラメータ**:
| パラメータ | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| device_id | string | ✅ | 所有者確認用デバイスID |

**セキュリティ**:
- `room.device_id` と `request.device_id` の一致確認
- 不一致の場合は 403 Forbidden

**レスポンス例**:
```json
{
  "status": "ok",
  "deleted": {
    "room": 1,
    "sessions": 2,
    "jobs": 15
  }
}
```

**ステータスコード**:
- 200: 削除成功
- 403: 所有者不一致
- 404: ルームが存在しない
```

### ☐ 2.4 メッセージ履歴API追加

**挿入位置**: 6.6の直後

**追加内容**:
```markdown
### 6.7 メッセージ履歴API (v3.0追加)

#### GET /messages

**目的**: ルーム×ランナー別のメッセージ履歴取得（チャット表示用）

**認証**: x-api-key ヘッダー必須

**クエリパラメータ**:
| パラメータ | 型 | 必須 | デフォルト | 説明 |
|-----------|-----|------|-----------|------|
| device_id | string | ✅ | - | デバイスID |
| room_id | string | ✅ | - | ルームID |
| runner | string | ✅ | - | "claude" or "codex" |
| limit | integer | ❌ | 20 | 取得件数 |
| offset | integer | ❌ | 0 | スキップ件数 |

**レスポンス例**:
```json
[
  {
    "id": "job-uuid-1",
    "runner": "claude",
    "input_text": "プロジェクトの概要を教えて",
    "status": "success",
    "stdout": "このプロジェクトは...",
    "stderr": "",
    "exit_code": 0,
    "created_at": "2025-11-19T10:00:00.000000",
    "started_at": "2025-11-19T10:00:01.000000",
    "finished_at": "2025-11-19T10:00:05.000000"
  }
]
```

**仕様**:
- `jobs` テーブルから `device_id`, `room_id`, `runner` でフィルタ
- 降順取得 (`ORDER BY created_at DESC`) 後に反転（最新が下に表示）
- ページング対応 (`LIMIT`, `OFFSET`)

**ステータスコード**:
- 200: 成功
- 400: 必須パラメータ不足
- 401: APIキー認証失敗
```

### ☐ 2.5 DELETE /sessions にroom_id追加の脚注

**変更箇所**: `Master_Specification.md:line 1100` 付近（DELETE /sessions定義）

**修正前**:
```markdown
#### DELETE /sessions

**クエリパラメータ**:
- device_id (必須)
- runner (必須)
```

**修正後**:
```markdown
#### DELETE /sessions

**クエリパラメータ** (v3.0更新):
- device_id (必須)
- room_id (必須, v3.0追加)
- runner (必須)

**v3.0での変更点**:
- v2.0: `device_id` + `runner` でセッション識別
- v3.0: `device_id` + `room_id` + `runner` の3次元でセッション識別
- ルーム×ランナー別のチャット履歴リセットが可能
```

---

## Phase 3: §8 iOS App Design の拡張

### ☐ 3.1 既存iOS章の位置確認

**対象箇所**: `Master_Specification.md:line 1384-1682` 付近（§8 iOS アプリ仕様）

**現状**:
- 8.1 プロジェクト構成
- 8.2 データモデル (Job)
- 8.3 API Client
- 8.4 主要画面 (JobsListView, JobDetailView, NewJobView)
- 8.5 Info.plist
- 8.6 プッシュ通知
- 8.7 Markdownレンダリング
- 8.8 APIキー設定

**追加先**: 8.2データモデルにRoom追加、8.4主要画面にRoom関連View追加

### ☐ 3.2 データモデルにRoom追加

**挿入位置**: `Master_Specification.md:line 1440` 付近（8.2 データモデル、Jobの後）

**追加内容**:
```markdown
#### Room.swift (v3.0追加)

**目的**: ルーム（プロジェクト/ワークスペース）の表現

```swift
import Foundation

struct Room: Codable, Identifiable, Hashable {
    let id: String
    var name: String  // 編集可能
    var workspacePath: String  // 編集可能
    var icon: String  // 編集可能
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

**プロパティ**:
- `name`, `workspacePath`, `icon`: `var` に変更（編集可能化）
- `id`, `deviceId`: `let` のまま（不変）
```

### ☐ 3.3 既存Jobモデルにroom_id追加の脚注

**変更箇所**: `Master_Specification.md:line 1420` 付近（Job.swift定義）

**追加内容**:
```swift
let roomId: String  // v3.0追加: 必須フィールド
```

**脚注**:
```markdown
**v3.0での変更点**:
- `roomId` フィールド追加（`String` 型、必須）
- v2.0では存在しなかったフィールド
```

### ☐ 3.4 APIClientにRoom管理API追加

**挿入位置**: `Master_Specification.md:line 1510` 付近（APIClient拡張セクション）

**追加内容**:
```markdown
#### APIClient拡張 (v3.0)

```swift
extension APIClient {
    // MARK: - Room Management

    func fetchRooms(deviceId: String) async throws -> [Room] {
        guard var components = URLComponents(string: "\(Constants.baseURL)/rooms") else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode([Room].self, from: data)
    }

    func createRoom(name: String, workspacePath: String, deviceId: String, icon: String = "folder") async throws -> Room {
        // ... (実装省略、詳細はAPIClient.swiftを参照)
    }

    func deleteRoom(roomId: String, deviceId: String) async throws {
        // ... (実装省略、詳細はAPIClient.swiftを参照)
    }
}
```

**セキュリティ改善 (v3.0)**:
- URL構築を文字列結合から `URLComponents` + `URLQueryItem` に変更
- 特殊文字を含む `device_id` や `room_id` でも正しくエンコード
```

### ☐ 3.5 主要画面にRoom関連View追加

**挿入位置**: `Master_Specification.md:line 1550` 付近（8.4 主要画面、既存View定義の後）

**追加内容**:
```markdown
#### v3.0で追加された画面

1. **RoomListView** (新規)
   - デバイスが所有する全ルームをリスト表示
   - タップで RoomDetailView へ遷移
   - 右上の "+" ボタンで新規ルーム作成画面へ

2. **RoomDetailView** (新規)
   - ルーム詳細情報表示（name, workspace_path, icon）
   - Claude / Codex タブ切り替え
   - 各タブ内に ChatView を表示（ルーム×ランナー別のチャット履歴）
   - 編集ボタンでルーム名・アイコン変更（未実装）
   - 削除ボタンでルーム削除

3. **NewRoomView** (新規)
   - ルーム名入力
   - ワークスペースパス入力（例: `/Users/macstudio/Projects/MyApp`）
   - アイコン選択（絵文字ピッカー）
   - 作成ボタンで POST /rooms 呼び出し

#### 画面遷移フロー (v3.0)

```
RoomListView
  ├─ タップ → RoomDetailView
  │            ├─ Claude Tab → ChatView (room_id=xxx, runner="claude")
  │            └─ Codex Tab → ChatView (room_id=xxx, runner="codex")
  └─ "+" ボタン → NewRoomView → 作成完了 → RoomListView へ戻る
```

#### ViewModelの追加 (v3.0)

**RoomStore.swift**:
```swift
@MainActor
class RoomStore: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient = APIClient.shared
    private let deviceId = APIClient.getDeviceId()

    func fetchRooms() async { /* ... */ }
    func createRoom(name: String, workspacePath: String, icon: String) async { /* ... */ }
    func deleteRoom(_ room: Room) async { /* ... */ }
}
```
```

---

## Phase 4: §10 セキュリティの拡張

### ☐ 4.1 既存セキュリティ章の位置確認

**対象箇所**: `Master_Specification.md:line 1907-1990` 付近（§10 セキュリティとエラーハンドリング）

**現状**:
- 10.1 APIキー認証
- 10.2 入力バリデーション
- 10.3 エラーハンドリング
- 10.4 ロギング

**追加先**: 10.2の後に「10.3 ワークスペース信頼モデル (v3.0追加)」を挿入、既存10.3以降を繰り下げ

### ☐ 4.2 ワークスペース信頼モデル追加

**挿入位置**: `Master_Specification.md:line 1950` 付近（10.2 入力バリデーションの後）

**追加内容**:
```markdown
### 10.3 ワークスペース信頼モデル (v3.0追加)

#### 10.3.1 設計方針

**課題**:
- v2.0: `trusted_directory="/Users/nao/workspace"` 固定
- v3.0: ルームごとに異なる `workspace_path` を動的に設定可能

**解決策**:
- `trusted_root` 基準で `workspace_path` を検証
- 許可されたベースパス内に存在することを強制
- システムディレクトリへのアクセスを禁止

#### 10.3.2 実装

**ファイル**: `remote-job-server/utils/path_validator.py`

```python
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
    "/bin",
    "/usr",
    "/sbin",
    "/var",
]

def is_safe_workspace_path(path: str) -> bool:
    """ワークスペースパスの安全性を検証"""
    try:
        abs_path = Path(path).resolve()

        # 禁止パスチェック
        for forbidden in FORBIDDEN_PATHS:
            if str(abs_path).startswith(forbidden):
                return False

        # 許可ベースパス内に存在するかチェック
        return any(
            str(abs_path).startswith(base)
            for base in ALLOWED_BASE_PATHS
        )
    except Exception:
        return False

def validate_workspace_path(path: str) -> str:
    """ワークスペースパス検証（例外発生版）"""
    if not is_safe_workspace_path(path):
        raise ValueError(f"Invalid workspace path: {path}")
    return path
```

#### 10.3.3 使用箇所

1. **POST /rooms エンドポイント**
   - ルーム作成時に `validate_workspace_path()` で検証
   - バリデーション失敗時は 400 Bad Request

2. **session_manager.py の execute_job()**
   - `cwd` パラメータに `workspace_path` を設定
   - `Path.resolve()` でシンボリックリンク攻撃を防止

#### 10.3.4 設定手順

1. **ALLOWED_BASE_PATHS の設定**
   - `utils/path_validator.py` を環境に合わせて変更

2. **既存ルームのバリデーション**
   - データベースマイグレーション時にチェック推奨

3. **テスト**
   - 禁止パス（`/System`, `/etc`）へのアクセスが拒否されるか確認
   - 許可ベースパス内の正常なパスが受け入れられるか確認
```

### ☐ 4.3 既存10.3以降の番号を繰り下げ

**変更内容**:
- 旧 10.3 エラーハンドリング → 新 10.4 エラーハンドリング
- 旧 10.4 ロギング → 新 10.5 ロギング

---

## Phase 5: §11 実装ロードマップの拡張

### ☐ 5.1 既存ロードマップ章の位置確認

**対象箇所**: `Master_Specification.md:line 2008-2045` 付近（§11 実装ロードマップ）

**現状**:
- 11.1 Phase 1: サーバー基盤
- 11.2 Phase 2: iOS基本機能
- 11.3 Phase 3: watchOS対応

**追加先**: 11.3の後に「11.4 v2→v3移行手順 (v3.0追加)」を挿入

### ☐ 5.2 v2→v3移行手順追加

**挿入位置**: `Master_Specification.md:line 2045` 付近（11.3の後）

**追加内容**:
```markdown
### 11.4 v2→v3移行手順 (v3.0追加)

#### 11.4.1 データベーススキーマ変更

**手順**:

1. **rooms テーブル作成**
   ```bash
   cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
   source .venv/bin/activate
   python init_db.py
   ```

2. **Default Room 挿入**
   ```bash
   python create_default_room.py
   ```

   **スクリプト内容**:
   ```python
   from database import SessionLocal
   from models import Room, utcnow
   import uuid

   def create_default_room(device_id: str, name="RemotePrompt"):
       db = SessionLocal()
       try:
           room = Room(
               id=str(uuid.uuid4()),
               name=name,
               workspace_path="/Users/macstudio/Projects/RemotePrompt",
               icon="folder",
               device_id=device_id,
               created_at=utcnow(),
               updated_at=utcnow(),
           )
           db.add(room)
           db.commit()
           return room.id
       finally:
           db.close()
   ```

3. **既存レコードにroom_id追加**
   ```sql
   -- device_sessions
   UPDATE device_sessions
   SET room_id = '<default_room_id>'
   WHERE room_id IS NULL;

   -- jobs
   UPDATE jobs
   SET room_id = '<default_room_id>'
   WHERE room_id IS NULL;
   ```

#### 11.4.2 後方互換性維持戦略

**v2.0クライアント対応**:
- `POST /jobs` で `room_id` 未指定の場合、デフォルトルーム使用
- 自動作成されたデフォルトルームIDを割り当て

**廃止スケジュール**:
| バージョン | リリース予定 | v2.0互換 | 備考 |
|-----------|-------------|----------|------|
| v3.0 | 2025-11-19 | ✅ 有効 | デフォルトルーム自動作成 |
| v3.1 | 2025-12-01 | ⚠️ 非推奨警告 | ログに警告メッセージ出力 |
| v4.0 | 2026-01-01 | ❌ 廃止 | room_id 必須化 |

#### 11.4.3 ダウンタイム

**要否**: 不要

**理由**:
- スキーマ変更は新カラム追加のみ
- デフォルト値設定で既存データ互換性維持
- API・iOSは段階的ロールアウト
```

---

## Phase 6: 全体検証

### ☐ 6.1 変更箇所の脚注確認

**チェック項目**:
- [ ] §5, §6, §8, §10の該当箇所に "(v3.0で更新)" または "(v3.0追加)" 脚注
- [ ] 新設セクションのヘッダーに "(v3.0追加)" 記載

### ☐ 6.2 コード例の整合性確認

**チェック項目**:
- [ ] Pythonコード例がPEP 8準拠
- [ ] SwiftUIコード例が最新構文（async/await, @MainActor）
- [ ] SQLスキーマが `models.py` 実装と一致

### ☐ 6.3 リンク・相互参照の確認

**チェック項目**:
- [ ] 目次のアンカーリンクが正しい
- [ ] §10.3.3 のスクリプト例が実際の `create_default_room.py` と一致
- [ ] §10.3.2 のコード例が実際の `utils/path_validator.py` と一致

---

## 完了条件

### Phase 1-5 の全チェックボックスが完了
### Phase 6 の全検証項目がクリア
### 仕様書内に "room" 文字列が適切に出現（現状は変更履歴のみ）

---

## 次のステップ

1. **Phase 1**: §5 データベース設計の更新（15分）
2. **Phase 2**: §6 REST API仕様の拡張（30分）
3. **Phase 3**: §8 iOS App Design の拡張（30分）
4. **Phase 4**: §10 セキュリティの拡張（20分）
5. **Phase 5**: §11 実装ロードマップの拡張（15分）
6. **Phase 6**: 全体検証（15分）

**合計推定時間**: 約2時間5分

---

## 備考

- **元の計画との違い**:
  - Phase 1（ヘッダー更新）をスキップ（完了済み）
  - 新章追加→既存章拡張に変更（章番号競合を回避）
  - 反映箇所の行番号を明記（差し替え範囲を明確化）
  - 実装済み内容との乖離を解消（ヘッダーv3.0、本文v2.0の矛盾修正）
