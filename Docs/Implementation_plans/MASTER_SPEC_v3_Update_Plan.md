# MASTER_SPECIFICATION.md v2.0 → v3.0 更新計画

**作成日**: 2025-11-19
**対象ファイル**: `Docs/Specifications/Master_Specification.md`
**現行バージョン**: v2.0
**目標バージョン**: v3.0
**更新理由**: Room-Based Architecture実装に伴う仕様追加

---

## 更新方針サマリー（Codex提案ベース）

### 1. 変更履歴
- 冒頭にv3.0項目追加（Roomベース多拠点管理、3次元セッション、workspace動的化、API追加、iOS UI拡張）

### 2. セキュリティモデル
- 10章に「10.3 ワークスペース信頼モデル」新設
- `trusted_root` 基準で `workspace_path` を検証する仕組みを文書化

### 3. API定義
- 6章に「6.4 Rooms API」「6.5 Messages API」「6.6 Sessions API拡張」サブセクション追加
- HTTPメソッド別テーブル (Path, 認証, クエリ, スキーマ, エラーコード) を記述

### 4. iOS画面設計
- 8章にRoomListView/RoomDetailView追加
- NavigationStackフロー図とSwiftUIスニペット

### 5. 後方互換性
- 11章に「v2→v3移行手順」追加（Default Room作成、既存レコード紐付け、段階ロールアウトフラグ設計）

---

## Phase 1: ヘッダー・変更履歴の更新

### ☐ 1.1 バージョン情報更新（line 3-10）

**変更箇所**: `Docs/Specifications/Master_Specification.md:3-10`

**修正前**:
```markdown
作成日: 2025-11-16
最終更新: 2025-11-17
バージョン: 2.0（非対話モード + セッション管理版）
想定作成者: Nao

**変更履歴**:
- v1.0 (2025-11-16): PTY永続セッション方式での初版
- v2.0 (2025-11-17): 調査結果に基づき非対話モード + セッション管理方式に変更
```

**修正後**:
```markdown
作成日: 2025-11-16
最終更新: 2025-11-19
バージョン: 3.0（非対話モード + Room-Based セッション管理版）
想定作成者: Nao

**変更履歴**:
- v1.0 (2025-11-16): PTY永続セッション方式での初版
- v2.0 (2025-11-17): 調査結果に基づき非対話モード + セッション管理方式に変更
- v3.0 (2025-11-19): Room-Based Architecture実装に伴う仕様追加
  - Roomベース多拠点管理導入（複数プロジェクト/ワークスペースの並行管理）
  - セッション管理を (device_id, room_id, runner) の3次元に拡張
  - workspace_path 動的変更とパスバリデーション機能追加
  - REST API拡張: GET/POST/DELETE /rooms, GET /messages, DELETE /sessions
  - iOS UI拡張: RoomListView, RoomDetailView によるルーム選択機能
```

**検証方法**:
```bash
head -15 Docs/Specifications/Master_Specification.md
```

---

## Phase 2: 目次の更新

### ☐ 2.1 目次に新章追加（line 14-26付近）

**変更箇所**: 既存目次の末尾に以下を追加

**追加内容**:
```markdown
10. [セキュリティとバリデーション](#10-セキュリティとバリデーション)
    - 10.1 APIキー認証
    - 10.2 デバイスID検証
    - 10.3 ワークスペース信頼モデル (v3.0新設)
11. [データ移行とバージョン管理](#11-データ移行とバージョン管理)
    - 11.1 v2.0 → v3.0 移行手順 (v3.0新設)
    - 11.2 後方互換性維持戦略 (v3.0新設)
```

**注記**: 既存の目次項目はそのまま維持し、末尾に追加する形とする

---

## Phase 3: §5 データベース設計の更新

### ☐ 3.1 rooms テーブル定義追加

**変更箇所**: §5 Database Design の既存テーブル定義の後に追加

**追加内容**:
```markdown
#### 5.4 rooms テーブル (v3.0追加)

```python
class Room(Base):
    __tablename__ = "rooms"

    id = Column(String(36), primary_key=True)  # UUID
    name = Column(String(100), nullable=False)  # 例: "RemotePrompt", "MyApp"
    workspace_path = Column(String(500), nullable=False)  # 例: "/Users/macstudio/Projects/RemotePrompt"
    icon = Column(String(50), default="folder")  # 例: "folder", "🚀", "💻"
    device_id = Column(String(100), nullable=False)  # 所有者デバイスID
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)
```

**目的**:
- 複数のプロジェクト/ワークスペースを個別管理
- 各ルームに固有の作業ディレクトリ (`workspace_path`) を設定
- デバイスごとにルームを分離管理

**制約**:
- `device_id` + `name` の組み合わせは一意であることが推奨（アプリケーションレベルで検証）
- `workspace_path` は `utils/path_validator.py` でセキュリティ検証を実施
```

### ☐ 3.2 device_sessions テーブルにroom_id追加

**変更箇所**: 既存の `device_sessions` テーブル定義を修正

**修正前**:
```python
class DeviceSession(Base):
    __tablename__ = "device_sessions"

    device_id = Column(String(100), primary_key=True)
    runner = Column(String(20), primary_key=True)  # "claude" or "codex"
    session_id = Column(String(100), nullable=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)
```

**修正後**:
```python
class DeviceSession(Base):
    __tablename__ = "device_sessions"

    device_id = Column(String(100), nullable=False)
    room_id = Column(String(36), nullable=False)  # v3.0追加
    runner = Column(String(20), nullable=False)  # "claude" or "codex"
    session_id = Column(String(100), nullable=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    # v3.0: 複合主キーをUNIQUE制約に変更
    __table_args__ = (
        UniqueConstraint("device_id", "room_id", "runner", name="uq_device_room_runner"),
        Index("idx_device_room_runner", "device_id", "room_id", "runner"),
    )
```

**備考**: 脚注 "(v3.0で更新)" を追加して差分を明示

### ☐ 3.3 jobs テーブルにroom_id追加

**変更箇所**: 既存の `jobs` テーブル定義に `room_id` カラム追加

**追加フィールド**:
```python
room_id = Column(String(36), nullable=False)  # v3.0追加: ジョブが属するルーム
```

**備考**: 脚注 "(v3.0で更新)" を追加

---

## Phase 4: §6 REST API仕様の拡張

### ☐ 4.1 §6.4 Rooms API 新設

**追加箇所**: §6 REST API Specification の末尾に新セクション追加

**内容**:
```markdown
### 6.4 Rooms API (v3.0新設)

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

**エラーコード**:
- 400: device_id パラメータ不足
- 401: APIキー認証失敗
- 500: サーバー内部エラー

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

**バリデーション**:
- `workspace_path` は `utils/path_validator.py` でセキュリティ検証
- 許可されたベースパス内に存在すること
  - `/Users/macstudio/Projects`
  - `/Users/macstudio/Documents`
- システムディレクトリ (`/System`, `/Library`, `/private`, `/etc`, `/bin`, `/usr`) へのアクセスは禁止
- シンボリックリンク攻撃を防ぐため `Path.resolve()` を使用

**エラーコード**:
- 400: バリデーションエラー（不正なworkspace_path、必須フィールド不足）
- 401: APIキー認証失敗
- 500: サーバー内部エラー

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

**セキュリティ**:
- `room.device_id` と `request.device_id` の一致確認
- 不一致の場合は 403 Forbidden を返す

**エラーコード**:
- 400: room_id または device_id パラメータ不足
- 401: APIキー認証失敗
- 403: 所有者不一致（他デバイスのルームへのアクセス）
- 404: ルームが存在しない
- 500: サーバー内部エラー
```

### ☐ 4.2 §6.5 Messages API 新設

**追加内容**:
```markdown
### 6.5 Messages API (v3.0新設)

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
  },
  {
    "id": "job-uuid-2",
    "runner": "claude",
    "input_text": "続きを教えて",
    "status": "success",
    "stdout": "さらに詳しく...",
    "stderr": "",
    "exit_code": 0,
    "created_at": "2025-11-19T10:01:00.000000",
    "started_at": "2025-11-19T10:01:01.000000",
    "finished_at": "2025-11-19T10:01:08.000000"
  }
]
```

**仕様**:
- `jobs` テーブルから `device_id`, `room_id`, `runner` でフィルタ
- 降順取得 (`ORDER BY created_at DESC`) 後に反転（最新が下に表示）
- ページング対応 (`LIMIT`, `OFFSET`)

**エラーコード**:
- 400: 必須パラメータ不足
- 401: APIキー認証失敗
- 500: サーバー内部エラー
```

### ☐ 4.3 §6.6 Sessions API 拡張

**追加内容**:
```markdown
### 6.6 Sessions API (v3.0拡張)

#### DELETE /sessions

**目的**: ルーム×ランナー別のセッション削除（チャット履歴リセット）

**認証**: x-api-key ヘッダー必須

**クエリパラメータ**:
| パラメータ | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| device_id | string | ✅ | デバイスID |
| room_id | string | ✅ | ルームID (v3.0追加) |
| runner | string | ✅ | "claude" or "codex" |

**レスポンス例**:
```json
{
  "status": "ok"
}
```

**動作**:
- `device_sessions` テーブルから該当レコード削除
- 次回ジョブ実行時に新規セッションが作成される

**v2.0からの変更**:
- v2.0: `device_id` + `runner` でセッション識別
- v3.0: `device_id` + `room_id` + `runner` の3次元でセッション識別

**エラーコード**:
- 400: 必須パラメータ不足
- 401: APIキー認証失敗
- 404: セッションが存在しない
- 500: サーバー内部エラー
```

### ☐ 4.4 既存POST /jobsエンドポイントの更新

**変更箇所**: 既存の `POST /jobs` セクションに脚注追加

**追加内容**:
```markdown
**v3.0での変更**:
- リクエストボディに `room_id` フィールドを追加（必須）
- バックグラウンドタスクで `room.workspace_path` を `cwd` として渡す

**リクエストボディ例（v3.0）**:
```json
{
  "runner": "claude",
  "input_text": "プロジェクトの概要を教えて",
  "device_id": "iphone-test-1",
  "room_id": "12345678-1234-1234-1234-123456789012"
}
```
```

---

## Phase 5: §8 iOS App Design の拡張

### ☐ 5.1 §8.1 画面構成に新画面追加

**変更箇所**: 既存の画面リストに以下を追加

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
```

### ☐ 5.2 §8.2 データモデルにRoom追加

**追加内容**:
```markdown
#### Room.swift (v3.0追加)

```swift
import Foundation

struct Room: Codable, Identifiable, Hashable {
    let id: String
    var name: String  // v3.0: 編集可能
    var workspacePath: String  // v3.0: 編集可能
    var icon: String  // v3.0: 編集可能
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

**変更点**:
- `name`, `workspacePath`, `icon` を `var` に変更（編集可能化）
```

### ☐ 5.3 §8.2 既存JobモデルにroomId追加の脚注

**変更箇所**: 既存の `Job.swift` セクションに脚注追加

**追加内容**:
```markdown
**v3.0での変更**:
- `roomId` フィールドを追加（`String` 型、必須）

```swift
struct Job: Codable, Identifiable {
    let id: String
    let runner: String
    let inputText: String?
    let deviceId: String?
    let roomId: String  // v3.0追加: 必須フィールド
    var status: String
    // ... 以下省略
}
```
```

### ☐ 5.4 §8.3 APIClientにRoom管理API追加

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
        guard let url = URL(string: "\(Constants.baseURL)/rooms") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "device_id": deviceId,
            "name": name,
            "workspace_path": workspacePath,
            "icon": icon
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode(Room.self, from: data)
    }

    func deleteRoom(roomId: String, deviceId: String) async throws {
        guard var components = URLComponents(string: "\(Constants.baseURL)/rooms/\(roomId)") else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(Constants.apiKey, forHTTPHeaderField: "x-api-key")

        let (_, _) = try await URLSession.shared.data(for: request)
    }
}
```

**セキュリティ改善 (v3.0)**:
- URL構築を文字列結合から `URLComponents` + `URLQueryItem` に変更
- 特殊文字（`+`, `/`, `%` 等）を含む `device_id` や `room_id` でも正しくエンコード
```

### ☐ 5.5 §8.4 ViewModelにRoomStore追加

**追加内容**:
```markdown
#### RoomStore.swift (v3.0追加)

```swift
import Foundation

@MainActor
class RoomStore: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient = APIClient.shared
    private let deviceId = APIClient.getDeviceId()

    func fetchRooms() async {
        isLoading = true
        errorMessage = nil

        do {
            rooms = try await apiClient.fetchRooms(deviceId: deviceId)
        } catch {
            errorMessage = "ルーム取得失敗: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func createRoom(name: String, workspacePath: String, icon: String) async {
        do {
            let newRoom = try await apiClient.createRoom(
                name: name,
                workspacePath: workspacePath,
                deviceId: deviceId,
                icon: icon
            )
            rooms.append(newRoom)
        } catch {
            errorMessage = "ルーム作成失敗: \(error.localizedDescription)"
        }
    }

    func deleteRoom(_ room: Room) async {
        do {
            try await apiClient.deleteRoom(roomId: room.id, deviceId: deviceId)
            rooms.removeAll { $0.id == room.id }
        } catch {
            errorMessage = "ルーム削除失敗: \(error.localizedDescription)"
        }
    }
}
```
```

---

## Phase 6: §10 セキュリティとバリデーション (新章)

### ☐ 6.1 §10 新設

**追加箇所**: §9 の後に新章として追加

**内容**:
```markdown
## 10. セキュリティとバリデーション

### 10.1 APIキー認証

**実装**: `verify_api_key()` 依存関数（FastAPI Depends）

**仕様**:
- リクエストヘッダー `x-api-key` の値を環境変数 `API_KEY` と照合
- 不一致の場合は 401 Unauthorized を返す

**設定**:
```bash
# .env
API_KEY=your-secret-api-key-here
```

---

### 10.2 デバイスID検証

**実装**: iOS/watchOS アプリ側で `UserDefaults` にデバイスIDを永続化

**生成ロジック**:
```swift
static func getDeviceId() -> String {
    if let saved = UserDefaults.standard.string(forKey: "remote_prompt_device_id") {
        return saved
    }
    let newId = UUID().uuidString
    UserDefaults.standard.set(newId, forKey: "remote_prompt_device_id")
    return newId
}
```

**セキュリティ考慮**:
- アプリ削除・再インストール時は新規デバイスIDが生成される
- サーバー側では `device_id` による所有権確認を実施（ルーム更新・削除時）

---

### 10.3 ワークスペース信頼モデル (v3.0新設)

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
   - バリデーション失敗時は 400 Bad Request を返す

2. **session_manager.py の execute_job()**
   - `cwd` パラメータに `workspace_path` を設定
   - `Path.resolve()` でシンボリックリンク攻撃を防止

#### 10.3.4 監査ログ（将来実装）

**要件**:
- ワークスペースパスのバリデーション結果をログに記録
- 不正なパスへのアクセス試行を検知・アラート

**実装例**:
```python
import logging

LOGGER = logging.getLogger(__name__)

def validate_workspace_path(path: str) -> str:
    if not is_safe_workspace_path(path):
        LOGGER.warning("Invalid workspace path attempted: %s", path)
        raise ValueError(f"Invalid workspace path: {path}")
    LOGGER.info("Validated workspace path: %s", path)
    return path
```

#### 10.3.5 設定手順

1. **ALLOWED_BASE_PATHS の設定**
   - `utils/path_validator.py` の `ALLOWED_BASE_PATHS` を環境に合わせて変更
   - 例: `/Users/<username>/Projects`, `/Users/<username>/Documents`

2. **rooms.workspace_path の整合性チェック**
   - 既存ルームの `workspace_path` が `ALLOWED_BASE_PATHS` 内に存在するか確認
   - データベースマイグレーション時にバリデーション実施を推奨

3. **テスト**
   - 禁止パス（`/System`, `/etc`）へのアクセスが拒否されるか確認
   - 許可ベースパス内の正常なパスが受け入れられるか確認
```

---

## Phase 7: §11 データ移行とバージョン管理 (新章)

### ☐ 7.1 §11 新設

**追加箇所**: §10 の後に新章として追加

**内容**:
```markdown
## 11. データ移行とバージョン管理

### 11.1 v2.0 → v3.0 移行手順

#### 11.1.1 データベーススキーマ変更

**手順**:

1. **rooms テーブル作成**
   ```bash
   cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
   source .venv/bin/activate
   python init_db.py
   ```

2. **Default Room 挿入**
   - 既存の `trusted_directory` を持つデフォルトルームを作成
   - `create_default_room.py` スクリプトを使用

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
           existing = db.query(Room).filter_by(device_id=device_id, name=name).first()
           if existing:
               print(f"✅ Room '{name}' already exists")
               return existing.id

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
           db.refresh(room)
           print(f"✅ Created default room: {room.id}")
           return room.id
       finally:
           db.close()

   if __name__ == "__main__":
       DEVICE_ID = "iphone-test-1"
       room_id = create_default_room(DEVICE_ID)
       print(f"ℹ️  Use this room_id in API requests: {room_id}")
   ```

3. **既存 device_sessions レコードに room_id 追加**
   ```sql
   -- 手動SQL（必要に応じて）
   UPDATE device_sessions
   SET room_id = '<default_room_id>'
   WHERE room_id IS NULL;
   ```

4. **既存 jobs レコードに room_id 追加**
   ```sql
   UPDATE jobs
   SET room_id = '<default_room_id>'
   WHERE room_id IS NULL;
   ```

#### 11.1.2 API・iOSアプリのロールアウト戦略

**段階1: サーバー側デプロイ (v3.0互換モード)**
- `room_id` が未指定の場合はデフォルトルームを使用
- v2.0クライアントとの互換性を維持

**段階2: iOSアプリ更新 (v3.0対応)**
- Room選択UI追加
- `POST /jobs` リクエストに `room_id` を必須化

**段階3: v2.0互換モード廃止**
- サーバー側で `room_id` 必須チェックを有効化

#### 11.1.3 ダウンタイム

**要否**: 不要

**理由**:
- データベーススキーマ変更は既存テーブルに新カラム追加のみ
- デフォルト値を設定することで既存データとの互換性を維持
- API・iOSアプリは段階的ロールアウトで対応

---

### 11.2 後方互換性維持戦略

#### 11.2.1 v2.0クライアント対応

**実装方針**:
- `POST /jobs` エンドポイントで `room_id` が未指定の場合、デフォルトルームを使用
- `device_id` からデフォルトルームを検索し、存在しない場合は自動作成

**実装例**:
```python
@app.post("/jobs")
def create_job(req: CreateJobRequest, ...):
    room_id = req.room_id

    # v2.0互換: room_idが未指定の場合はデフォルトルーム使用
    if not room_id:
        room = db.query(Room).filter_by(
            device_id=req.device_id,
            name="Default"
        ).first()

        if not room:
            # デフォルトルーム自動作成
            room = Room(
                id=str(uuid.uuid4()),
                name="Default",
                workspace_path="/Users/macstudio/workspace",
                device_id=req.device_id,
                icon="folder",
            )
            db.add(room)
            db.commit()

        room_id = room.id

    # 以降は通常処理
    ...
```

#### 11.2.2 廃止スケジュール

| バージョン | リリース予定 | v2.0互換モード | 備考 |
|-----------|-------------|---------------|------|
| v3.0 | 2025-11-19 | ✅ 有効 | デフォルトルーム自動作成 |
| v3.1 | 2025-12-01 | ⚠️ 非推奨警告 | ログに警告メッセージ出力 |
| v4.0 | 2026-01-01 | ❌ 廃止 | room_id 必須化 |
```

---

## Phase 8: 全体検証とドキュメント整合性チェック

### ☐ 8.1 変更箇所の脚注確認

**チェック項目**:
- [ ] 3章、5章、6章、8章の該当箇所に "(v3.0で更新)" 脚注が付いているか
- [ ] 新設セクション（6.4, 6.5, 6.6, 10.3, §11）のヘッダーに "(v3.0新設)" が付いているか

### ☐ 8.2 コード例の整合性確認

**チェック項目**:
- [ ] Pythonコード例がPEP 8準拠か
- [ ] SwiftUIコード例が最新構文（async/await, @MainActor）か
- [ ] SQLスキーマ定義が `models.py` の実装と一致しているか

### ☐ 8.3 リンク・相互参照の確認

**チェック項目**:
- [ ] 目次のアンカーリンクが正しいか
- [ ] §11.1.1 のスクリプト例が実際の `create_default_room.py` と一致しているか
- [ ] §10.3.2 のコード例が実際の `utils/path_validator.py` と一致しているか

### ☐ 8.4 ファイルサイズ確認

**制約**: CLAUDE.md の「1ファイル500〜800行以内」ルール

**現状**: Master_Specification.md は約2000行

**対応**:
- v3.0更新後は約2500行になると予想
- 将来的にファイル分割を検討（§10, §11を別ファイルに）

---

## 完了条件

### Phase 1-7 の全チェックボックスが完了
### Phase 8 の全検証項目がクリア
### Codex または Claude Code によるレビュー実施

---

## 次のステップ

1. **Phase 1-2**: ヘッダー・目次の更新（5分）
2. **Phase 3**: データベース設計の更新（15分）
3. **Phase 4**: REST API仕様の拡張（30分）
4. **Phase 5**: iOS App Design の拡張（30分）
5. **Phase 6**: セキュリティとバリデーション新章（20分）
6. **Phase 7**: データ移行とバージョン管理新章（20分）
7. **Phase 8**: 全体検証（15分）

**合計推定時間**: 約2時間15分

---

## 備考

- 実装中に不明点があれば Codex に相談
- 各 Phase 完了後に進捗を報告
- MASTER_SPEC 更新完了後、iOS実装（RoomStore, RoomListView等）に進む
