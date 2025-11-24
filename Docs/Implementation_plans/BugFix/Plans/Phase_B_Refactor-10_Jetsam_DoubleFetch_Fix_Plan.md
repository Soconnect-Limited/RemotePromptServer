# Phase B Refactor-10: Jetsam (Double Fetch) Fix Plan
作成日: 2025-11-24
対象: iOS RemotePrompt アプリ (Chat/SSE)

## 背景・現象
- JetsamEvent-2025-11-23-235852.ips で `largestProcess: RemotePrompt`, rpages ≈ 181,763 (約2.9GB) に達しメモリ予算超過でKill。
- Xcodeログで各ジョブにつき `fetchFinalResult` が二重に実行され、LLMレスポンスが大きいほどメモリ・CPUが倍増。
- SSEManager が仕様(v4.3)と異なり delegateQueue を独自BGキューで生成し続けている点も付随リスク。

## ゴール
- 終端ステータスと切断イベントのどちらか一方のみで最終結果取得を実行し、二重フェッチを根絶。
- SSE接続の生成とキュー指定を仕様準拠に戻し、不要なURLSession増殖とスレッド負荷を抑制。
- 修正後にJetsamが再発しないことを確認する再現テスト手順を用意。

## 前提・参照
- Docs/Specifications/Master_Specification.md (v4.3 SSE初期スナップショット + delegateQueue.main + timeout60 + 1MBバッファ)。
- 既存メモリ計測ログ出力 (`#if DEBUG && MEMORY_METRICS`).

## タスクチェックリスト
### A. 原因箇所修正 (ChatViewModel.swift)
- [ ] `finalResultFetched` の管理を「一度だけフェッチ」に変更
  - [ ] 終端ステータス受信時にフラグをセットし、切断側は未受信かつ未フェッチの場合のみ実行
  - [ ] `defer` でフラグを即クリアしない（二重実行防止を優先）
  - [ ] フラグは @MainActor 保護下の Bool または OSAllocatedUnfairLock<Bool> で管理し、競合を防止
  - [ ] 新規ジョブ開始時（sendMessage/createJob直後）に対象 jobId のフラグを明示リセット
- [ ] 切断イベントのフェッチ条件を「jobStatus未終端かつ未フェッチ」に限定
- [ ] ログメッセージを二重起動検知用に整理（fetch開始を一意に）

### B. SSEManager 仕様整合
- [ ] URLSession delegateQueue を `.main` に固定（v4.3準拠）
- [ ] URLSession 生成方針を Master Spec 確認のうえ明記
  - A案: 接続毎に生成・破棄（仕様優先）
  - B案: インスタンス内で再利用し、connect毎の新規生成を抑制（メモリ効率優先）
  - 現時点の採用: delegateQueue.main 固定＋再利用（B案）。仕様上A案が求められる場合は方針を切替。
- [ ] 生成・破棄ログを簡素化し、メモリ測定箇所を必要最小限に

### C. メモリフットプリント抑制（オプション）
- [ ] `fetchFinalResult` で取得する `stdout` が閾値超過時に警告ログを出す
- [ ] MessageStore キャッシュ上限(100)を超えた古いメッセージを明示削除（現行trim確認）

### D. テスト & 再現確認
- [ ] 手動: 同一長文プロンプトを10連投し、Xcodeログで `fetchFinalResult` が1回/ジョブであることを確認
  - プロンプト: Lorem ipsum 100KB相当（約1e5文字）
  - 投稿間隔: 2秒間隔で直列送信（必要に応じて1秒に短縮し軽い並行状態を作る）
  - 期待: 各ジョブで fetch ログ1回のみ、二重発火なし
- [ ] 手動: `DEBUG && MEMORY_METRICS` 有効ビルドでRSS推移を記録し、500MB以内で頭打ちになること
- [ ] デバイス: 再現後に解析データで JetsamEvent が出ないことを確認

## 作業順序
1) Aを実装 → ユニットレベルで二重フェッチログが消えることを確認
2) Bを実装 → ビルド・起動確認（SSE接続正常）
3) Cは必要に応じて実施（長文負荷が続く場合）
4) Dの手動試験を実施し結果を記録

## リスク / 注意点
- `finalResultFetched` の扱い変更で稀なネットワーク切断時に未フェッチとなる恐れ。切断側条件を慎重に実装すること。
- delegateQueueをmainに戻すことでUIスレッド負荷が増える可能性があるため、ログ量を抑制しつつ検証。

## 完了条件
- 各ジョブで `Fetching final result` ログが1回のみになる
- 10連投テストでRSSが安定し、JetsamEventが記録されない
- Master Spec v4.3 SSE要件と実装が一致
