# Phase B Refactor-8: メモリ暴走・UI凍結 根本原因修正計画（コードレビュー版）

作成日: 2025-11-23 / 作成者: Codex

## 目的
- Docs/Implementation_plans/Phase_B_Refactor-8_Memory_Freeze_Root_Cause_Fix.md の計画を、現行サーバー・iOSコードを踏まえて精査し、実装着手前にブレイクダウンを明確化する。
- Master_Spec v4.2（Docs/Specifications/Master_Specification.md）に適合する形で、SSEストリームとUIのフリーズ再発を防止する。

## 参照ソース
- サーバー: `remote-job-server/main.py:500-590`（/jobs/{id}/stream SSEエンドポイント）, `remote-job-server/sse_manager.py`, `remote-job-server/job_manager.py:1-160`
- iOS: `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/SSEManager.swift`, `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ChatViewModel.swift`, `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/ChatView.swift`
- 既存計画: Docs/Implementation_plans/Phase_B_Refactor-8_Memory_Freeze_Root_Cause_Fix.md
- 仕様: Docs/Specifications/Master_Specification.md (v4.2, Thread Simplification + SSE Fix)

## 現状コード概要（抜粋）
### サーバー側
- SSEエンドポイントは `StreamingResponse` で `text/event-stream` を返却し、キューに入ったpayloadをそのまま `data:` 行で送出。キュー終了時に接続をクローズ（close時はNoneをput）。
- `JobManager._broadcast_job_event()` が `status` 更新と最終イベント送信を担当し、`close_stream=True` で確実にクローズを指示。
- 心拍やリトライイベントは未送信。サブスクライバ不在時に履歴を再送する仕組みはなし。

### iOS側
- `SSEManager.connect()` は毎回新規 `URLSession` を生成し、`Accept: text/event-stream` のみを付与。バッファ上限なしでチャンクを蓄積し、`\n\n` で区切ってJSONデコードする。
- `ChatViewModel.startSSEStreaming()` で `SSEManager` をジョブごとに生成し、`$jobStatus` / `$isConnected` をCombine購読。切断時に0.5秒待って `fetchFinalResult` を呼び、`cleanupConnection` でcancellableを破棄。
- `ChatView` は `messages.count` と `messages.map { content+status }` の二系統 `onChange` を持ち、全件再描画を誘発する可能性がある。

## ギャップと懸念点（計画との差分）
- **高速完了レース**: ジョブが瞬時に完了すると、SSE購読開始前に`broadcast/close`が終わり、クライアントはヘッダ受信直後に`didComplete`で終了しデータゼロ → 既観測事象と一致。サーバー側に遅延バッファや最終状態の即時返却が無く、計画に明記なし。
- **キープアライブ欠如**: サーバーは心拍を送らず、クライアントも`timeoutIntervalForRequest=300`のみ。ネットワーク/プロキシによる早期切断で`didReceive data`未到達のまま完了し得る。計画ではウォッチドッグはiOSのみ想定でサーバー未着手。
- **バッファ上限とメモリ計測**: iOSの`buffer`サイズ制御は未実装（計画フェーズ2.2で記載あるがコード未対応）。Combineの購読数ログも未追加。
- **ビュー再描画トリガ多重**: `ChatView` の2つの `onChange` が `messages`全体を監視し、status更新ごとにスクロール・再描画。計画には再描画抑制策が未整理。
- **サーバー側検証不足**: `remote-job-server/tests/test_sse.py` では高速完了・購読開始タイミングのレースを網羅しておらず、再現性のある回帰テストが欠ける。

## 改訂ブレイクダウン計画
### Phase 0: 事前確認
- [ ] Master_Spec v4.2 で求めるSSE動作（Thread Simplification後のrunner自由切替）を確認。影響範囲: /jobs, /jobs/{id}/stream, iOS SSEクライアント。
- [ ] 現行バイナリでメモリ挙動を再計測し、Logs/memory_snapshot_comparison.md に追記（既存計画1.0と整合）。

### Phase 1: 診断強化（計画補強）
- [ ] iOS `SSEManager` / `ChatViewModel` に状態遷移ログとスレッド情報を追加（計画1.1/1.2）し、`didReceive`未着時の最終ステートを取得。
- [ ] `buffer.count` と `AnyCancellable` 数をログし、リークパターンを可視化（計画1.3/1.4）。
- [ ] `ChatView` の描画回数・差分ログを追加し、再描画起点を特定（計画1.5）。
- [ ] サーバー側: SSEサブスク登録・close呼び出しをINFOログで相関ID付き記録し、クライアント未受信時のタイムラインを復元できるようにする（新規補足）。

### Phase 2: サーバー側暫定修正
- [ ] `/jobs/{id}/stream` で接続直後に最新ジョブ状態を単発送信（running/finishedのスナップショット）して、購読開始が遅れても必ず1件受信できるようにする（レース解消）。
- [ ] 15〜30秒間隔の `:heartbeat` コメントまたは `event: ping` を送信し、アイドル切断と`didReceive`未到達を抑止。
- [ ] `SSEManager.close()` をジョブ完了後に確実に呼ぶだけでなく、購読ゼロ時でも「最終状態を返して即close」するパスを追加し、無限待ちを防ぐ。
- [ ] `remote-job-server/tests/test_sse.py` に高速完了・遅延購読シナリオ、heartbeat有無、close保証の回帰テストを追加。

### Phase 3: iOS側恒久修正
- [ ] `SSEManager.connect()` で `httpAdditionalHeaders` に `Cache-Control: no-cache`, `Accept-Encoding: identity` を追加し、プロキシバッファリングを回避。`request.timeoutInterval = 0`（無限）ではなくサーバーheartbeat間隔+余裕で再設定。
- [ ] `buffer` に1MB上限を設け、超過時はイベント境界でリセットしログを吐く（計画2.2）。
- [ ] `URLSession` をジョブ単位で生成する現行方針は維持しつつ、`delegateQueue` をserial `OperationQueue` に固定して順序性を保証（メインキューに戻さない）。
- [ ] `ChatViewModel` の `sseCancellables` を `Set` に集約し、`cleanupConnection` が二重呼び出しでも安全に `cancel` / `removeAll` するよう防御（計画2.3強化）。
- [ ] `ChatView` の `onChange` を1本に統合し、差分検知を `MessageStore` 側で行うか、`messages` の変更点のみをスクロールトリガにする（再描画ループ回避）。
- [ ] `fetchFinalResult` を`isConnected` falseトリガと`JobStatus` terminalイベントの両方で一度だけ実行するガードを追加し、二重更新とタスク累積を防止。

### Phase 4: 検証
- [ ] iOS: Instruments (Memory Graph + Allocations) で1回目/2回目送信後の差分を取得し、`URLSession` / `Data` / `AnyCancellable` の残存を確認（計画1.0）。
- [ ] iOS: 自動化シナリオで「高速完了ジョブ」「長時間stream」「途中キャンセル」を走らせ、RSS推移とUI応答性を計測。最低3周繰り返し。
- [ ] サーバー: pytestでSSEレース・heartbeat・close保証のテストをCIに追加。`pytest remote-job-server/tests/test_sse.py -k heartbeat` を想定。

### Phase 5: ドキュメント・リリース
- [ ] 修正内容を `Docs/MASTER_SPECIFICATION.md` と `Docs/Implementation_plans/Phase_B_Refactor-8_Memory_Freeze_Root_Cause_Fix.md` に反映（SSE初期スナップショット送信とheartbeat追記）。
- [ ] iOS/サーバー双方のログ取得手順を `Logs/memory_snapshot_comparison.md` に追記し、再発時の確認フローを明文化。

## リスクと優先順位
- **最優先**: サーバー初期スナップショット送信 + heartbeat 追加（`didReceive`未着で即`didComplete`する現象の根治が目的）。
- **次点**: iOSバッファ上限・`onChange`統合。これらが未対応だと再描画ループとメモリ膨張の再現余地が残る。
- **計測依存**: CombineリークやURLSession残存は Instruments 計測結果次第で追加タスク化。計測前に最終対処を決めない。

## 完了条件（Definition of Done）
- 高速完了ジョブでもクライアントが少なくとも1件のSSEイベントを受信し、UIがフリーズしないことを手動/自動テストで確認。
- 3回連続送信後のRSS増加が±5MB以内で安定し、`AnyCancellable` や `URLSession` が累積しないことを Instruments で確認。
- pytestのSSE新規テストがgreen、iOSデバッグログに state遷移とbufferサイズが記録されること。
