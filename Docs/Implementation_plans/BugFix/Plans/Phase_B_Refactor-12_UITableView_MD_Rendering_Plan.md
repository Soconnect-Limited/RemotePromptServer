# Phase B Refactor-12: UIKitベース Chat UI + Markdown/Code 表示計画 (チェックシート)
作成日: 2025-11-24
更新日: 2025-11-24 (SwiftUI版削除に伴う計画改訂)
目的: SwiftUI StackLayout起因のフリーズを解消するため、チャット一覧を UIKit (UITableView) に完全移行し、セル再利用によるメインスレッド負荷軽減と Markdown/コードの視認性向上を両立する。

## ゴール/完了条件
- 通常・長文送信でメインスレッドフリーズ/ジェスチャタイムアウトが発生しない。
- メッセージ一覧はセル再利用を行い、スクロール・再レイアウトが滑らか。
- Markdownパラグラフ/コードブロック/インラインコード/リストが正しく表示される。
- 100KB×10連投でもUI応答を維持し、Jetsamなし。

## 技術方針（改訂）
- UIフレームワーク: UIKit UITableView（シンプル・高速）に完全移行。SwiftUI版は削除済み。
- ホスティング: SwiftUI上にUIViewRepresentableで埋め込み。
- Markdown: 基本は `AttributedString(markdown:)`。100KB級で遅ければ段階的レンダリング (BG変換→Main反映) に切替。シンタックスハイライトは後段オプトイン。
- セル: User/Assistant 2種。テキスト主体。長文は折りたたみ表示可。
- 高さ: automaticDimension。estimatedRowHeight は文字数で可変（短文/中/長）。

## フェーズとチェックリスト（改訂版）
### Phase 0 準備
- [x] 影響範囲確認（SwiftUI版削除、UIKit版に完全移行）。
- [x] dSYM/シンボル解決設定確認（Debug Information Format = DWARF with dSYM）。
  - Debug/Release両方で `dwarf-with-dsym` に設定完了

### Phase 1 UIKitホスト準備
- [x] `ChatListContainerView` (UIView) を新規作成：UITableView を内包。
- [x] SwiftUI `ChatListRepresentable` (UIViewRepresentable) を用意し、ViewModelから配列を受け取れるようにする。
- [x] ChatView から SwiftUI版コード削除、UIKit版のみに簡素化。
- [x] MessageBubble.swift、FeatureFlags.swift 削除。

### Phase 2 DataSource/Delegate 実装（標準DataSource）
- [x] セルID定義（user/assistant）。
- [x] 再利用登録、automaticDimension 有効化。
- [x] estimatedRowHeight を短文/長文で可変（例: <1k文字:80, <10k:300, それ以上:1000）。
- [x] 推論中インジケーター（UIActivityIndicatorView + "応答を生成中..."）実装。
- [x] 追加は insertRows、更新は reloadRows 部分更新（diffableは採用しない、必要なら後から）。
  - 通常メッセージ送信での部分更新動作確認済み
  - 推論中のリアルタイム更新（reloadRows）確認済み

### Phase 3 Markdown/Code 対応（分割）
#### Phase 3-A 基本Markdown + 性能計測
- [x] `AttributedString(markdown:)` で見出し/リスト/リンクを表示（暫定実装済み）。
- [ ] 100KB Markdown 変換時間を計測（目標 <50ms）。超過なら Phase 3-A' にフォールバック。
#### Phase 3-A' 段階的レンダリング（必要時）
- [ ] 10KBチャンクに分割しBGで変換→Mainで反映。
#### Phase 3-B コードブロック装飾
- [x] ``` ブロック検出、等幅フォント＋淡灰背景（暫定実装済み）。
- [ ] シンタックスハイライトは後続フェーズ（Highlightr等はオプトイン）。
#### Phase 3-C UITextView 最適化
- [x] isEditable=false, isSelectable=true, isScrollEnabled=false（実装済み）。
- [x] textContainerInset設定、lineFragmentPadding=0, delaysContentTouches=false（実装済み）。
- [ ] タップ/スクロール干渉を実機で確認。

### Phase 4 パフォーマンス調整
- [x] rowHeight=automatic, estimatedRowHeightを可変設定（実装済み）。
- [ ] prefetchDataSource 無効化。
- [ ] 表示は最新50件まで、古い履歴はページング取得。
- [ ] 長文は最初の1000文字＋「続きを読む」折りたたみで高さ計算を抑制。

### Phase 5 テスト
- [ ] 通常文(≤2KB)×10送信：フリーズなし。
- [x] 100KB×10送信（デバッグボタン）: UI応答維持・Jetsamなし。
  - ピークメモリ: 397.9MB、クリーンアップ後: 97MB
  - CPU使用率: 0%付近で安定
  - スクロール: カクつきなし
  - UI応答: 送信ボタン即座に反応
- [ ] Markdown表示（見出し/リスト/リンク/インラインコード/コードブロック）。
- [ ] ダークモード/ライトモードでの表示確認。
- [x] 推論中インジケーターの動作確認。

## リスクと緩和（改訂）
- AttributedString(markdown:) 性能劣化
  - 100KB変換が50ms超なら段階的レンダリング（Phase 3-A'）へ切替。
  - さらに遅い場合は swift-markdown AST 直組み立てにフォールバック。
- UITextView のタップ/スクロール干渉
  - isEditable=false, isSelectable=true, isScrollEnabled=false, inset/padding設定済み。問題時は isSelectable=false ＋長押しメニューに変更。
- Diffable の差分計算コスト
  - 今回は標準DataSourceで部分更新。必要時のみ diffable（animatingDifferences=false）。

## 工数目安（再見積）
- Phase 0: 0.5h (完了)
- Phase 1: 2h (完了)
- Phase 2: 2h (完了)
- Phase 3-A/B/C: 5.5h (一部完了、性能計測・最適化残)
- Phase 4: 1.5h (prefetch無効化・ページング・折りたたみ残)
- Phase 5: 2h (テスト)
- **合計: 約13.5h**（シンタックスハイライト導入時は +1h）

## 完了条件
- UIKit版で動作し、SwiftUI版コードは完全削除済み。
- 100KB×10連投でもメインスレッドフリーズなし、Jetsamなし。
- Markdown/コード表示が視認性よく崩れない。
- ダークモード/ライトモードで適切に表示される。
