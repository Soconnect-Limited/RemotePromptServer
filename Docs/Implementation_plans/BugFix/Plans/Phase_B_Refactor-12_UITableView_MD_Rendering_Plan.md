# Phase B Refactor-12: UIKitベース Chat UI + Markdown/Code 表示計画 (チェックシート)
作成日: 2025-11-24
目的: SwiftUI StackLayout起因のフリーズを解消するため、チャット一覧を UIKit (UITableView/UICollectionView) に置き換え、セル再利用によるメインスレッド負荷軽減と Markdown/コードの視認性向上を両立する。

## ゴール/完了条件
- 通常・長文送信でメインスレッドフリーズ/ジェスチャタイムアウトが発生しない。
- メッセージ一覧はセル再利用を行い、スクロール・再レイアウトが滑らか。
- Markdownパラグラフ/コードブロック/インラインコード/リストが正しく表示される。
- 100KB×10連投でもUI応答を維持し、Jetsamなし。

## 技術方針
- UIフレームワーク: UIKit UITableView（シンプル・高速）、必要なら UICollectionView compositional へ拡張可能。
- ホスティング: SwiftUI画面上に UIViewRepresentable で埋め込み。
- Markdownレンダリング: `AttributedString(markdown:)` (iOS 15+) を基本とし、コードブロックは等幅フォント＋背景色。必要に応じて SyntaxHighlighter (Highlightr など) をオプトイン。依存追加は後段で検討。
- セル種別: User/Assistant 2種。画像なし、テキスト主体。必要なら後で attachment 対応。
- セル高さ: UITableView.automaticDimension + 先読みを抑制（estimatedRowHeight を控えめに設定）。

## フェーズとチェックリスト
### Phase 0 準備
- [ ] 影響範囲確認・既存 SwiftUI チャットビューの保持方法を決める（feature flag で切替）。
- [ ] 依存追加が必要か判断（Highlightr等は後回し）。

### Phase 1 UIKitホスト準備
- [ ] `ChatListContainerView` (UIView) を新規作成：UITableView を内包。
- [ ] SwiftUI `ChatListRepresentable` (UIViewRepresentable) で SwiftUI から利用可能にする。
- [ ] DI: ViewModel からメッセージ配列を渡す API（bind または data source 注入）。

### Phase 2 DataSource/Delegate 実装
- [ ] `ChatTableDataSource`: diffable data source または標準 data source（今回単純なので標準でも可）。
- [ ] セルID定義（user/assistant）。
- [ ] セル再利用登録と高さ自動計算を有効化。
- [ ] メッセージ更新時に `reloadData` ではなく差分適用（`reloadSections` or diffable）。

### Phase 3 セル実装 (Markdown/Code対応)
- [ ] BaseCell: 共通レイアウト（UILabelまたは UITextView で Markdown 表示）。
- [ ] Markdown変換: `AttributedString(markdown:)` を使い、段落/リスト/リンクをサポート。
- [ ] コードブロック: モノスペースフォント＋淡色背景＋角丸。インラインコードは背景付き。
- [ ] 行間・余白を最小限に調整し、レイアウト計算を簡素化。
- [ ] アクセシビリティ識別子付与（UIテスト用）。

### Phase 4 SwiftUI への組み込み
- [ ] 既存 `ChatView` のメッセージ一覧部を `ChatListRepresentable` に置き換え（feature flag）。
- [ ] スクロール維持/最下部スクロールは必要時のみ（送信完了時に明示スクロール）。
- [ ] オートスクロールはトグルで制御。

### Phase 5 パフォーマンス調整
- [ ] `rowHeight = automatic`, `estimatedRowHeight = 120` など控えめ設定。
- [ ] `prefetchDataSource` 無効化（長文では逆効果の場合）。
- [ ] メッセージ保持は最新50件までをテーブルに反映、古い履歴はページング読み込み。

### Phase 6 テスト
- [ ] 通常文(〜2KB)×10送信でフリーズなし。
- [ ] 100KB×10送信（デバッグボタン）でUI応答維持、Jetsamなし。
- [ ] Markdown表示確認：見出し/リスト/リンク/インラインコード/コードブロック。
- [ ] 自動スクロールON/OFFの動作確認。

### Phase 7 フラグ/ロールアウト
- [ ] Feature flag: `USE_UIKIT_CHAT_LIST`（UserDefaultsまたはビルド設定）。
- [ ] デフォルト: UIKit版を有効、問題が出たら SwiftUI 版へ即時戻せるよう保持。

## リスクと緩和
- リスク: AttributedString(markdown:) のパフォーマンスが不十分 → 部分的にテキスト分割して簡易レンダリングにフォールバック。
- リスク: セル内UITextViewがタップを奪う → `isSelectable=false` + `textContainerInset`最小化で回避。
- リスク: Diffable で大量差分時にコスト増 → セクション単位reloadへ切替可能な実装に。

## 工数目安
- Phase 1-2: 2.5h
- Phase 3: 3h（Markdown装飾含む）
- Phase 4-5: 2h
- Phase 6: 2h
- 合計: 約9.5h（Highlightr等を入れる場合＋1h）

## 完了条件
- UIKit版がデフォルトで動作し、SwiftUI版に戻すスイッチが生きている。
- 100KB×10連投でもメインスレッドフリーズなし、Jetsamなし。
- Markdown/コード表示が視認性よく崩れない。
