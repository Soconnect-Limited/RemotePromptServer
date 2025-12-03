# AI Provider Selection 実装計画

## 概要
サーバー設定画面にAIプロバイダー（Claude Code, Codex, Gemini）の選択機能を追加し、
チャット画面での表示順序を変更できるようにする。

## 要件
1. AIプロバイダーの選択肢: Claude Code, Codex, Gemini の3種類
2. Gemini用のBashパス設定項目
3. AIプロバイダーの表示順序をドラッグで並べ替え可能
4. チャット画面のタブ表示順序に反映

## 実装項目チェックリスト

### Phase 1: モデル定義
- [x] `AIProvider` enum 作成（claude, codex, gemini）
- [x] `AIProviderConfiguration` struct 作成（プロバイダー設定）
- [x] `ServerConfiguration` に AI設定プロパティ追加

### Phase 2: 設定ストア拡張
- [x] `ServerConfigurationStore` に AI設定の保存/読み込み追加（既存の永続化を活用）
- [x] UserDefaults / Keychain での永続化対応（ServerConfiguration経由）

### Phase 3: UI実装
- [x] `AIProviderRow` コンポーネント新規作成
  - [x] プロバイダー一覧表示
  - [x] ドラッグ＆ドロップ並べ替え（EditButton連携）
  - [x] Gemini Bashパス設定フィールド
- [x] `ServerSettingsView` に AI設定セクション追加

### Phase 4: RunnerTab拡張
- [x] `RoomDetailView.RunnerTab` を削除し、`AIProvider` を直接使用
- [x] 設定された順序でタブ表示（enabledProviders活用）
- [x] 無効化されたプロバイダーは非表示

### Phase 5: テスト・ドキュメント
- [x] 起動テスト（Xcodeビルド成功）
- [x] `Master_Specification.md` 更新（v4.5として記載）

## データ構造

```swift
// AIプロバイダー定義
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }
    var displayName: String { ... }
    var systemImage: String { ... }
}

// プロバイダー設定
struct AIProviderConfiguration: Codable, Identifiable {
    let provider: AIProvider
    var isEnabled: Bool
    var bashPath: String?  // Gemini用
    var sortOrder: Int
}

// ServerConfiguration拡張
struct ServerConfiguration {
    // 既存プロパティ...
    var aiProviders: [AIProviderConfiguration]
}
```

## UI設計

### サーバー設定画面
```
[サーバー設定]
├── 自動検出
├── サーバー情報
├── 代替URL
├── 認証
├── AI設定 ← 新規追加
│   ├── Claude Code [✓] ≡
│   ├── Codex [✓] ≡
│   └── Gemini [✓] ≡
│       └── Bashパス: /path/to/gemini
├── 接続状態
├── 証明書情報
└── 詳細設定
```

### チャット画面タブ
```
[ Claude Code | Codex | Gemini ]
           ↓ 並べ替え後
[ Gemini | Claude Code | Codex ]
```

## 影響範囲
- `ServerConfiguration.swift`: モデル拡張
- `ServerConfigurationStore.swift`: 永続化対応
- `ServerSettingsView.swift`: UI追加
- `ServerSettingsViewModel.swift`: ロジック追加
- `RoomDetailView.swift`: タブ拡張
- `Master_Specification.md`: ドキュメント更新
