# Phase B: Thread Management API 完全実装計画（v4.1準拠版）

**親ファイル**: [thread_management_v2.1_final.md](./thread_management_v2.1_final.md)
**派生元セクション**: Phase B - 抜本的最適化（Thread API未実装問題の解決）
**作成日**: 2025-01-21
**最終更新**: 2025-01-21（MASTER_SPECIFICATION.md v4.1準拠に更新）
**目的**: Thread Management APIの完全実装により、Thread別履歴管理とRunner切り替えの根本的な問題を解決する

**v4.1仕様準拠の主な変更点**:
- GET /threads: runnerフィルタをサーバー側実装に変更（クライアント側 → サーバー側）
- GET /threads: limit/offsetページネーション実装
- PATCH /threads: device_id必須パラメータを明記
- DELETE /threads: Jobs処理を明確化（CASCADE削除せず、thread_id=NULL）
- 互換モード（thread_id NULL）のテスト観点を追加

---

## 📋 概要

### 現状の問題

1. **Thread API未実装**
   - サーバー側は4次元session管理 `(device_id, room_id, runner, thread_id)` を実装済み
   - しかし**Thread作成・取得APIが存在しない**
   - `ThreadListViewModel.swift`は存在するが、APIエンドポイントが未実装のため機能していない

2. **データフロー不整合**
   - **ChatViewModel**: threadIdを受け取るが、実際には機能していない
   - **RoomDetailView**: `selectedThread`を保持するが、実際のThread取得ができていない
   - **ThreadListView**: 表示されるが、Thread一覧が取得できない

3. **View再生成問題**
   - [RoomDetailView.swift:105](../../iOS_WatchOS/RemotePrompt/RemotePrompt/Views/RoomDetailView.swift#L105)の`.id()`修飾子がrunner切り替え時にChatViewを完全破棄・再生成
   - 進行中のAPI requestがキャンセルされ、"Request interrupted by user"エラーが発生

### 解決方針

**Phase A（完了済み）**: Runner切り替え基盤実装
**Phase B（本計画）**: Thread Management API完全実装 + View再生成問題の解決

---

## 🎯 実装範囲

### Phase B-1: バックエンド - Thread Management API実装

必要なエンドポイント：
- `POST /rooms/{room_id}/threads` - Thread作成
- `GET /rooms/{room_id}/threads` - Thread一覧取得
- `PATCH /threads/{thread_id}` - Thread名更新
- `DELETE /threads/{thread_id}` - Thread削除

### Phase B-2: iOS - Thread選択フロー実装

修正箇所：
1. **APIClient.swift** - Thread API呼び出し実装
2. **ThreadListViewModel.swift** - 実際のThread取得・作成ロジック実装
3. **RoomDetailView.swift** - `.id()`修飾子削除 + Thread選択時の正しいthread_id渡し
4. **ChatViewModel.swift** - threadIdの正しい使用

### Phase B-3: 統合テスト

- Thread作成 → Chat表示 → Runner切り替え → Thread切り替えの一連フロー検証
- 各Thread×Runnerの組み合わせで独立した履歴が保持されることを確認

---

## ✅ 実装チェックリスト

### Phase B-1: バックエンド実装（推定: 4時間）

#### B-1.1 データベースモデル確認
- [ ] `threads`テーブルのスキーマ確認（id, room_id, name, runner, device_id, created_at, updated_at）
- [ ] 既存のインデックス確認（room_id, runner, updated_at）
- [ ] 外部キー制約確認（room_id → rooms.id）

#### B-1.2 Thread作成API実装
- [ ] `POST /rooms/{room_id}/threads` エンドポイント作成
- [ ] リクエストボディのバリデーション実装
  - [ ] `name`: 必須、1-100文字
  - [ ] `runner`: 必須、"claude" or "codex"
  - [ ] `device_id`: 必須、Query parameter
- [ ] Thread UUID生成実装
- [ ] データベース挿入実装
- [ ] レスポンスモデル定義（Thread JSON）
- [ ] エラーハンドリング実装
  - [ ] 404: Room not found
  - [ ] 403: Room所有権エラー
  - [ ] 400: バリデーションエラー

#### B-1.3 Thread一覧取得API実装（v4.1: サーバー側フィルタ + ページネーション）
- [ ] `GET /rooms/{room_id}/threads` エンドポイント作成
- [ ] Query parameters実装
  - [ ] `device_id`: 必須
  - [ ] `runner`: オプショナル（**[v4.1] サーバー側でWHERE runner = ? によるフィルタリング実装**）
  - [ ] `limit`: オプショナル（デフォルト50、最大200）**[v4.1で追加]**
  - [ ] `offset`: オプショナル（デフォルト0、ページネーション用）**[v4.1で追加]**
- [ ] データベースクエリ実装
  - [ ] `updated_at DESC` でソート
  - [ ] **[v4.1] runnerパラメータ指定時はWHERE runner = ? を追加（サーバー側フィルタ）**
  - [ ] **[v4.1] LIMIT ? OFFSET ? によるページネーション実装**
  - [ ] **[v4.1] limitの最大値検証（200超えたら400エラー）**
- [ ] レスポンス実装（Thread配列）
- [ ] エラーハンドリング実装
  - [ ] 404: Room not found
  - [ ] 403: Room所有権エラー
  - [ ] **[v4.1] 400: limit超過エラー（limit > 200）**

#### B-1.4 Thread更新API実装（v4.1: device_id Query Parameter必須化）
- [ ] `PATCH /threads/{thread_id}` エンドポイント作成
- [ ] **[v4.1] Query Parameters実装**
  - [ ] **`device_id`: 必須、認証用（MASTER_SPECIFICATION.md v4.1で明記）**
- [ ] リクエストボディのバリデーション実装
  - [ ] `name`: オプショナル、1-100文字
- [ ] Thread存在確認実装
- [ ] **[v4.1] Room所有権確認実装（thread.room_id → room.device_id が device_id と一致するか検証）**
- [ ] データベース更新実装（updated_at自動更新）
- [ ] レスポンス実装（更新後のThread JSON）
- [ ] エラーハンドリング実装
  - [ ] 404: Thread not found
  - [ ] 403: 所有権エラー（device_id不一致）
  - [ ] 400: バリデーションエラー（name長さ超過など）

#### B-1.5 Thread削除API実装（v4.1: Jobs処理明確化 - CASCADE削除せず）
- [ ] `DELETE /threads/{thread_id}` エンドポイント作成
- [ ] Query parameters実装
  - [ ] `device_id`: 必須
- [ ] Thread存在確認実装
- [ ] Room所有権確認実装（thread.room_id → room.device_id が device_id と一致するか検証）
- [ ] **[v4.1] 削除時の動作確認（データベーススキーマのFOREIGN KEY制約に基づく）**
  - [ ] **Threadレコード削除（DELETE FROM threads WHERE id = ?）**
  - [ ] **関連Jobsのthread_idはNULLに設定（ON DELETE SET NULL）**
    - ❌ **JobsはCASCADE削除されない（v4.1で明確化）**
    - ✅ **Jobsは削除されず、thread_id=NULLとして保持される**
  - [ ] **関連DeviceSessionsはCASCADE削除（ON DELETE CASCADE）**
- [ ] データベース削除実装
- [ ] レスポンス実装（204 No Content）
- [ ] エラーハンドリング実装
  - [ ] 404: Thread not found
  - [ ] 403: 所有権エラー（device_id不一致）

#### B-1.6 APIテスト作成（v4.1準拠）
- [ ] Thread作成テスト（正常系）
- [ ] Thread作成テスト（異常系: Room不存在、所有権エラー）
- [ ] **[v4.1] Thread一覧取得テスト（正常系）**
- [ ] **[v4.1] Thread一覧取得テスト（runnerフィルタリング - サーバー側）**
  - [ ] `runner=claude` 指定時、claudeスレッドのみ返却されることを確認
  - [ ] `runner=codex` 指定時、codexスレッドのみ返却されることを確認
  - [ ] runner未指定時、全スレッドが返却されることを確認
- [ ] **[v4.1] Thread一覧取得テスト（ページネーション）**
  - [ ] `limit=10, offset=0` で最初の10件取得確認
  - [ ] `limit=10, offset=10` で次の10件取得確認
  - [ ] `limit=200` で最大200件取得確認
  - [ ] `limit=201` で400エラー確認（limit超過）
- [ ] **[v4.1] Thread更新テスト（正常系 - device_id Query Parameter）**
  - [ ] `device_id` 正しく指定時、更新成功確認
- [ ] **[v4.1] Thread更新テスト（異常系: device_id不一致）**
  - [ ] 他デバイスのThreadに対するPATCH時、403エラー確認
- [ ] Thread更新テスト（異常系: Thread不存在、バリデーションエラー）
- [ ] **[v4.1] Thread削除テスト（正常系 - Jobs SET NULL確認）**
  - [ ] Thread削除前にJobを作成（thread_id設定）
  - [ ] Thread削除実行
  - [ ] 削除後、関連Jobsのthread_idがNULLになることを確認
  - [ ] ❌ **JobsがCASCADE削除されないことを確認（重要）**
- [ ] **[v4.1] Thread削除テスト（DeviceSessions CASCADE削除確認）**
  - [ ] Thread削除前にDeviceSessionを作成（thread_id設定）
  - [ ] Thread削除実行
  - [ ] 削除後、関連DeviceSessionsが削除されることを確認
- [ ] Thread削除テスト（異常系: Thread不存在、所有権エラー）

#### B-1.7 デプロイ準備
- [ ] サーバー起動確認
- [ ] APIドキュメント更新（Swagger/OpenAPI）
- [ ] ログ出力確認

---

### Phase B-2: iOS実装（推定: 6時間）

#### B-2.1 データモデル確認
- [ ] `Thread.swift` モデル確認
  - [ ] プロパティ確認（id, roomId, name, runner, createdAt, updatedAt）
  - [ ] CodingKeys確認（snake_case ↔ camelCase変換）
  - [ ] Hashable, Identifiable準拠確認

#### B-2.2 APIClient拡張
- [ ] `APIClientProtocol` にThread APIメソッド追加
  ```swift
  func createThread(roomId: String, name: String, runner: String, deviceId: String) async throws -> Thread
  func fetchThreads(roomId: String, deviceId: String, runner: String?) async throws -> [Thread]
  func updateThread(threadId: String, name: String, deviceId: String) async throws -> Thread
  func deleteThread(threadId: String, deviceId: String) async throws
  ```
- [ ] `APIClient` にThread API実装
  - [ ] `createThread` 実装（POST /rooms/{room_id}/threads）
  - [ ] `fetchThreads` 実装（GET /rooms/{room_id}/threads）
  - [ ] `updateThread` 実装（PATCH /threads/{thread_id}）
  - [ ] `deleteThread` 実装（DELETE /threads/{thread_id}）
- [ ] エラーハンドリング実装
  - [ ] 404エラー処理
  - [ ] 403エラー処理
  - [ ] 400エラー処理
  - [ ] ネットワークエラー処理

#### B-2.3 PreviewAPIClient対応
- [ ] `PreviewAPIClient` にThread APIモック実装
  - [ ] `createThread` モック（UUID生成、配列に追加）
  - [ ] `fetchThreads` モック（フィルタリング実装）
  - [ ] `updateThread` モック（配列内更新）
  - [ ] `deleteThread` モック（配列から削除）
- [ ] モックデータ準備（サンプルThread配列）

#### B-2.4 ThreadListViewModel修正
- [ ] `fetchThreads()` メソッド修正
  - [ ] `apiClient.fetchThreads()` 呼び出し実装
  - [ ] エラーハンドリング実装
  - [ ] `isLoading` 状態管理実装
- [ ] `createThread()` メソッド修正
  - [ ] `apiClient.createThread()` 呼び出し実装
  - [ ] 作成後のThread配列更新実装
  - [ ] エラーハンドリング実装
- [ ] `updateThreadName()` メソッド修正
  - [ ] `apiClient.updateThread()` 呼び出し実装
  - [ ] 更新後のThread配列更新実装
  - [ ] エラーハンドリング実装
- [ ] `deleteThread()` メソッド修正
  - [ ] `apiClient.deleteThread()` 呼び出し実装
  - [ ] 削除後のThread配列更新実装
  - [ ] エラーハンドリング実装

#### B-2.5 RoomDetailView修正（重要: View再生成問題の解決）
- [ ] `.id()` 修飾子削除
  - [ ] [RoomDetailView.swift:105](../../iOS_WatchOS/RemotePrompt/RemotePrompt/Views/RoomDetailView.swift#L105) の `.id("\(thread.id)-\(selectedRunner.rawValue)")` を削除
- [ ] ChatViewの動的更新対応
  - [ ] runner変更時にChatViewModelを再生成せずに更新する仕組み実装
  - [ ] 方法1: ChatViewModelに `updateRunner(_ runner: String)` メソッド追加
  - [ ] 方法2: ChatViewに `runner` をBindingで渡し、変更検知でreload
- [ ] Thread選択時の正しいthread_id渡し確認
  - [ ] `chatViewContainer(for thread: Thread)` でthread.idが正しく渡されているか確認

#### B-2.6 ChatViewModel修正
- [ ] threadIdの使用確認
  - [ ] `init` でthreadIdを受け取っているか確認
  - [ ] `createJob` APIでthreadIdが正しく送信されているか確認
  - [ ] `fetchMessages` APIでthreadIdが正しく送信されているか確認
- [ ] runner動的更新対応（B-2.5の方法1の場合）
  - [ ] `updateRunner(_ runner: String)` メソッド追加
  - [ ] runner変更時にメッセージ再読み込み実装
  - [ ] SSE接続のクリーンアップ実装

#### B-2.7 ThreadListView確認
- [ ] Thread一覧表示確認
- [ ] Thread作成ダイアログ確認
- [ ] Thread編集ダイアログ確認
- [ ] Thread削除スワイプアクション確認
- [ ] Thread選択時のコールバック確認

#### B-2.8 ビルド・コンパイル確認
- [ ] Xcodeビルド実行
- [ ] ビルドエラー解消
- [ ] 警告解消
- [ ] コード整形（SwiftLint）

---

### Phase B-3: 統合テスト（推定: 2時間）

#### B-3.1 Thread CRUD動作確認
- [ ] Room一覧からRoom選択
- [ ] Thread一覧が表示されることを確認
- [ ] 「新しいスレッド」ボタンでThread作成ダイアログ表示確認
- [ ] Thread作成（名前入力 → 作成）
- [ ] 作成したThreadが一覧の先頭に表示されることを確認
- [ ] Thread編集（スワイプ → 編集 → 名前変更）
- [ ] 編集後の名前が反映されることを確認
- [ ] Thread削除（スワイプ → 削除）
- [ ] 削除したThreadが一覧から消えることを確認

#### B-3.2 Thread別履歴管理確認
- [ ] Thread A作成 → Thread A選択 → Claude Codeでメッセージ送信
- [ ] Thread A → Codexに切り替え → メッセージ送信
- [ ] Thread一覧に戻る → Thread B作成 → Thread B選択
- [ ] Thread B → Claude Codeでメッセージ送信
- [ ] Thread B → Codexに切り替え → メッセージ送信
- [ ] Thread一覧に戻る → Thread A再選択
- [ ] Thread A → Claude Codeの履歴が正しく表示されることを確認
- [ ] Thread A → Codexに切り替え → Thread A Codexの履歴が正しく表示されることを確認
- [ ] Thread一覧に戻る → Thread B再選択
- [ ] Thread B → Claude Codeの履歴が正しく表示されることを確認
- [ ] Thread B → Codexの履歴が正しく表示されることを確認

#### B-3.3 Runner切り替え動作確認（View再生成問題の解決確認）
- [ ] Thread選択 → Claude Code表示
- [ ] メッセージ送信 → SSE接続確立確認
- [ ] 送信中にCodexタブに切り替え
- [ ] ❌ **「Request interrupted by user」エラーが表示されないことを確認**（重要）
- [ ] Codexタブでメッセージ送信
- [ ] Claude Codeタブに戻る
- [ ] Claude Codeの履歴が正しく表示されることを確認
- [ ] Codexタブに戻る
- [ ] Codexの履歴が正しく表示されることを確認

#### B-3.4 エラーハンドリング確認
- [ ] ネットワーク切断時のThread作成エラー表示確認
- [ ] ネットワーク切断時のThread一覧取得エラー表示確認
- [ ] 不正なThread ID指定時の404エラー表示確認
- [ ] 他デバイスのThreadアクセス時の403エラー表示確認

#### B-3.5 パフォーマンス確認
- [ ] Thread一覧の読み込み速度確認（100 Thread時）
- [ ] Thread切り替え時のレスポンス確認
- [ ] Runner切り替え時のレスポンス確認（View再生成なし）
- [ ] メッセージ送信時のレスポンス確認

#### B-3.6 サーバーログ確認
- [ ] Thread作成時のログ確認
  - [ ] `Created thread {thread_id} in room {room_id} for runner {runner}`
- [ ] Thread取得時のログ確認
  - [ ] `Fetched {count} threads from room {room_id}`
- [ ] Session管理ログ確認
  - [ ] `Starting new {runner} session {session_id} for device {device_id} in room {room_id} thread {thread_id}`
- [ ] エラーログ確認（意図的にエラーを発生させて確認）

#### B-3.7 互換モードテスト（v4.1: thread_id=NULL処理確認）

**目的**: v3.x（旧バージョン）クライアントがthread_idパラメータを送信しない場合でも正常動作することを確認

- [ ] **互換モード - Job作成テスト（thread_id=nil送信）**
  - [ ] `POST /jobs` API呼び出し時に `thread_id` パラメータを **送信しない（nilまたは未指定）**
  - [ ] サーバー側でthread_id=NULLとしてJobが作成されることを確認
  - [ ] レスポンスが正常に返却されることを確認（200 OK）
  - [ ] データベースで `jobs.thread_id IS NULL` を確認

- [ ] **互換モード - メッセージ取得テスト（thread_id=nil送信）**
  - [ ] `GET /messages` API呼び出し時に `thread_id` パラメータを **送信しない（nilまたは未指定）**
  - [ ] サーバー側で `WHERE thread_id IS NULL` でフィルタリングされることを確認
  - [ ] thread_id=NULLのJobsのみが返却されることを確認
  - [ ] thread_id指定のJobsは返却されないことを確認（他スレッドとの分離）

- [ ] **互換モード - Session管理テスト（thread_id=NULL）**
  - [ ] thread_id=nilでJob作成時、device_sessionsテーブルに `thread_id=NULL` で登録されることを確認
  - [ ] サーバーログで `thread=NULL` または `thread=default` のようなログが出力されることを確認
  - [ ] thread_id指定のSessionとは独立していることを確認

- [ ] **混在モードテスト（v3.x互換 + v4.x Thread併用）**
  - [ ] Room内に以下のJobsを作成:
    - Thread A指定Job（thread_id="uuid-a"）
    - Thread B指定Job（thread_id="uuid-b"）
    - 互換モードJob（thread_id=NULL）
  - [ ] `GET /messages?thread_id=uuid-a` 呼び出し → Thread Aのみ返却確認
  - [ ] `GET /messages?thread_id=uuid-b` 呼び出し → Thread Bのみ返却確認
  - [ ] `GET /messages` （thread_id未指定）呼び出し → thread_id=NULLのみ返却確認
  - [ ] 各履歴が独立して保持されていることを確認

- [ ] **互換モード - iOS旧バージョンシミュレート**
  - [ ] `ChatViewModel` の `init` で `threadId: nil` を明示的に指定
  - [ ] メッセージ送信・取得が正常動作することを確認
  - [ ] サーバーログで互換モード動作を確認

---

## 🎯 完了基準

### Phase B-1完了基準
- [ ] Thread Management API 4つすべてが正常動作
- [ ] APIテストがすべてパス
- [ ] サーバーログにエラーなし

### Phase B-2完了基準
- [ ] Xcodeビルドが成功
- [ ] ThreadListViewModelがAPIを正しく呼び出せる
- [ ] RoomDetailViewの`.id()`修飾子が削除され、runner切り替え時にView再生成が発生しない
- [ ] ChatViewModelがthreadIdを正しく使用している

### Phase B-3完了基準
- [ ] Thread CRUD操作がすべて正常動作
- [ ] Thread別履歴が独立して保持される
- [ ] Runner切り替え時に「Request interrupted by user」エラーが発生しない ← **最重要**
- [ ] サーバーログで4次元session管理が正しく動作している
- [ ] **[v4.1] 互換モード（thread_id=NULL）が正常動作する**
  - [ ] thread_id未指定でのJob作成・取得が正常動作
  - [ ] thread_id指定と未指定の履歴が独立して保持される
  - [ ] 混在モード（v3.x互換 + v4.x Thread併用）が正常動作

### 全体完了基準
- [ ] Phase B-1, B-2, B-3のすべての完了基準を満たす
- [ ] **[v4.1] MASTER_SPECIFICATION.md v4.1準拠確認**
  - [ ] runnerフィルタ: サーバー側実装
  - [ ] limit/offset: ページネーション実装
  - [ ] PATCH device_id: Query Parameter必須化
  - [ ] DELETE Jobs: thread_id=NULL（CASCADE削除せず）
  - [ ] 互換モード: thread_id=NULL処理実装
- [ ] 実装計画書（本ファイル）のチェックリストがすべて完了

---

## 📊 工数見積もり

| フェーズ | タスク | 工数 |
|---------|--------|------|
| Phase B-1 | データベースモデル確認 | 0.5h |
| Phase B-1 | Thread作成API実装 | 1h |
| Phase B-1 | Thread一覧取得API実装 | 1h |
| Phase B-1 | Thread更新API実装 | 0.5h |
| Phase B-1 | Thread削除API実装 | 0.5h |
| Phase B-1 | APIテスト作成 | 1h |
| Phase B-1 | デプロイ準備 | 0.5h |
| **Phase B-1 合計** | | **5h** |
| | | |
| Phase B-2 | データモデル確認 | 0.5h |
| Phase B-2 | APIClient拡張 | 1.5h |
| Phase B-2 | PreviewAPIClient対応 | 0.5h |
| Phase B-2 | ThreadListViewModel修正 | 1h |
| Phase B-2 | RoomDetailView修正（`.id()`削除） | 1h |
| Phase B-2 | ChatViewModel修正 | 1h |
| Phase B-2 | ThreadListView確認 | 0.5h |
| Phase B-2 | ビルド・コンパイル確認 | 0.5h |
| **Phase B-2 合計** | | **6.5h** |
| | | |
| Phase B-3 | Thread CRUD動作確認 | 0.5h |
| Phase B-3 | Thread別履歴管理確認 | 1h |
| Phase B-3 | Runner切り替え動作確認 | 0.5h |
| Phase B-3 | エラーハンドリング確認 | 0.5h |
| Phase B-3 | パフォーマンス確認 | 0.5h |
| Phase B-3 | サーバーログ確認 | 0.5h |
| Phase B-3 | **[v4.1] 互換モードテスト** | **1h** |
| **Phase B-3 合計** | | **4.5h** |
| | | |
| **総合計** | | **16h** |

---

## 🚨 リスク管理

### リスク1: API仕様の不整合
**内容**: バックエンドAPIとiOSクライアントのリクエスト/レスポンス形式が一致しない
**影響度**: 高
**対策**:
- [ ] APIエンドポイントをPostman/cURLで事前テスト
- [ ] レスポンスJSONをSwiftモデルと照合
- [ ] CodingKeysのsnake_case/camelCase変換を確認

### リスク2: View再生成問題の解決失敗
**内容**: `.id()`削除後もrunner切り替え時にエラーが発生する
**影響度**: 高
**対策**:
- [ ] ChatViewModelのライフサイクルをログで確認
- [ ] SSE接続のクリーンアップを確認
- [ ] 代替案: runner変更時にChatViewModelを再生成するが、進行中のリクエストを適切にキャンセル

### リスク3: 既存データとの整合性
**内容**: 既存のJobsが新しいThread構造と整合しない
**影響度**: 中
**対策**:
- [ ] 既存JobsのthreadIdを確認
- [ ] マイグレーションスクリプトが必要か検討
- [ ] 既存データのバックアップ

### リスク4: CASCADE削除の影響（v4.1で明確化済み）
**内容**: Thread削除時にJobsやdevice_sessionsが意図せず削除される
**影響度**: 中
**対策**:
- [ ] データベーススキーマのFOREIGN KEY制約を確認
  - [ ] **[v4.1] jobs.thread_id: ON DELETE SET NULL を確認（CASCADE削除されない）**
  - [ ] **[v4.1] device_sessions.thread_id: ON DELETE CASCADE を確認**
- [ ] Thread削除APIでCASCADE削除の動作をテスト
- [ ] ユーザーに削除確認ダイアログを表示

### リスク5: 互換モード（thread_id=NULL）の不整合（v4.1追加）
**内容**: thread_id=NULL処理が不十分で、旧バージョンクライアントが動作しない
**影響度**: 高
**対策**:
- [ ] **[v4.1] サーバー側でthread_id未指定時の処理を明示的に実装**
  - [ ] POST /jobs API: thread_id未指定 → NULLで保存
  - [ ] GET /messages API: thread_id未指定 → WHERE thread_id IS NULL
- [ ] **[v4.1] 混在モードテスト実施（v3.x互換 + v4.x Thread併用）**
- [ ] **[v4.1] データベースインデックス確認（thread_id IS NULLクエリの最適化）**

---

## 📝 メモ

### Phase A完了内容（前提）
- [x] Runner Picker（Segmented Control）実装
- [x] RoomDetailView統合
- [x] ChatView表示切り替え実装
- [x] MessageStore Runner別管理実装

### Phase B開始前の状態
- ThreadListViewModel: APIメソッドが未実装（コンパイルエラー）
- RoomDetailView: `.id()` 修飾子によりrunner切り替え時にView再生成
- ChatViewModel: threadIdを受け取るが、実際には機能していない可能性
- サーバー: Thread Management APIが未実装

### Phase B完了後の期待状態
- Thread CRUD操作が完全動作
- Thread別×Runner別で独立した履歴管理
- Runner切り替え時にView再生成なし → エラーなし
- サーバーログで4次元session管理が明確に確認できる

---

**更新日**: 2025-01-21
**作成者**: Claude Code
**ステータス**: 実装待ち
