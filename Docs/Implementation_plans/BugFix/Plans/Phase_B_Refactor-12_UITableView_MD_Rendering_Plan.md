# Phase B Refactor-12: UIKitベース Chat UI + Markdown/Code 表示計画 (チェックシート)
作成日: 2025-11-24
目的: SwiftUI StackLayout起因のフリーズを解消するため、チャット一覧を UIKit (UITableView/UICollectionView) に置き換え、セル再利用によるメインスレッド負荷軽減と Markdown/コードの視認性向上を両立する。

## ゴール/完了条件
- 通常・長文送信でメインスレッドフリーズ/ジェスチャタイムアウトが発生しない。
- メッセージ一覧はセル再利用を行い、スクロール・再レイアウトが滑らか。
- Markdownパラグラフ/コードブロック/インラインコード/リストが正しく表示される。
- 100KB×10連投でもUI応答を維持し、Jetsamなし。

## 技術方針（改訂）
- UIフレームワーク: UIKit UITableView（シンプル・高速）、必要に応じてUICollectionViewへ拡張。
- ホスティング: SwiftUI上にUIViewRepresentableで埋め込み、feature flagでSwiftUI版に戻せる。
- Markdown: 基本は `AttributedString(markdown:)`。100KB級で遅ければ段階的レンダリング (BG変換→Main反映) に切替。シンタックスハイライトは後段オプトイン。
- セル: User/Assistant 2種。テキスト主体。長文は折りたたみ表示可。
- 高さ: automaticDimension。estimatedRowHeight は文字数で可変（短文/中/長）。

## フェーズとチェックリスト（改訂版）
### Phase 0 準備
- [x] 影響範囲確認・feature flag で切替設計（SwiftUI版は保持）。
- [ ] dSYM/シンボル解決設定確認（Debug Information Format = DWARF with dSYM）。

### Phase 1 UIKitホスト準備
- [x] `ChatListContainerView` (UIView) を新規作成：UITableView を内包。
- [x] SwiftUI `ChatListRepresentable` (UIViewRepresentable) を用意し、ViewModelから配列を受け取れるようにする。
- [x] Feature flag `USE_UIKIT_CHAT_LIST` で切替（デフォルトON）。

### Phase 2 DataSource/Delegate 実装（標準DataSource）
- [x] セルID定義（user/assistant）。
- [x] 再利用登録、automaticDimension 有効化。
- [ ] 追加は insertRows、更新は reloadRows 部分更新（diffableは採用しない、必要なら後から）。
- [x] estimatedRowHeight を短文/長文で可変（例: <1k文字:80, <10k:300, それ以上:1000）。

### Phase 3 Markdown/Code 対応（分割）
#### Phase 3-A 基本Markdown + 性能計測
- [x] `AttributedString(markdown:)` で見出し/リスト/リンクを表示（暫定実装済み）。
- [ ] 100KB Markdown 変換時間を計測（目標 <50ms）。超過なら Phase 3-A' にフォールバック。
#### Phase 3-A' 段階的レンダリング（必要時）
- [ ] 10KBチャンクに分割しBGで変換→Mainで反映。
#### Phase 3-B コードブロック装飾
- [ ] ``` ブロック検出、等幅フォント＋淡灰背景＋角丸。
- [ ] シンタックスハイライトは後続フェーズ（Highlightr等はオプトイン）。
#### Phase 3-C UITextView 最適化
- [ ] isEditable=false, isSelectable=true, isScrollEnabled=false。
- [ ] textContainerInset=.zero, lineFragmentPadding=0, delaysContentTouches=false。
- [ ] タップ/スクロール干渉を実機で確認。

### Phase 4 SwiftUI への組み込み
- [ ] ChatView の一覧部分を `ChatListRepresentable` に置換（flagで切替）。
- [ ] オートスクロールは明示トリガのみ（送信完了時に必要なら）。

### Phase 5 パフォーマンス調整
- [ ] rowHeight=automatic, estimatedRowHeightを上記ルールで可変設定。
- [ ] prefetchDataSource 無効化。
- [ ] 表示は最新50件まで、古い履歴はページング取得。
- [ ] 長文は最初の1000文字＋「続きを読む」折りたたみで高さ計算を抑制。

### Phase 6 テスト
- [ ] 通常文(≤2KB)×10送信：フリーズなし。
- [ ] 100KB×10送信（デバッグボタン）: UI応答維持・Jetsamなし。
- [ ] Markdown表示（見出し/リスト/リンク/インラインコード/コードブロック）。
- [ ] オートスクロールON/OFFの挙動確認。

### Phase 7 フラグ/ロールアウト
- [ ] `USE_UIKIT_CHAT_LIST` でデフォルトON、問題時に即座にSwiftUI版へ戻せること。

## リスクと緩和（改訂）
- AttributedString(markdown:) 性能劣化
  - 100KB変換が50ms超なら段階的レンダリング（Phase 3-A'）へ切替。
  - さらに遅い場合は swift-markdown AST 直組み立てにフォールバック。
- UITextView のタップ/スクロール干渉
  - isEditable=false, isSelectable=true, isScrollEnabled=false, inset/paddingゼロ。問題時は isSelectable=false ＋長押しメニューに変更。
- Diffable の差分計算コスト
  - 今回は標準DataSourceで部分更新。必要時のみ diffable（animatingDifferences=false）。

## 工数目安（再見積）
- Phase 0: 0.5h
- Phase 1: 2h
- Phase 2: 2h
- Phase 3-A/B/C: 5.5h
- Phase 4: 2h
- Phase 5: 1.5h
- Phase 6: 2h
- Phase 7: 0.5h
- **合計: 約16h**（シンタックスハイライト導入時は +1h）

## 完了条件
- UIKit版がデフォルトで動作し、SwiftUI版に戻すスイッチが生きている。
- 100KB×10連投でもメインスレッドフリーズなし、Jetsamなし。
- Markdown/コード表示が視認性よく崩れない。
