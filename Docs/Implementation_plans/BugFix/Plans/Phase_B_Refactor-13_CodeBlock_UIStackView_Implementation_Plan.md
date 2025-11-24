# Phase B Refactor-13: コードブロック専用UI + UIStackView混在レイアウト実装計画
作成日: 2025-11-24
更新日: 2025-11-24 (rev.2 - 不整合修正)
目的: チャットメッセージ内のコードブロックを、言語名表示・コピーボタン付きの専用UIで表示し、通常テキストと混在できるUIStackViewベースのセルレイアウトを実現する。Master_Specification 8.7 Markdownレンダリング要件に準拠し、テスト網羅とフォールバック保証を含む。

## ゴール/完了条件
- Markdownコードブロック(```)が四角で囲まれた専用UIとして表示される。
- コードブロックのヘッダーに言語名（大文字）とコピーボタンが右側に配置される。
- コピーボタンをタップすると「Copied!」が1.5秒表示され、クリップボードにコード内容がコピーされる。
- 通常テキスト（段落、リスト、太字、イタリック、インラインコード）とコードブロックが混在したメッセージが正しく表示される。
- セル再利用時にprepareForReuse()で古いビュー階層がクリアされる。
- 100KB以上のメッセージ（コードブロック含む）でもフリーズなし（目標: パース処理<100ms）。
- セグメント数が20個超の場合は最初の20個のみ表示し、警告ログを出力（DoS防止）。
- 既存のMarkdownレンダリング（AttributedString生成、フォント/テーマ設定）が継続動作する。
- ユニットテスト・UIテストでコードブロックUI/コピー機能/パース性能を検証（Master_Specification 8.7準拠）。

## 技術方針
- セル構造: 単一UITextView (`textView`) → UIStackView + 複数サブビュー（UITextView + CodeBlockView）
  - **重要**: 既存の`textView`プロパティは**削除せず残す**。推論中インジケーター・展開ボタン・prepareForReuse()の既存ロジックで参照されているため、削除すると未定義参照エラー。Phase 1では`textView.isHidden = true`で非表示化し、Phase 2でcontentStackViewへの移行完了後も**削除しない**（互換性維持）。
- パース: MessageParser.parse()でMarkdownを[MessageContentSegment]に分割。
  - `.text(NSAttributedString)`: 通常テキスト → UITextView
  - `.codeBlock(code: String, language: String?)`: コードブロック → CodeBlockView
  - **セグメント上限**: parse()内で最大20セグメントに制限。超過時は最初の20個のみ返却し、警告ログ出力。
- レイアウト: UIStackView.axis = .vertical, spacing = 8, distribution = .fill
- 高さ計算: automaticDimension。estimatedRowHeightは文字数 + コードブロック数で可変（Phase 6で詳細定義）。
- 再利用: prepareForReuse()でcontentStackView.arrangedSubviewsを全削除＋removeFromSuperview()。**textViewは維持**（クリアのみ）。
- パフォーマンス:
  - MessageParser内部で100KB超の場合は計測ログ出力＋CFAbsoluteTimeGetCurrent()で計測。
  - 目標: 全体処理時間<100ms。超過時はPhase 7-Aで段階的パース。
  - 計測箇所: MessageParser.parse()の入口/出口をラップし、`print("[Phase 7] Parse time: \(ms)ms for \(segments.count) segments")`。
- Markdownレンダリング継続保証（Master_Specification 8.7準拠）:
  - MessageParser.renderText()内でAttributedString(markdown:)を呼び出し、例外時はプレーンテキストへフォールバック（try-catchでエラーハンドリング）。
  - フォント: UIFont.preferredFont(forTextStyle: .body)を維持。
  - テーマ: isUserフラグで色を切り替え（User: .white, Assistant: .label）。
  - 既存のrenderMarkdown()メソッドとの互換性: Phase 9まで両方保持し、切り替えテストを実施。

## 前提条件
- Phase B Refactor-12完了済み（UIKit UITableViewベースのチャットUI）。
- CodeBlockViewクラス作成済み（ChatListRepresentable.swift Lines 144-243）。
- MessageContentSegment enum作成済み（Lines 14-18）。
- MessageParser struct作成済み（Lines 20-142）。
- Xcodeプロジェクトに`Testing`フレームワークが導入済み（ユニットテスト用）。

## フェーズとチェックリスト

### Phase 0 準備
- [x] CodeBlockViewクラス実装確認（Lines 144-243）。
- [x] MessageParser実装確認（Lines 20-142）。
- [x] 既存renderMarkdown()の動作確認（Lines 616-715）。
- [ ] Master_Specification 8.7のテスト要件を確認。

### Phase 1 ChatMessageCell構造のUIStackView化
- [x] `ChatMessageCell`にプライベートプロパティ`contentStackView: UIStackView`を追加。
  - axis = .vertical
  - spacing = 8
  - distribution = .fill
  - alignment = .fill
- [x] `setup()`内で`contentStackView`をbubbleViewに追加し、AutoLayoutで制約設定。
  - top/bottom/leading/trailing = bubbleView.layoutMarginsGuide
  - bubbleView.layoutMargins を左右12, 上下10に設定（既存のtextView制約と同等）
- [x] 既存の`textView`を**非表示化**（`textView.isHidden = true`）。**削除しない**（pushButton・prepareForReuse()で参照されているため）。
- [x] ビルド確認：エラーなしでコンパイル通過を確認。

### Phase 2 configure(message:isUser:runner:)のリファクタリング
- [x] `configure(message:isUser:runner:)`冒頭で`contentStackView.arrangedSubviews`を全削除。
  ```swift
  for view in contentStackView.arrangedSubviews {
      contentStackView.removeArrangedSubview(view)
      view.removeFromSuperview()
  }
  ```
- [x] 推論中インジケーター表示ロジック（Lines 583-589）を**維持**。推論中の場合は既存のloadingStackViewを表示し、contentStackViewは空のまま終了。
- [x] 通常メッセージの場合、`MessageParser.parse(message.content, isUser: isUser)`を呼び出し、`[MessageContentSegment]`を取得。
  - **セグメント数チェック**: `segments.count > 20`の場合、`segments = Array(segments.prefix(20))`で切り詰め、警告ログ出力。
- [x] segmentsをループ処理：
  - `.text(let attrString)` → `createTextView(with:isUser:)`で新UITextViewを作成し、contentStackViewに追加。
  - `.codeBlock(let code, let language)` → `createCodeBlockView(code:language:)`で新CodeBlockViewを作成し、contentStackViewに追加。
- [x] `textView.isHidden = true`を設定（旧UITextViewを完全に隠す）。
- [x] Phase 4長文折りたたみ機能を一時無効化（`expandButton.isHidden = true`）。
- [x] ビルド＆実行：単純なテキストメッセージが表示されることを確認。

### Phase 3 テキスト用UITextView生成メソッド実装
- [x] `createTextView(with attributedString: NSAttributedString, isUser: Bool) -> UITextView`を実装。
  - UITextViewを生成
  - attributedText = attributedString
  - isEditable = false, isSelectable = true, isScrollEnabled = false
  - textContainerInset = .zero
  - textContainer.lineFragmentPadding = 0
  - backgroundColor = .clear
  - font = UIFont.preferredFont(forTextStyle: .body)（既存設定を踏襲）
  - textColor = isUser ? .white : UIColor.label
  - linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
  - dataDetectorTypes = []
  - delaysContentTouches = false
  - returnで生成したUITextView
- [x] ビルド確認。

### Phase 4 CodeBlockView生成メソッド実装
- [x] `createCodeBlockView(code: String, language: String?) -> CodeBlockView`を実装。
  - CodeBlockView()を生成
  - configure(code: code, language: language)を呼び出し
  - returnで生成したCodeBlockView
- [x] ビルド確認。

### Phase 5 prepareForReuse()実装修正
- [ ] `prepareForReuse()`メソッドを更新。
  ```swift
  override func prepareForReuse() {
      super.prepareForReuse()
      // contentStackViewのサブビューをクリア
      for view in contentStackView.arrangedSubviews {
          contentStackView.removeArrangedSubview(view)
          view.removeFromSuperview()
      }
      // 既存のtextViewはクリアのみ（削除しない）
      // IMPORTANT: isHiddenはリセットしない（configure()の最初で必ず設定されるため不要）
      textView.text = nil
      textView.attributedText = nil

      // その他既存のリセット処理（Phase 4展開ボタン等）
      avatarImageView.image = nil
      activityIndicator.stopAnimating()
      loadingStackView.isHidden = true
      isExpanded = false
      fullContent = ""
      expandButton.isHidden = true
      expandButton.setTitle("続きを読む", for: .normal)
      textViewBottomConstraint?.isActive = false
  }
  ```
- [ ] ビルド確認。

### Phase 6 高さ計算最適化
- [ ] ChatListContainerView内のestimatedRowHeight計算ロジック（Lines 746-759付近）を確認。
- [ ] コードブロック含有メッセージの推定高さ補正を追加：
  ```swift
  // 既存: 文字数ベースの推定
  let baseHeight = min(max(charCount / 40 * 24, 60), 800)
  // 追加: コードブロック数の検出（簡易的に```の出現回数/2）
  let codeBlockCount = message.content.components(separatedBy: "```").count / 2
  let codeBlockBonus = codeBlockCount * 150  // 1ブロックあたり150pt加算
  return baseHeight + CGFloat(codeBlockBonus)
  ```
- [ ] 実機でスクロール動作確認。ジャンプやカクつきがあれば係数を調整。

### Phase 7 MessageParser内部の最適化とフォールバック
- [ ] MessageParser.parse()に性能計測コードを追加：
  ```swift
  static func parse(_ markdown: String, isUser: Bool) -> [MessageContentSegment] {
      let shouldMeasure = markdown.utf8.count >= 100_000
      let startTime = shouldMeasure ? CFAbsoluteTimeGetCurrent() : 0

      // 既存のパース処理
      var segments: [MessageContentSegment] = []
      // ... (正規表現マッチング)

      if shouldMeasure {
          let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
          print("[Phase 7] Parse time: \(String(format: "%.1f", elapsed))ms for \(segments.count) segments")
          if elapsed > 100 {
              print("[Phase 7] ⚠️ Parse exceeded 100ms, consider Phase 7-A")
          }
      }

      // セグメント上限チェック（DoS防止）
      if segments.count > 20 {
          print("[Phase 7] ⚠️ Segment count \(segments.count) exceeds limit 20, truncating")
          segments = Array(segments.prefix(20))
      }

      return segments
  }
  ```
- [ ] MessageParser.renderText()にフォールバック処理を追加（Master_Specification 8.7準拠）：
  ```swift
  private static func renderText(_ text: String, isUser: Bool) -> NSAttributedString {
      do {
          // 既存のAttributedString(markdown:)処理
          let attributed = try AttributedString(markdown: text, options: ...)
          return NSAttributedString(attributed)
      } catch {
          // フォールバック: プレーンテキストで返却
          print("[Phase 7] Markdown parsing failed, fallback to plain text: \(error)")
          let font = UIFont.preferredFont(forTextStyle: .body)
          let color: UIColor = isUser ? .white : .label
          return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
      }
  }
  ```
- [ ] ビルド＆実行：100KBメッセージでログ確認。

### Phase 7-A 段階的パース（必要時のみ）
- [ ] Phase 7で100ms超過が頻発する場合のみ実施。
- [ ] 10KBチャンクに分割してDispatchQueue.globalでパース→DispatchQueue.mainで結果をマージ。
- [ ] または、正規表現の最適化（NSRegularExpressionのキャッシュ、パターン簡略化）。

### Phase 8 ユニットテスト・UIテスト実装（Master_Specification 8.7準拠）
- [ ] `RemotePromptTests/MessageParserTests.swift`を新規作成（`Testing`フレームワーク使用）。
  - テスト1: 通常テキストのみのパース（segmentsが1個、`.text`型）
  - テスト2: コードブロック1個のパース（segmentsが1個、`.codeBlock`型、言語名抽出）
  - テスト3: 混在メッセージのパース（text + code + text のセグメント順序検証）
  - テスト4: セグメント上限（21個のコードブロック→20個に切り詰め、警告ログ検証）
  - テスト5: パース性能計測（100KB入力で計測ログ出力を検証、**閾値断定はしない**。CI環境の非決定性を考慮し、ログ出力の有無とフォーマットのみ確認。性能閾値（<100ms）はPhase 9手動テストで確認）
  - テスト6: Markdownフォールバック（不正なMarkdown構文でAttributedString生成失敗→プレーンテキスト返却）
  - テスト7: 空文字入力（空配列またはプレーンテキストセグメント1個）
- [ ] `RemotePromptTests/CodeBlockViewTests.swift`を新規作成。
  - テスト1: configure()で言語名・コード内容が正しく設定される
  - テスト2: コピーボタンタップでUIPasteboard.general.stringに内容がコピーされる
  - テスト3: コピー後にボタンラベルが「Copied!」→元に戻る（1.5秒後）
- [ ] `RemotePromptUITests/ChatCodeBlockUITests.swift`を新規作成。
  - UIテスト1: チャット画面でコードブロックメッセージを送信→CodeBlockViewが表示される
  - UIテスト2: コピーボタンをタップ→「Copied!」が表示される
  - UIテスト3: 100KBコードブロックでスクロールがスムーズ（カクつき検証は手動）
- [ ] 全テスト実行：`xcodebuild test -scheme RemotePrompt`で成功確認。

### Phase 9 手動テスト・検証
- [ ] 通常テキストのみのメッセージ表示確認。
- [ ] コードブロック1個のメッセージ表示確認（言語名あり/なし両方）。
- [ ] コードブロック複数個＋通常テキスト混在メッセージ表示確認。
- [ ] コピーボタンタップ→クリップボード確認＋「Copied!」表示確認。
- [ ] **100KBコードブロックを含むメッセージでフリーズなし確認（パース処理<100msを実機で計測、Phase 8では閾値断定せず）**。
- [ ] スクロール動作確認（カクつきなし）。
- [ ] ダークモード/ライトモードでの表示確認。
- [ ] MD表示テストボタン（ChatView.swift Lines 32-35）でMarkdown総合表示確認。
- [ ] 推論中インジケーター表示確認（既存機能が正常動作）。
- [ ] Phase 4長文折りたたみ機能（1000文字超）が引き続き動作するか確認（expandButton表示・展開/折りたたみ）。
- [ ] **セル再利用時にtextView.isHiddenの状態が正しく制御されているか確認（推論中→通常メッセージのスクロール遷移でちらつきなし）**。

### Phase 10 クリーンアップ
- [ ] 旧renderMarkdown()メソッド（Lines 616-715）を削除またはコメントアウト（不使用確認後）。
  - **注意**: Phase 9で互換性テスト完了後のみ削除。削除前にコミット推奨。
- [ ] `textView`プロパティは**削除しない**（pushButton・prepareForReuse()で引き続き使用）。
- [ ] 不要なimport文削除。
- [ ] コード整形・コメント追加（特にconfigure()内のロジック、MessageParser.parse()）。
- [ ] 実装計画完了をDocs/MASTER_SPECIFICATION.mdに記録（8.7章に追記）。

## リスクと緩和
- **UIStackView内の複数ビュー生成による高さ計算コスト**
  - 緩和: estimatedRowHeightにコードブロック数を反映（Phase 6）。実機でジャンプがあれば係数調整。
- **正規表現パース性能劣化（100KB級メッセージ）**
  - 緩和: Phase 7で計測＋ログ。目標<100ms。超過時はPhase 7-Aで段階的処理またはパターン最適化。
  - **残リスク（小）**: CI環境での性能テストは非決定的なため、Phase 8では閾値断定せず、ログ出力の有無とフォーマットのみ検証。閾値（<100ms）はPhase 9手動テストで実機計測。
- **CodeBlockViewのメモリリーク**
  - 緩和: prepareForReuse()で確実に削除（Phase 5）。Instruments Allocationsで確認。
- **UITextView複数生成によるメインスレッド負荷**
  - 緩和: 1メッセージあたりのセグメント数を最大20に制限（Phase 7）。超過時は警告ログ＋最初の20個のみ表示。
- **textView削除によるコンパイルエラー**
  - 緩和: Phase 1で非表示化のみ、削除しない。expandButton・prepareForReuse()の既存ロジックを維持。
- **Markdown構文エラーによるクラッシュ**
  - 緩和: MessageParser.renderText()にtry-catchフォールバック実装（Phase 7）。プレーンテキストで安全に表示。
- **テスト不足による品質リスク**
  - 緩和: Phase 8でユニットテスト・UIテスト網羅。Master_Specification 8.7要件を充足。
- **prepareForReuse()時のtextView.isHidden制御**
  - 緩和: Phase 5でisHiddenをリセットせず、configure()の最初で必ず設定する方針。Phase 9でセル再利用時のちらつきを手動確認。
  - **残リスク（小）**: 推論中→通常メッセージのスクロール遷移で、configure()が呼ばれる前にtextViewが一瞬見える可能性。実機テストで確認し、問題があればconfigure()冒頭で即座にisHidden設定を追加。

## 工数目安
- Phase 0: 0.5h (完了)
- Phase 1: 1h
- Phase 2: 1.5h
- Phase 3: 1h
- Phase 4: 0.5h
- Phase 5: 0.5h
- Phase 6: 1h
- Phase 7: 1.5h（計測＋フォールバック実装）
- Phase 7-A: 2h（必要時のみ）
- Phase 8: 3h（ユニットテスト・UIテスト実装）
- Phase 9: 1.5h（手動テスト網羅）
- Phase 10: 1h
- **合計: 約12.5h**（Phase 7-A不要なら約10.5h）

## 完了条件
- コードブロックが言語名＋コピーボタン付きの専用UIで表示される。
- 通常テキストとコードブロックが混在したメッセージが正しくレイアウトされる。
- コピー機能が正常動作する（クリップボード＋「Copied!」表示）。
- 100KB級メッセージでもフリーズなし（パース処理<100ms）。
- セグメント数20個超は切り詰め＋警告ログ出力（DoS防止）。
- セル再利用時にメモリリークなし。
- ダークモード/ライトモードで適切に表示される。
- Phase B Refactor-12の完了条件（フリーズなし、Jetsamなし）を維持。
- Master_Specification 8.7 Markdownレンダリング要件準拠：
  - AttributedString生成の例外時フォールバック実装
  - ユニットテスト・UIテストでコードブロックUI/パース性能/フォールバックを検証
  - 既存のフォント/テーマ設定が継続動作
- Phase 4長文折りたたみ機能（1000文字超）が引き続き動作。

## 参考
- Master_Specification 8.7: Markdownレンダリング要件
- Phase B Refactor-12: UITableView_MD_Rendering_Plan.md
- ChatListRepresentable.swift: Lines 144-243 (CodeBlockView), Lines 14-142 (MessageParser), Lines 380-791 (ChatMessageCell)
- ChatView.swift: Lines 32-35 (MD表示テストボタン)
