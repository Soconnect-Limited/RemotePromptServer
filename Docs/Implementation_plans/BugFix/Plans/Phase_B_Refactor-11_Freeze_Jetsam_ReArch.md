# Phase B Refactor-11: Freeze/Jetsam 抜本対策 Re-Architecture Plan (Checklist)
作成日: 2025-11-24
目的: UI貼り付け/キーボード負荷とSSE/送信負荷を完全分離し、メインスレッド飽和とJetsamを防止する。

## ゴール/完了条件
- 通常プロンプト送信10回でUIフリーズなし、`fetchFinalResult` 1回/ジョブ。
- 長文(100KB)×10送信でもUI固まらず、RSS < 500MB、JetsamEventなし。
- ログは必要最低限、デバッグ時のみ詳細有効。A/B切替可能。

## フェーズ構成
- Phase 1: 入力経路分離・キーボード負荷低減
- Phase 2': SSE処理の専用キュー化（BG化を最優先） + A/B切替
- Phase 3: ログ/計測の最小化
- Phase E: Jetsam早期警告モニタ
- Phase 4: メッセージ保持の軽量化（短期対症）
- Phase A/B/C/D: 長期的抜本対策（ストリーム処理・Lazy Loading・fetchStreaming・Session Pool）
- Phase 5: テストプロトコル整備

---

## Phase 1: 入力経路分離・キーボード負荷低減
- [ ] TextEditor に入力系モディファイアを付与
  - [ ] `.autocorrectionDisabled(true)`
  - [ ] `.textInputAutocapitalization(.never)`
  - [ ] `.keyboardType(.asciiCapable)`
- [ ] 大文字量テキストをUIに保持しない構造
  - [ ] 入力欄は短い表示用文字列のみ保持（例: 2000文字上限）
  - [ ] 実送信テキストは一時バッファ（ファイル or メモリ）で保持し、送信直前にロード
- [ ] デバッグ用「100KB送信」ボタン追加（#if DEBUG）
  - [ ] ChatViewModelに `sendLoadTestPayload(sizeKB: Int = 100)` を追加
  - [ ] UIから直接送信（貼り付け不要）

## Phase 2: SSE処理の専用キュー化 + A/B切替
### Phase 2': SSE処理の専用キュー化（最優先）
- [ ] SSEManagerを single OperationQueue(.userInitiated, maxConcurrentOperationCount=1) に戻す（BGキュー）
- [ ] delegateQueueをコンフィグで切替可能にする
  - [ ] Option A: delegateQueue = .main（Spec準拠・デフォルト）
  - [ ] Option B: delegateQueue = BG queue（UI負荷分散、現状推奨）
  - [ ] 設定フラグでA/Bを起動時に選択（UserDefaults / env）
- [ ] URLSession生成方針のスイッチ
  - [ ] A: 接続毎生成（Spec準拠）
  - [ ] B: インスタンス再利用（性能優先）
  - [ ] デフォルト: A（Spec準拠）、必要に応じてBに切替

## Phase 3: ログ/計測の最小化
- [ ] DEBUGログのレートリミット（state遷移とfetch開始/完了のみ）
- [ ] `[VIEW-ONCHANGE]` 等高頻度ログをオフ or 1秒あたり1回に抑制
- [ ] MEMORY_METRICS はデバッグビルド時のみ有効

## Phase 4: メッセージ保持の軽量化
- [ ] MessageStoreキャッシュ上限を100→50に一時変更
- [ ] 表示用配列と送信用データを分離（UIは軽量化）
- [ ] `fetchFinalResult` で巨大stdoutの場合は警告ログのみで早期リターン（必要ならストリーム保存）
 - [ ] 代替案メモ: stdout圧縮保存、LRUキャッシュ化、ディスク退避（長期）

## Phase 5: テストプロトコル整備
- [ ] テストシナリオをREADMEに追記（またはプラン内メモ）
  - [ ] 通常プロンプト(<=2KB)×10連投：フリーズ/二重fetchなし
  - [ ] 長文100KB×10（デバッグボタン使用）：フリーズなし、RSS < 500MB
  - [ ] JetsamEventが生成されないことを確認（解析データ）

## Phase E: Jetsam早期警告モニタ
- [ ] DispatchSourceMemoryPressure で warning/critical を監視
- [ ] warning: 古いメッセージを20件残して即時圧縮/ディスク退避
- [ ] critical: 全SSE切断 + 明示解放 + ログ出力

## Phase A/B/C/D: 長期的抜本対策
- Phase A: SSE受信ストリーム処理（メモリ爆発防止）
- Phase B: MessageStore Lazy Loading（3層キャッシュ）
- Phase C: fetchFinalResult Streaming（チャンクUI更新）
- Phase D: URLSession共有プール（並行上限制御）

## 優先度と概算工数（目安）
- 最小構成（即効性）：Phase 1 + Phase 2' + Phase 3 + Phase E ≈ 7h
- 完全構成（抜本対策）：全Phase ≈ 25.5h

## ロールバック/スイッチ
- [ ] delegateQueue A/B 切替スイッチを UserDefaults / 環境変数で持つ
- [ ] URLSession生成 A/B を同様に切替可能に

## リスク
- delegateQueueをBGに戻すとSpecとの差異が出るため、後でSpec更新/注記が必要。
- MessageStore上限変更で古い履歴が見えなくなる可能性（テスト期間中のみ適用）。

## 進行管理
- PhaseごとにPR/コミットを分割
- 各Phase完了時に計測結果を記録
