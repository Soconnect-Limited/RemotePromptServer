# 実装計画: ファイルブラウザ & Markdownエディタ機能

**作成日**: 2025-11-20
**バージョン**: 2.1（レビュー2反映版）
**対象**: RemotePrompt iOS/WatchOS アプリ
**最低対応iOS**: iOS 18.0+（要確認：Master_Specification.mdとの整合性）

---

## 📋 要件サマリー

### 削除機能
- [ ] RoomDetailView右上の履歴削除ボタン（Claude/Codex）を削除

### 追加機能
- [ ] ファイルブラウザ機能（RoomDetailView右上ツールバー）
  - [ ] ルームのworkspace_path以下のディレクトリ・.mdファイルを表示
  - [ ] ディレクトリをタップ → 下階層へ移動
  - [ ] .mdファイルをタップ → 編集可能なViewで表示
  - [ ] Markdownテキストにシンタックスハイライト（VSCode風）

---

## 🎯 目標

1. **ユーザビリティ向上**: チャット履歴を残しつつ、プロジェクトファイルへ直接アクセス可能に
2. **開発効率向上**: iPhone/Apple WatchからMarkdownファイルを編集可能に
3. **一貫性**: 既存のUI/UXデザインと統一

---

## 📊 影響範囲分析

| レイヤー | 影響範囲 | 複雑度 | 推定工数 |
|---------|---------|-------|---------|
| **iOS UI** | RoomDetailView、新規ファイルブラウザView、新規エディタView、新規シンタックスハイライトView、**watchOS UI対応** | 高 | 7-9h |
| **iOS Models** | FileItem、FileError | 中 | 2-3h |
| **iOS Services** | FileService (API呼び出し・エラーハンドリング)、MarkdownHighlighter | 中 | 3-4h |
| **サーバーAPI** | GET /files、GET /files/*filepath、PUT /files/*filepath、認証・認可ヘルパー | 高 | 5-6h |
| **サーバーDB** | なし（ファイルシステム直接アクセス） | 低 | 0h |
| **セキュリティ** | 二重デコード対策、OS区切り文字正規化、Workspace Trust Model適用 | 高 | 3-4h |
| **テスト** | 単体テスト、統合テスト、手動テスト（iOS + watchOS） | 高 | 4-5h |

**合計推定工数**: 24-31時間

---

## 🏗️ アーキテクチャ設計

### コンポーネント構成

```
RoomDetailView
├── ChatView (既存)
└── FileBrowserView (新規) ← 右上ツールバーボタンからsheet表示
    ├── DirectoryListView (ディレクトリ一覧)
    │   └── FileRow (ファイル/フォルダ行)
    └── MarkdownEditorView (新規) ← .mdファイルタップ時にNavigationLink
        └── SyntaxHighlightedTextEditor (新規)
```

### データフロー

```
iOS App ──GET /files?path={path}──> Server
         <──JSON: [{name, type, path}]─

iOS App ──GET /files/{encoded_path}──> Server
         <──text/plain: file content───

iOS App ──PUT /files/{encoded_path}──> Server
         body: new content
         <──200 OK / 400 Error──────────
```

---

## 🔧 技術選定

### シンタックスハイライト
**選択肢**:
1. ✅ **自作（推奨）**: Markdownの限定的なハイライト（見出し、リスト、コードブロック、太字、リンク）
2. ❌ Highlightr（サードパーティ）: 依存関係増加、ライセンス確認必要
3. ❌ TextKit2: iOS 15+必要、実装複雑

**決定**: 自作（シンプルで軽量、Markdown専用）

### UIコンポーネント
- **ファイルブラウザ**: `List` + `NavigationStack` (iOS 18.0+)
- **エディタ**: `TextEditor` + カスタムシンタックスハイライト overlay

---

## 🔐 セキュリティ仕様（Master_Specification v3.0準拠）

### 認証・認可モデル
- **認証**: `device_id` (既存のdevicesテーブル)
- **認可**: `rooms.device_id` との一致確認 (room所有権)
- **Workspace Trust Model適用**: `workspace_path` はホワイトリスト検証済み（TRUSTED_BASE_DIRECTORIES）

### パストラバーサル対策（強化版）
```python
from pathlib import Path
from urllib.parse import unquote

def validate_file_path(workspace_path: str, relative_path: str) -> Path:
    """
    二重デコード・OS区切り文字混在に対応したパス検証

    Args:
        workspace_path: ルームのworkspace_path（ホワイトリスト検証済み）
        relative_path: ユーザー指定の相対パス（URLデコード前）

    Returns:
        検証済みの絶対Path

    Raises:
        ValueError: 不正なパス
    """
    # 1. URLデコード（二重エンコード対策で2回実施）
    decoded = unquote(unquote(relative_path))

    # 2. Windowsパス区切り文字を正規化
    normalized = decoded.replace('\\', '/')

    # 3. 絶対パス化
    base = Path(workspace_path).resolve()
    target = (base / normalized).resolve()

    # 4. workspace配下にあるか確認
    try:
        target.relative_to(base)
    except ValueError:
        raise ValueError(f"Path traversal detected: {relative_path}")

    return target
```

### ファイルサイズ制限
- **上限**: 500KB（.mdファイル）
- **サーバー挙動**: 500KB超過時は `413 Payload Too Large` を返却
- **クライアント挙動**: 読込時に500KB超過を検知したらアラート表示、編集不可

### バックアップ戦略
- **方式**: 1世代上書き `.bak` ファイル
- **保存場所**: 同一ディレクトリ（`file.md` → `file.md.bak`）
- **ローテーション**: 保存時に既存 `.bak` を削除 → 現行ファイルを `.bak` にリネーム → 新内容を保存
- **パーミッション**: 元ファイルと同じ権限を継承

### 監査ログ（オプション・Phase 1では未実装）
将来的に以下をログ記録：
- ファイルアクセス（read/write）
- device_id、room_id、file_path、タイムスタンプ

---

## 🌐 REST API 仕様（詳細版）

### API エンドポイント一覧

| メソッド | パス | 説明 | 認証 |
|---------|------|------|------|
| GET | `/rooms/{room_id}/files` | ディレクトリ一覧取得 | device_id (query) |
| GET | `/rooms/{room_id}/files/*filepath` | ファイル内容取得 | device_id (query) |
| PUT | `/rooms/{room_id}/files/*filepath` | ファイル保存 | device_id (query) |

### パスエンコーディング方式

**課題**: `/files/{file_path}` でスラッシュを含む相対パスを直接URLに載せると、フレームワークがパス分割して誤解釈

**解決策**: ワイルドカードキャプチャ + URLエンコード

**FastAPI実装例**:
```python
@app.get("/rooms/{room_id}/files/{filepath:path}")
async def get_file(room_id: str, filepath: str, device_id: str = Query(...)):
    """
    ファイル内容を取得

    filepath: URLエンコード済み相対パス（例: "Docs%2FREADME.md"）
    """
    # validate_file_path内でURLデコード実施
    pass
```

**クライアント実装例（Swift）**:
```swift
// "Docs/README.md" → "Docs%2FREADME.md"
// 重要: .urlPathAllowed は / をエンコードしないため、/ を除外した文字セットを使用
var allowedCharacters = CharacterSet.urlPathAllowed
allowedCharacters.remove(charactersIn: "/")
let encoded = filepath.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? filepath
let url = "\(baseURL)/rooms/\(roomId)/files/\(encoded)?device_id=\(deviceId)"

// または簡潔に:
// let encoded = filepath.replacingOccurrences(of: "/", with: "%2F")
//     .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filepath
```

### エラーレスポンス仕様

| HTTPステータス | 説明 | responseBody例 |
|---------------|------|--------------|
| 200 OK | 成功 | `{"message": "File saved"}` |
| 400 Bad Request | 不正なパス・拡張子 | `{"detail": "Invalid file path"}` |
| 403 Forbidden | 認証失敗・所有権なし | `{"detail": "Room not owned by device"}` |
| 404 Not Found | ファイル/ディレクトリ不存在 | `{"detail": "File not found"}` |
| 413 Payload Too Large | ファイルサイズ超過 | `{"detail": "File exceeds 500KB limit"}` |
| 500 Internal Server Error | サーバーエラー | `{"detail": "Internal server error"}` |

### GET /rooms/{room_id}/files

**クエリパラメータ**:
- `device_id` (必須): デバイスID
- `path` (オプション): 相対パス（デフォルト: `""` = ルート）

**レスポンス例**:
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

### GET /rooms/{room_id}/files/*filepath

**クエリパラメータ**:
- `device_id` (必須)

**レスポンス**:
- Content-Type: `text/plain; charset=utf-8`
- Body: ファイル内容（プレインテキスト）

**サイズ制限**:
- 500KB超過時は `413 Payload Too Large` を返却

### PUT /rooms/{room_id}/files/*filepath

**クエリパラメータ**:
- `device_id` (必須)

**リクエストボディ**:
- Content-Type: `text/plain; charset=utf-8`
- Body: 新しいファイル内容

**バリデーション**:
- ファイルサイズ500KB以下
- `.md` 拡張子のみ
- workspace配下のパス

**レスポンス例**:
```json
{
  "message": "File saved",
  "path": "Docs/README.md",
  "size": 5432,
  "backup_created": true
}
```

---

## 📝 実装チェックリスト

### Phase 1: サーバーAPI実装 (5-6h)

#### 1.0 セキュリティ基盤実装
- [ ] `file_security.py` 作成
  - [ ] `validate_file_path(workspace_path: str, relative_path: str) -> Path`
    - [ ] 二重URLデコード（`unquote(unquote())`）
    - [ ] Windows区切り文字正規化（`\\` → `/`）
    - [ ] シンボリックリンク解決（`.resolve()`）
    - [ ] workspace配下チェック（`.relative_to()`）
  - [ ] `validate_markdown_extension(file_path: Path) -> bool`
  - [ ] `validate_file_size(file_path: Path, max_size: int = 500_000) -> bool`

#### 1.1 認証・認可ヘルパー
- [ ] `auth_helpers.py` 作成
  - [ ] `async def verify_room_ownership(room_id: str, device_id: str, db: Session) -> Room`
    - [ ] roomsテーブルから`room_id`でRoom取得
    - [ ] `room.device_id == device_id` チェック
    - [ ] 不一致時は `HTTPException(403)` raise

#### 1.2 ファイルシステム操作関数
- [ ] `file_operations.py` 作成
  - [ ] `list_files(workspace_path: str, relative_path: str) -> List[FileItemDict]`
    - [ ] `validate_file_path()` で検証
    - [ ] ディレクトリ存在確認
    - [ ] `.md` ファイルとディレクトリのみフィルタ
    - [ ] `.bak` ファイルを除外
    - [ ] FileItemDict作成（name, type, path, size, modified_at）

  - [ ] `read_file(workspace_path: str, file_path: str) -> str`
    - [ ] `validate_file_path()` で検証
    - [ ] `validate_markdown_extension()` チェック
    - [ ] `validate_file_size()` チェック（500KB）
    - [ ] UTF-8デコード（`errors='strict'`）
    - [ ] エラーハンドリング（FileNotFoundError, PermissionError, UnicodeDecodeError）

  - [ ] `write_file(workspace_path: str, file_path: str, content: str) -> WriteResult`
    - [ ] `validate_file_path()` で検証
    - [ ] `validate_markdown_extension()` チェック
    - [ ] サイズチェック（`len(content.encode('utf-8')) <= 500KB`）
    - [ ] バックアップ作成:
      - [ ] 既存 `.bak` 削除（存在する場合）
      - [ ] 現行ファイルを `.bak` にリネーム（存在する場合）
      - [ ] 元ファイルのパーミッション取得（`os.stat().st_mode`）
    - [ ] UTF-8エンコードして書き込み
    - [ ] `.bak` にパーミッション適用
    - [ ] `WriteResult(success=True, size=..., backup_created=...)` を返却

#### 1.3 REST APIエンドポイント
- [ ] `main.py` に追加
  - [ ] `GET /rooms/{room_id}/files`
    - [ ] `device_id: str = Query(...)` でdevice_id必須化
    - [ ] `path: str = Query("")` で相対パス（デフォルト: ルート）
    - [ ] `verify_room_ownership()` で認可
    - [ ] roomsテーブルから`workspace_path`取得
    - [ ] `list_files(workspace_path, path)` 呼び出し
    - [ ] JSON レスポンス

  - [ ] `GET /rooms/{room_id}/files/{filepath:path}`
    - [ ] `{filepath:path}` でワイルドカードキャプチャ
    - [ ] `device_id: str = Query(...)` でdevice_id必須化
    - [ ] `verify_room_ownership()` で認可
    - [ ] `workspace_path` 取得
    - [ ] `read_file(workspace_path, filepath)` 呼び出し
    - [ ] `Response(content=file_content, media_type="text/plain; charset=utf-8")`
    - [ ] エラー時: 404/403/413/500

  - [ ] `PUT /rooms/{room_id}/files/{filepath:path}`
    - [ ] `{filepath:path}` でワイルドカードキャプチャ
    - [ ] `device_id: str = Query(...)` でdevice_id必須化
    - [ ] `Request.body()` でボディ取得
    - [ ] UTF-8デコード
    - [ ] `verify_room_ownership()` で認可
    - [ ] `workspace_path` 取得
    - [ ] `write_file(workspace_path, filepath, content)` 呼び出し
    - [ ] JSON レスポンス: `{"message": "File saved", "path": ..., "size": ..., "backup_created": ...}`
    - [ ] エラー時: 400/403/413/500

#### 1.4 サーバーテスト
- [ ] `tests/test_file_security.py` 作成
  - [ ] パストラバーサル攻撃テスト:
    - [ ] `../../../etc/passwd`
    - [ ] `..\\..\\..\\Windows\\System32`
    - [ ] `....//....//etc/passwd` (二重エンコード)
    - [ ] URLエンコード済み攻撃（`%2e%2e%2f`）
  - [ ] 正常系テスト（workspace配下の正当なパス）

- [ ] `tests/test_file_operations.py` 作成
  - [ ] ディレクトリ一覧取得（空/階層構造/.bak除外）
  - [ ] ファイル読込（存在/不存在/500KB超過）
  - [ ] ファイル保存（新規/上書き/.bak作成）

- [ ] `tests/test_file_api.py` 作成
  - [ ] 認証失敗テスト（不正device_id）
  - [ ] 認可失敗テスト（他人のroom）
  - [ ] E2E正常系テスト（一覧→読込→保存）

---

### Phase 2: iOS Models & Services (3-4h)

#### 2.1 Models
- [ ] `FileItem.swift`
  ```swift
  struct FileItem: Identifiable, Codable {
      let id: String  // = path
      let name: String
      let type: FileType  // .directory, .markdownFile
      let path: String  // relative to workspace
      let size: Int64?
      let modifiedAt: Date

      // サーバーはsnake_case、Swiftはcamel_caseのため、CodingKeys必須
      enum CodingKeys: String, CodingKey {
          case id
          case name
          case type
          case path
          case size
          case modifiedAt = "modified_at"  // snake_case → camelCase
      }
  }

  enum FileType: String, Codable {
      case directory
      case markdownFile = "markdown_file"
  }
  ```
  - [ ] **重要**: `modifiedAt` ↔ `modified_at` のマッピングを`CodingKeys`で定義

- [ ] `FileError.swift`
  ```swift
  enum FileError: LocalizedError {
      case fileTooLarge(Int64)  // ファイルサイズ
      case invalidPath          // パストラバーサル、拡張子不正
      case unauthorized         // 認証失敗（device_id不正）
      case forbidden            // 認可失敗（room所有権なし）
      case networkError(Error)
      case serverError(Int, String)  // HTTPステータス, detail

      var errorDescription: String? {
          switch self {
          case .fileTooLarge(let size):
              return "ファイルサイズが上限（500KB）を超えています: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
          case .invalidPath:
              return "不正なファイルパスです"
          case .unauthorized:
              return "認証に失敗しました"
          case .forbidden:
              return "このルームにアクセスする権限がありません"
          case .networkError:
              return "ネットワークエラーが発生しました"
          case .serverError(let code, let detail):
              return "サーバーエラー (\(code)): \(detail)"
          }
      }
  }
  ```

#### 2.2 Services
- [ ] `FileService.swift`
  ```swift
  class FileService {
      private let apiClient: APIClient
      private let maxFileSize: Int64 = 500_000  // 500KB

      func listFiles(roomId: String, path: String) async throws -> [FileItem]
      func readFile(roomId: String, path: String) async throws -> String
      func saveFile(roomId: String, path: String, content: String) async throws

      // 事前バリデーション
      func validateFileSize(_ content: String) throws
  }
  ```
  - [ ] APIClient経由でREST API呼び出し
  - [ ] パスのURLエンコード
    - [ ] **重要**: `/` を `%2F` にエンコードするため、`.urlPathAllowed` から `/` を除外
    - [ ] 実装例: `allowedCharacters.remove(charactersIn: "/")`
  - [ ] エラーハンドリング（HTTPステータスコード → FileError）:
    - [ ] 400 → `FileError.invalidPath` (不正なパス・拡張子)
    - [ ] 401 → `FileError.unauthorized` (認証失敗、device_id不正)
    - [ ] 403 → `FileError.forbidden` (認可失敗、room所有権なし)
    - [ ] 404 → `FileError.serverError(404, detail)` (ファイル/ディレクトリ不存在)
    - [ ] 413 → `FileError.fileTooLarge(size)` (サイズ超過)
    - [ ] 500 → `FileError.serverError(500, detail)` (サーバー内部エラー)
    - [ ] ネットワークエラー → `FileError.networkError(error)`
  - [ ] 保存前にクライアント側でサイズチェック（500KB）
  - [ ] レスポンスボディから`detail`メッセージを抽出してエラーに含める

---

### Phase 3: ファイルブラウザUI (4-5h)

#### 3.1 FileBrowserView
- [ ] `FileBrowserView.swift` 作成
  - [ ] NavigationStack (iOS 18.0+)
  - [ ] 現在のパス表示（NavigationTitle）
    - [ ] 長いパスの折り返し処理（`.lineLimit(2)` + `.truncationMode(.middle)`）
  - [ ] 戻るボタン（親ディレクトリへ、ルート時は非表示）
  - [ ] ファイル/ディレクトリリスト（List）
    - [ ] 空ディレクトリ時: "このディレクトリは空です" メッセージ表示
  - [ ] ローディングインジケータ（ProgressView）
  - [ ] エラーアラート
    - [ ] 500KB超過時: "ファイルサイズが500KBを超えているため、編集できません"
    - [ ] ネットワークエラー時: リトライボタン付きアラート

#### 3.2 FileRow
- [ ] `FileRow.swift` 作成
  - [ ] アイコン（フォルダ: `folder.fill` / ドキュメント: `doc.text.fill`）
  - [ ] ファイル名（`.lineLimit(1)` + `.truncationMode(.middle)`）
  - [ ] ファイルサイズ（.mdファイルのみ、`ByteCountFormatter`で表示）
  - [ ] 更新日時（相対表示: "2時間前", "昨日", "2025/11/20"）
  - [ ] タップアクション（ディレクトリ移動 or ファイル編集）

#### 3.3 FileBrowserViewModel
- [ ] `FileBrowserViewModel.swift` 作成
  - [ ] @Published var currentPath: String
  - [ ] @Published var pathComponents: [String]  // パンくずリスト用
  - [ ] @Published var fileItems: [FileItem]
  - [ ] @Published var isLoading: Bool
  - [ ] @Published var errorMessage: String?
  - [ ] @Published var showRetry: Bool
  - [ ] func loadFiles(path: String)
  - [ ] func navigateToDirectory(path: String)
  - [ ] func navigateBack()
  - [ ] func retry()  // リトライ処理

---

### Phase 4: Markdownエディタ UI (4-5h)

#### 4.1 MarkdownEditorView
- [ ] `MarkdownEditorView.swift` 作成
  - [ ] NavigationTitle: ファイル名
  - [ ] ツールバー: 保存ボタン、キャンセルボタン
  - [ ] SyntaxHighlightedTextEditor
  - [ ] ローディングインジケータ
  - [ ] 保存成功/失敗アラート

#### 4.2 SyntaxHighlightedTextEditor
- [ ] `SyntaxHighlightedTextEditor.swift` 作成
  - [ ] TextEditor + overlay
  - [ ] シンタックスハイライトロジック（後述）
  - [ ] スクロール同期

#### 4.3 MarkdownHighlighter
- [ ] `MarkdownHighlighter.swift` 作成
  - [ ] `highlight(_ text: String) -> AttributedString`
  - [ ] 正規表現パターン:
    - [ ] 見出し (`# `, `## `, `### `)
    - [ ] リスト (`- `, `* `, `1. `)
    - [ ] コードブロック (`` ` ``, `` ``` ``)
    - [ ] 太字 (`**text**`)
    - [ ] イタリック (`*text*`)
    - [ ] リンク (`[text](url)`)
    - [ ] チェックボックス (`- [ ]`, `- [x]`)
  - [ ] カラーリング設定（VSCode風）

#### 4.4 MarkdownEditorViewModel
- [ ] `MarkdownEditorViewModel.swift` 作成
  - [ ] @Published var fileContent: String
  - [ ] @Published var originalContent: String
  - [ ] @Published var isDirty: Bool (変更検知)
  - [ ] @Published var isSaving: Bool
  - [ ] @Published var errorMessage: String?
  - [ ] func loadFile(roomId: String, path: String)
  - [ ] func saveFile(roomId: String, path: String)
  - [ ] func discardChanges()

---

### Phase 5: RoomDetailView統合 (1-2h)

#### 5.1 RoomDetailView修正
- [ ] 履歴削除ボタン削除
  - [ ] Menuコンポーネント削除
  - [ ] `clearChat()` 呼び出し削除

- [ ] ファイルブラウザボタン追加
  - [ ] ツールバー右上にボタン追加（`doc.text.magnifyingglass` アイコン）
  - [ ] `@State private var showFileBrowser = false`
  - [ ] `.sheet(isPresented: $showFileBrowser) { FileBrowserView(...) }`

---

### Phase 6: テスト & デバッグ (4-5h)

#### 6.1 サーバーテスト
- [ ] パストラバーサル攻撃テスト（`../../../etc/passwd`, 二重エンコード, Windows区切り文字）
- [ ] ファイル一覧取得テスト（空ディレクトリ、階層構造、.bak除外）
- [ ] ファイル読込テスト（存在する/しない、権限エラー、500KB超過）
- [ ] ファイル保存テスト（新規作成、上書き、.bak作成確認、パーミッション継承）

#### 6.2 iOSユニットテスト
- [ ] FileServiceテスト（モックAPI）
  - [ ] URLエンコード正常動作
  - [ ] エラーレスポンス変換（413→FileTooLarge等）
  - [ ] クライアント側サイズバリデーション
- [ ] MarkdownHighlighterテスト（正規表現パターン）
- [ ] ViewModelテスト（状態遷移、リトライ処理）

#### 6.3 統合テスト
- [ ] E2Eテスト: ルーム選択 → ファイルブラウザ → ディレクトリ移動 → .md編集 → 保存
- [ ] エラーハンドリングテスト:
  - [ ] ネットワーク切断 → リトライアラート表示確認
  - [ ] サーバーエラー → 適切なエラーメッセージ表示
  - [ ] 500KB超過 → 編集不可アラート表示

#### 6.4 手動テスト（iOS）
- [ ] iPhoneシミュレータ
  - [ ] 長いパス名の折り返し表示確認
  - [ ] 空ディレクトリメッセージ表示確認
  - [ ] ファイル名・サイズ・日時の表示確認
- [ ] 実機iPhone
  - [ ] ダークモード対応確認
  - [ ] キーボード表示時のレイアウト確認
  - [ ] 保存時のローディング表示確認

#### 6.5 手動テスト（watchOS）
- [ ] Apple Watch実機
  - [ ] RoomDetailView右上ボタン表示確認（ファイルブラウザボタン）
  - [ ] **履歴削除ボタンが削除されたことを確認**
  - [ ] ファイルブラウザ起動確認（sheet表示）
  - [ ] ファイル一覧表示確認（小画面での可読性）
  - [ ] ディレクトリ移動の動作確認
  - [ ] .mdファイル開くと編集View表示確認
  - [ ] エラー時のアラート/トースト表示確認
  - [ ] ネットワークエラー時のリトライボタン動作確認

---

### Phase 7: ドキュメント更新 (1h)

#### 7.1 仕様書更新
- [ ] `Docs/Specifications/Master_Specification.md` に追記
  - [ ] ファイルブラウザ機能
  - [ ] Markdownエディタ機能
  - [ ] REST API仕様（/files関連）

#### 7.2 README更新
- [ ] 機能説明追加
- [ ] スクリーンショット追加（オプション）

---

> **注意**: セキュリティ仕様の詳細は「🔐 セキュリティ仕様（Master_Specification v3.0準拠）」セクションを参照してください。旧バージョンの簡易的なパストラバーサル対策例は削除されました。

---

## 📐 UI/UXデザイン

### ファイルブラウザ
```
┌────────────────────────────┐
│ ← Documents         [×]    │ ← NavigationBar
├────────────────────────────┤
│ 📁 Docs                    │
│ 📁 Tests                   │
│ 📄 README.md       5.2 KB  │
│ 📄 CLAUDE.md       2.1 KB  │
└────────────────────────────┘
```

### Markdownエディタ
```
┌────────────────────────────┐
│ ← README.md     [保存] [×] │ ← NavigationBar
├────────────────────────────┤
│ # RemotePrompt             │ ← 太字・青色
│                            │
│ - Feature 1                │ ← 緑色
│ - Feature 2                │
│                            │
│ `code`                     │ ← グレー背景
└────────────────────────────┘
```

---

## 🚀 デプロイ計画

### ロールアウト順序
1. **ローカル開発環境**: Phase 1-6 完了後
2. **TestFlight**: Phase 7 完了後、内部テスター招待
3. **本番環境**: TestFlightで1週間問題なければリリース

### ロールバック計画
- サーバーAPI: 新規エンドポイントのため影響なし（既存機能は変更なし）
- iOSアプリ: 旧バージョンに戻すだけ（データベース変更なし）

---

## ⚠️ リスク & 対策

| リスク | 影響 | 確率 | 対策 | 対応Phase |
|-------|------|------|------|----------|
| シンタックスハイライトのパフォーマンス低下（大きなファイル） | 中 | 中 | ファイルサイズ制限（500KB）、遅延ハイライト | Phase 4 |
| 同時編集による競合 | 低 | 低 | `.bak` による1世代バックアップで上書き復旧可能 | Phase 1.2 |
| パストラバーサル脆弱性（二重エンコード、OS区切り文字混在） | 高 | 低 | 二重URLデコード、区切り文字正規化、厳密なパス検証、ユニットテスト | Phase 1.0 |
| .mdファイル以外への不正アクセス | 高 | 低 | 拡張子チェック、Workspace Trust Model適用 | Phase 1.0 |
| URLパラメータのパス分割（FastAPI誤解釈） | 中 | 中 | `{filepath:path}` ワイルドカードキャプチャ + URLエンコード | Phase 1.3 |
| 500KB超過ファイルの誤編集 | 中 | 低 | サーバー側413返却 + クライアント側事前バリデーション + アラート表示 | Phase 1.2, 2.2 |
| watchOS小画面での操作性低下 | 低 | 中 | 長いパス名の折り返し、空ディレクトリメッセージ、手動テストで検証 | Phase 3.1, 6.5 |
| .bak ファイルの累積・権限逸脱 | 低 | 低 | 1世代上書きルール、パーミッション継承、`.bak` を一覧から除外 | Phase 1.2 |

---

## 📚 参考資料

- [SwiftUI TextEditor Documentation](https://developer.apple.com/documentation/swiftui/texteditor)
- [AttributedString Syntax Highlighting](https://www.hackingwithswift.com/quick-start/swiftui/how-to-style-text-views-with-fonts-colors-line-spacing-and-more)
- [Markdown Syntax Guide](https://www.markdownguide.org/basic-syntax/)
- [OWASP Path Traversal](https://owasp.org/www-community/attacks/Path_Traversal)

---

## 🔄 変更履歴

| 日付 | バージョン | 変更内容 | 担当 |
|------|---------|---------|------|
| 2025-11-20 | 1.0 | 初版作成 | Claude |
| 2025-11-20 | 2.0 | レビュー1反映:<br>・API仕様詳細化（パスエンコード、エラーレスポンス、サイズ上限）<br>・セキュリティ強化（二重デコード、OS区切り文字正規化）<br>・バックアップ戦略明文化（1世代上書き、パーミッション継承）<br>・Workspace Trust Model適用<br>・watchOS影響確認タスク追加<br>・UX細目追加（長いパス折返し、空ディレクトリ表示、エラーリトライ）<br>・最低対応iOS 18.0+に明記 | Claude |
| 2025-11-20 | 2.1 | レビュー2反映（重複・矛盾の解消）:<br>・旧セキュリティ対策セクション削除（強化版に統合済み）<br>・SwiftのURLエンコード修正（`/` を `%2F` に変換する指針追加）<br>・FileError 403マッピング分離（`unauthorized`/`forbidden`）<br>・FileItem `CodingKeys` 定義追加（`modified_at` ↔ `modifiedAt`）<br>・Master_Specification.mdとのiOS対応バージョン整合性確認タスク追加 | Claude |

---

## ✅ 完了条件

- [ ] すべてのチェックリスト項目が完了
- [ ] サーバーテスト・iOSテストすべて合格（パストラバーサル、サイズ制限、バックアップ検証）
- [ ] セキュリティレビュー通過（二重デコード対策、Workspace Trust Model適用確認）
- [ ] watchOS実機テスト完了（履歴削除ボタン削除確認、ファイルブラウザ動作確認）
- [ ] ドキュメント更新完了（Master_Specification.md に REST API仕様追記）
- [ ] コードレビュー承認
- [ ] TestFlight配信完了

---

## 📌 実装開始前の確認事項

### Master_Specification.mdとの整合性チェック
- [ ] `TRUSTED_BASE_DIRECTORIES` がサーバー環境に合わせて設定されていることを確認
- [ ] `device_id` 認証フローが既存APIと同じパターンであることを確認
- [ ] `rooms.device_id` での認可が既存のRoom操作APIと一貫していることを確認
- [ ] **最低iOS/watchOS対応バージョン確認**:
  - [ ] Master_Specification.mdにiOS最低バージョンの記載があるか確認
  - [ ] 本計画の「iOS 18.0+」が要件と矛盾しないか確認（iOS 18.0未満サポート不要なら問題なし）
  - [ ] `NavigationStack` はiOS 16.0+で利用可能だが、iOS 18.0+を要件とするため問題なし

### 未定義・将来拡張項目
- **監査ログ**: Phase 1では未実装（将来的に追加予定）
- **ファイル操作範囲**: 読込・保存のみ対応。新規作成・リネーム・削除は**非対応**として明記
- **同時編集競合解決**: 保存時タイムスタンプチェックは**未実装**（.bakでのロールバックで対応）

---

**推定総工数**: 24-31時間
**推奨実装順序**: Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7
