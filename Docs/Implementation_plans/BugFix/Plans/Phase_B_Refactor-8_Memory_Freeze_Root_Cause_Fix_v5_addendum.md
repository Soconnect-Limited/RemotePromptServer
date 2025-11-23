# Phase B Refactor-8: メモリ暴走・UI凍結 根本原因修正計画 v5 追補（Codex追加レビュー）

作成日: 2025-11-23  
用途: v5計画を現行サーバー・iOSコードと照合し、不整合や追加リスクを解消するブレイクダウン補強

## 適用範囲
- サーバー: `remote-job-server/main.py`, `remote-job-server/sse_manager.py`, `remote-job-server/job_manager.py`
- iOS: `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/SSEManager.swift`, `ViewModels/ChatViewModel.swift`, `Views/ChatView.swift`
- 仕様: `Docs/Specifications/Master_Specification.md` (v4.2→v4.3への改訂項目)

## 差分サマリ（v5への追補）
- **初期スナップショット送信は同期APIで取得**：`job_manager.get_job()` は同期関数。`stream_job_status` 内で同期取得し `data:` 付きSSEイベントを即送信。`await job_manager.get_job` 形式は不可。
- **SSEフォーマットの責務分担を維持**：`broadcast` は dict を受け取り、`subscribe` が `data: …\n\n` に整形する現行設計を踏襲。`_broadcast_job_event` 側で `data:` を付けない。
- **heartbeatはコメントフレームで30s**：`subscribe` で `asyncio.wait_for(queue.get(), timeout=30)`、`TimeoutError` 時に `:heartbeat\n\n` を送信。
- **ヘッダー重複回避**：`/jobs/{id}/stream` は既に `Cache-Control` と `X-Accel-Buffering` を設定済み。追加時は重複を避ける。
- **delegateQueue方針の明文化が必要**：Spec v4.2 は `.main` を想定。serial `OperationQueue` を採用する場合は v4.3 で仕様を更新する。
- **最終結果取得の二重実行防止**：`ChatViewModel` に `finalResultFetched` セットを持たせ、`isConnected=false` トリガと終端ステータスの双方で一度だけ実行。
- **ChatViewのonChangeを1本化**：`messages.count` と `messages.map{content+status}` の二重監視を統合し、ID差分のみでスクロール。
- **buffer上限1MB**：`didReceive data` で `buffer.count + data.count > 1_048_576` の場合はログ出力してクリア&破棄。

## ブレイクダウン

### P0-Server（レース・切断対策）
1) `/jobs/{job_id}/stream` 初期スナップショット  
   - `job = job_manager.get_job(job_id)` を同期取得。存在すれば `initial_event = {"status": …}` を `data: {json}\n\n` で最初にyield。  
   - 既に `completed/failed` の場合はスナップショット送信後 `return`。  
   - 既存 `StreamingResponse` のヘッダーは流用（重複追加しない）。

2) heartbeat送信（30sコメント）  
   - `sse_manager.subscribe`: `asyncio.wait_for(queue.get(), timeout=30.0)`。  
   - `TimeoutError` 時に `:heartbeat\n\n` をyieldし `LOGGER.debug` で記録。  
   - payload dict を受け取った場合のみ `data:` 変換して送出。

3) 購読者数ログとclose保証  
   - `job_manager._broadcast_job_event`: broadcast前に `subscribers = len(self.sse_manager._connections.get(job_id, []))` をINFOログ。  
   - `close_stream=True` ならログを残して `close()` を必ず呼ぶ（購読0でも実行）。

### P1-iOS（防御強化）
4) delegateQueue方針の決定  
   - **Option A（現状維持）**: `delegateQueue = .main`（Spec v4.2準拠）。  
   - **Option B（順序重視）**: serial `OperationQueue` を明示。採用する場合は Spec v4.3 に「delegateQueue=serial queue」を追記。

5) Buffer上限1MB  
   - `SSEManager.urlSession(_:didReceive:)`: 上限超過時に `[SSE-BUFFER] LIMIT EXCEEDED` を出力し `buffer.removeAll(); return`。

6) fetchFinalResult 二重実行防止  
   - `ChatViewModel`: `finalResultFetched: Set<String>` を追加。`isConnected=false` / 終端イベントの両方でガードし、一度だけ fetch+cleanup。cleanup完了時にセットから削除。

7) onChange統合  
   - `ChatView`: `messages.count` と `messages.map{content+status}` の2本を削除し、`messages.map{$0.id}` 1本に統合。発火時にスクロールとログのみ。

8) HTTPヘッダーとタイムアウト  
   - `connect`: `Cache-Control: no-cache`, `Accept-Encoding: identity`, `timeoutInterval = 60`（heartbeat 30s + 余裕）。`Accept: text/event-stream` は維持。

### P2-Tests / Docs
9) SSE回帰テスト拡張（`remote-job-server/tests/test_sse.py`）  
   - fast-completion レース（購読開始前に完了）で初期スナップショットを最低1件受信すること。  
   - heartbeatを60秒観測し2回以上受信。  
   - close保証: 終端イベント後にストリームが正常終了すること。

10) Spec/Docs更新  
   - `Master_Specification.md` を v4.3 へ更新し、初期スナップショット・heartbeat・buffer上限・delegateQueue方針を明記。  
   - v5計画本体にも上記変更点を追記。

## 完了条件（追補分）
- 初期スナップショットが高速完了ジョブでも必ず1件届くことを手動/自動テストで確認。  
- heartbeatが30s間隔で送達し、iOSログに記録されること。  
- buffer超過時にログが出てメモリリークしないこと。  
- fetchFinalResultがジョブごとに一度だけ実行されるログを確認。  
- Spec v4.3 と計画ドキュメントの改訂が完了。
