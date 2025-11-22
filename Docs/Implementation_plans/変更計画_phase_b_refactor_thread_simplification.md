# Phase B-Refactor: Thread仕様シンプル化実装計画（v4.2）

**親元実装計画**: [`Docs/Implementation_plans/thread_management_v2.1_final.md`](thread_management_v2.1_final.md)
**作成日**: 2025-01-21
**目的**: Thread.runnerフィールドを削除し、同一Thread内でrunner自由切替を可能にする

**背景**:
Phase B完了後のコードレビューで、v4.1設計に3つの重大な問題が発見された:
1. ChatViewModel.updateRunner()がrunnerのみ更新、threadId固定 → runner切替時に400エラー
2. MessageStoreが(roomId, runner)のみでキャッシュ、threadId非考慮 → 履歴混在
3. updateRunner()が並行フェッチ未キャンセル → レースコンディション

この変更計画は、上記問題を根本解決するため、Thread.runnerを削除しThread=純粋な会話コンテナ化する設計変更。

**対象ファイル（修正対象）**:
- Backend: `remote-job-server/models.py`, `remote-job-server/main.py`, `remote-job-server/migrations/v4_2_remove_thread_runner.py`
- iOS: `iOS_WatchOS/RemotePrompt/RemotePrompt/Models/Thread.swift`, `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/APIClient.swift`, `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/MessageStore.swift`, `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ThreadListViewModel.swift`
- Documentation: `Docs/Specifications/Master_Specification.md`, `README.md`

**影響範囲**: バックエンド（models, main, migrations）、iOS（わずかな修正のみ）

---

## 📁 影響を受けるファイル一覧

### Backend（親元ファイル）

#### ✅ 修正が必要なファイル
| ファイルパス | 役割 | 修正内容 |
|------------|------|---------|
| `remote-job-server/models.py` | データベースモデル定義 | Thread.runnerカラム削除、インデックス削除、to_dict()修正 |
| `remote-job-server/main.py` | FastAPI エンドポイント定義 | Thread作成/一覧取得/Job作成APIのrunner関連処理削除（~20箇所） |
| `migrations/v4_2_remove_thread_runner.py` | マイグレーションスクリプト（新規作成） | threadsテーブル再作成、runnerカラム削除、データ移行 |

#### 🔍 参照のみ（修正不要）
| ファイルパス | 役割 | 備考 |
|------------|------|------|
| `remote-job-server/database.py` | データベース接続・初期化 | 変更不要（参考用） |
| `remote-job-server/db.py` | SQLAlchemy Base定義 | 変更不要（参考用） |
| `remote-job-server/config.py` | 設定管理 | 変更不要（参考用） |
| `migrations/v4_1_fix_room_foreign_keys.py` | v4.1マイグレーション | 参考用（同様のパターンでv4.2作成） |

---

### iOS（親元ファイル）

#### ✅ 修正が必要なファイル
| ファイルパス | 役割 | 修正内容 |
|------------|------|---------|
| `iOS_WatchOS/RemotePrompt/RemotePrompt/Models/Thread.swift` | Threadモデル定義 | Thread.runnerプロパティ削除、CreateThreadRequest.runner削除 |
| `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/APIClient.swift` | APIクライアント実装 | createThread/fetchThreadsメソッドからrunner引数削除 |
| `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/MessageStore.swift` | **重大**: メッセージキャッシュ | Contextに`threadId`を追加し3次元キー`(roomId, runner, threadId)`に変更。現状の2次元キーでは同一room・runner内の複数threadで履歴が混在する |
| `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ThreadListViewModel.swift` | Thread一覧管理 | runner指定削除、クライアント側フィルタリング実装 |
| `iOS_WatchOS/RemotePrompt/RemotePrompt/Preview Content/PreviewAPIClient.swift` | プレビュー用モック | モックデータからrunner削除 |

#### 🔍 参照のみ（修正不要）
| ファイルパス | 役割 | 備考 |
|------------|------|------|
| `iOS_WatchOS/RemotePrompt/RemotePrompt/ViewModels/ChatViewModel.swift` | チャット管理 | updateRunner()メソッドはそのまま動作（v4.2対応済み） |
| `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/RoomDetailView.swift` | Room詳細画面 | 既存実装そのまま動作（確認のみ） |

---

### Documentation（親元ファイル）

#### ✅ 修正が必要なファイル
| ファイルパス | 役割 | 修正内容 |
|------------|------|---------|
| `Docs/Specifications/Master_Specification.md` | 全体仕様書 | v4.2変更点セクション追加、Thread API仕様修正 |
| `README.md` | プロジェクト概要 | v4.2変更点・マイグレーション手順追記 |
| `Docs/Implementation_plans/変更計画_phase_b_refactor_thread_simplification.md` | 本実装計画書 | 進捗に応じてチェックリスト更新 |

---

### ファイル構造図

```
RemotePrompt/
├── remote-job-server/          # Backend
│   ├── models.py               ← [修正] Thread.runnerカラム削除
│   ├── main.py                 ← [修正] Thread API修正（~20箇所）
│   ├── database.py             ← [参照] DB接続
│   ├── db.py                   ← [参照] Base定義
│   ├── config.py               ← [参照] 設定
│   └── migrations/
│       ├── v4_1_fix_room_foreign_keys.py  ← [参照] パターン参考
│       └── v4_2_remove_thread_runner.py   ← [新規] 作成予定
├── iOS_WatchOS/RemotePrompt/RemotePrompt/  # iOS
│   ├── Models/
│   │   └── Thread.swift        ← [修正] runnerプロパティ削除
│   ├── Services/
│   │   ├── MessageStore.swift  ← [修正] 3次元キー(roomId,runner,threadId)に変更
│   │   └── APIClient.swift     ← [修正] runner引数削除
│   ├── ViewModels/
│   │   ├── ThreadListViewModel.swift  ← [修正] クライアント側フィルタ
│   │   └── ChatViewModel.swift        ← [参照] 動作確認のみ
│   ├── Views/
│   │   └── RoomDetailView.swift       ← [参照] 動作確認のみ
│   └── Preview Content/
│       └── PreviewAPIClient.swift     ← [修正] モック修正
└── Docs/                       # Documentation
    ├── Specifications/
    │   └── Master_Specification.md  ← [修正] v4.2仕様追記
    ├── Implementation_plans/
    │   └── 変更計画_phase_b_refactor_thread_simplification.md  ← [本ファイル]
    └── README.md               ← [修正] v4.2変更点追記
```

---

## 📋 変更の背景

### 現状の問題点（v4.1）

1. **Thread.runner固定**: Thread作成時にrunnerが固定され、後から変更不可
2. **整合性チェックが厳しすぎる**: Job作成時に`thread.runner != job.runner`なら400エラー
3. **iOS実装が複雑化**: Runner切替時にThread自動切替またはMessageStore大幅修正が必要

### v4.2での解決方針

✅ **Thread = 会話履歴のコンテナ**として機能
✅ **Runnerは自由に切替可能**（同一Thread内でClaudeとCodexを混在可能）
✅ **iOS実装は現状のまま動作**（updateRunner()そのまま使える）
✅ **4次元管理達成**: `(device_id, room_id, runner, thread_id)`で履歴分離

---

## ✅ 実装チェックリスト

### Refactor-1: バックエンドスキーマ変更（推定: 2時間）

#### R-1.1 models.py修正
- [x] Thread.runnerカラム削除
  - [x] `runner = Column(String(20), ...)` 行を削除
  - [x] `to_dict()`メソッドから`"runner": self.runner`削除
  - [x] `Index("idx_threads_room_runner", "room_id", "runner")`削除
- [x] Thread.to_dict()修正
  - [x] レスポンスから`runner`フィールド削除
- [x] ビルド確認（import/参照エラーチェック）

#### R-1.2 マイグレーションスクリプト作成
- [x] `migrations/v4_2_remove_thread_runner.py`作成
- [x] 既存threadsテーブルバックアップ
- [x] threadsテーブル再作成（runnerカラムなし）
  - [x] `id, room_id, name, device_id, created_at, updated_at`のみ
  - [x] FOREIGN KEY(room_id) ON DELETE CASCADE維持
- [x] インデックス再作成
  - [x] `idx_threads_room_id` (room_id単独)
  - [x] `idx_threads_updated_at` (updated_at)
- [x] データ復元（runner列を除外してコピー）
- [x] 検証
  - [x] 新スキーマにrunnerカラムがないことを確認
  - [x] データ件数が一致することを確認
- [x] ロールバック処理実装

#### R-1.3 マイグレーション実行
- [x] データベースバックアップ作成
  - [x] `cp data/jobs.db data/jobs.db.backup_before_v4.2`
- [x] マイグレーション実行
  - [x] `python3 migrations/v4_2_remove_thread_runner.py --auto-approve`
- [x] 実行結果確認
  - [x] threadsテーブルのrunnerカラム削除確認
  - [x] 既存Thread件数確認（6件）
  - [x] インデックス確認（2個: idx_threads_room_id, idx_threads_updated_at）

---

### Refactor-2: バックエンドAPI修正（推定: 1.5時間）

#### R-2.1 Thread作成API修正（POST /rooms/{room_id}/threads）
- [x] `main.py` CreateThreadRequest修正
  - [x] `runner`フィールド削除
  - [x] Pydantic modelから`runner: str`削除
- [x] Thread作成処理修正
  - [x] `Thread(runner=body.runner, ...)`削除
  - [x] `Thread(name=body.name, room_id=...)`のみ
- [x] レスポンス確認
  - [x] `runner`フィールドが含まれないことを確認
- [x] エラーハンドリング確認
  - [x] 404: Room not found（維持）
  - [x] 403: 所有権エラー（維持）
  - [x] 400: nameバリデーション（維持）

#### R-2.2 Thread一覧取得API修正（GET /rooms/{room_id}/threads）
- [x] Query parameter `runner`削除
  - [x] `runner: Optional[str] = Query(None)`削除
  - [x] サーバー側runnerフィルタリング削除
- [x] クエリ修正
  - [x] `if runner: query = query.filter_by(runner=runner)`削除
  - [x] `query.order_by(Thread.updated_at.desc())`のみ維持
- [x] レスポンス確認
  - [x] 全Thread返却（runner関係なく）
  - [x] `runner`フィールドが含まれないことを確認

#### R-2.3 Job作成API修正（POST /jobs）
- [x] Thread整合性チェック削除
  - [x] POST /jobsのthread.runnerチェック削除（500-501行目）
  - [x] GET /messagesのthread.runnerチェック削除（587-589行目）
  - [x] _get_or_create_default_thread関数修正（runnerカラム除外）
  - [x] Thread存在確認のみ残す
- [x] 動作確認
  - [x] 任意のrunnerでJob作成可能
  - [x] thread_id指定時もrunner不問

#### R-2.4 ThreadResponse回帰防止テスト追加
- [x] test_thread_response_schema_v4_2 追加
  - [x] POST /rooms/{room_id}/threads レスポンス検証
  - [x] GET /rooms/{room_id}/threads レスポンス検証
  - [x] PATCH /threads/{thread_id} レスポンス検証
  - [x] runnerフィールドが含まれないことを確認
- [x] test_session_endpoints 修正
  - [x] Thread作成時にrunnerパラメータ削除

#### R-2.5 Master_Specification.md更新
- [x] Thread作成APIドキュメント修正
  - [x] POST /threads リクエストから`runner`削除
  - [x] レスポンス例から`runner`削除
- [x] Thread一覧取得APIドキュメント修正
  - [x] GET /threads Query parameterから`runner`削除
  - [x] レスポンス例から`runner`削除
- [x] 仕様変更セクション追加
  - [x] v4.2変更点を明記（Section 15追加）

---

### Refactor-3: iOS修正（推定: 1時間）

#### R-3.1 Thread.swift修正
- [x] `Thread`モデルから`runner`プロパティ削除
  - [x] `let runner: String`削除
  - [x] `CodingKeys`から`case runner`削除
- [x] `CreateThreadRequest`から`runner`削除
  - [x] `let runner: String`削除
  - [x] `CodingKeys`から`case runner`削除
- [x] コンパイル確認

#### R-3.2 APIClient.swift修正
- [x] `createThread`メソッドシグネチャ変更
  - [x] `runner: String`パラメータ削除
  - [x] リクエストボディから`runner`削除
- [x] `fetchThreads`メソッドシグネチャ変更
  - [x] `runner: String?`パラメータ削除
  - [x] URLから`runner`クエリパラメータ削除
- [x] APIClientProtocol 修正
  - [x] プロトコル定義から runner パラメータ削除
- [x] コンパイル確認

#### R-3.3 MessageStore.swift修正（重大）
- [x] `Context`構造体に`threadId`追加
  - [x] `let threadId: String`追加
  - [x] 2次元キー`(roomId, runner)` → 3次元キー`(roomId, runner, threadId)`
- [x] `setActiveContext`メソッド修正
  - [x] `threadId: String`パラメータ追加
  - [x] `Context(roomId: roomId, runner: runner, threadId: threadId)`
- [x] `init`メソッド修正
  - [x] `defaultThreadId: String`パラメータ追加
- [x] ChatViewModel.swift呼び出し修正
  - [x] `messageStore.setActiveContext(roomId: roomId, runner: runner, threadId: threadId)`（2箇所）
  - [x] `updateRunner()`内でも3次元キーを使用
- [x] 動作確認
  - [x] 同一room・runner内で異なるthreadの履歴が混在しないことを確認
  - [x] Thread切替時に履歴が正しく切り替わることを確認

#### R-3.4 ThreadListViewModel.swift修正
- [x] `createThread`呼び出し修正
  - [x] `runner: selectedRunner.rawValue`削除
  - [x] `roomId, name, deviceId`のみ渡す
- [x] `fetchThreads`呼び出し修正
  - [x] `runner: runnerFilter`削除
  - [x] 全Thread取得（クライアント側フィルタはコメントで記載）

#### R-3.5 PreviewAPIClient.swift修正
- [x] モックThread配列から`runner`削除
- [x] `createThread`モックから`runner`削除
- [x] `fetchThreads`モックから`runner`フィルタ削除
- [x] `updateThread`モックから`runner`削除

#### R-3.6 RoomDetailView.swift確認
- [x] 既存実装そのまま動作確認
- [x] `updateRunner()`が正常動作することを確認
- [x] runner切替時にthreadId固定で動作確認

---

### Refactor-4: 動作テスト（推定: 1.5時間）

#### R-4.1 バックエンド単体テスト
- [x] Thread作成テスト
  - [x] runnerなしでThread作成可能
  - [x] レスポンスにrunnerが含まれない
- [x] Thread一覧取得テスト
  - [x] runner指定なしで全Thread取得
  - [x] 複数Threadが返却される（本番環境で確認済み）
- [ ] Job作成テスト（Thread指定あり）
  - [ ] claudeでThread作成 → codexでJob作成 → 成功
  - [ ] 同一Thread内でrunner混在可能

#### R-4.2 iOS統合テスト
- [x] Thread作成テスト
  - [x] "新機能開発"Thread作成
  - [x] サーバー側でThread作成成功
- [x] Runner切替テスト
  - [x] Thread選択 → runner=claude → メッセージ送信（成功）
  - [ ] runner=codexに切替 → メッセージ送信（Codex `-a` エラー調査中）
  - [ ] 同一Thread内でClaudeとCodex混在確認
- [x] 履歴分離テスト
  - [x] runner=claudeで履歴取得 → Claudeメッセージのみ表示（確認済み）
  - [ ] runner=codexで履歴取得 → Codexメッセージのみ表示
  - [ ] 4次元管理 `(device_id, room_id, runner, thread_id)` 達成確認

#### R-4.3 エラーケーステスト
- [ ] 存在しないThread指定
  - [ ] Job作成時に404エラー
- [ ] 所有権エラー
  - [ ] 他deviceのThreadに対して403エラー

---

### Refactor-5: ドキュメント更新（推定: 0.5時間）

#### R-5.1 仕様書更新
- [ ] Master_Specification.md
  - [ ] v4.2変更点セクション追加
  - [ ] Thread APIドキュメント修正
- [ ] 変更計画_phase_b_refactor_thread_simplification.md（本ファイル）
  - [ ] 完了チェックリスト更新

#### R-5.2 README更新
- [ ] v4.2の主な変更点を記載
- [ ] マイグレーション手順を記載

---

## 🎯 完了基準

### Refactor-1完了基準
- [x] threadsテーブルからrunnerカラム削除完了
- [x] マイグレーション実行成功
- [x] データ件数不変

### Refactor-2完了基準
- [x] Thread作成APIがrunnerなしで動作
- [x] Thread一覧取得APIがrunner指定なしで全Thread返却
- [x] Job作成APIで任意のrunnerが使用可能（整合性チェックなし）
- [x] ThreadResponse回帰防止テスト追加完了

### Refactor-3完了基準
- [x] iOSビルド成功
- [x] Thread作成時にrunner指定不要
- [x] runner切替時にthreadId固定で動作
- [x] **MessageStore 3次元キー対応完了**（同一room・runner内の異なるthreadで履歴が混在しない）

### Refactor-4完了基準
- [ ] 同一Thread内でClaudeとCodex混在可能
- [ ] runner切替時に"Request interrupted by user"エラーなし
- [ ] **4次元履歴管理達成**: MessageStoreが`(device_id, room_id, runner, thread_id)`で完全に分離

### 全体完了基準
- [ ] Refactor-1〜5のすべての完了基準を満たす
- [ ] Master_Specification.md v4.2準拠
- [ ] 本実装計画書のチェックリストがすべて完了

---

## 📊 工数見積もり

| フェーズ | タスク | 工数 |
|---------|--------|------|
| Refactor-1 | models.py修正 | 0.5h |
| Refactor-1 | マイグレーションスクリプト作成 | 1h |
| Refactor-1 | マイグレーション実行 | 0.5h |
| **Refactor-1 合計** | | **2h** |
| | | |
| Refactor-2 | Thread作成API修正 | 0.5h |
| Refactor-2 | Thread一覧取得API修正 | 0.5h |
| Refactor-2 | Job作成API修正 | 0.3h |
| Refactor-2 | Master_Specification.md更新 | 0.2h |
| **Refactor-2 合計** | | **1.5h** |
| | | |
| Refactor-3 | Thread.swift修正 | 0.3h |
| Refactor-3 | APIClient.swift修正 | 0.3h |
| Refactor-3 | **MessageStore.swift修正（重大）** | **0.5h** |
| Refactor-3 | ThreadListViewModel.swift修正 | 0.2h |
| Refactor-3 | PreviewAPIClient.swift修正 | 0.1h |
| Refactor-3 | RoomDetailView.swift確認 | 0.1h |
| **Refactor-3 合計** | | **1.5h** |
| | | |
| Refactor-4 | バックエンド単体テスト | 0.5h |
| Refactor-4 | iOS統合テスト | 0.8h |
| Refactor-4 | エラーケーステスト | 0.2h |
| **Refactor-4 合計** | | **1.5h** |
| | | |
| Refactor-5 | ドキュメント更新 | 0.5h |
| **Refactor-5 合計** | | **0.5h** |
| | | |
| **総合計** | | **7.0h** |

---

## 🚨 リスク管理

### リスク1: 既存Threadデータの互換性
**内容**: 既存のThread.runnerデータが失われる
**影響度**: 低（runnerはJob側で保持されているため、履歴は維持される）
**対策**:
- [ ] マイグレーション前にデータベースバックアップ
- [ ] 既存Jobsのrunnerはそのまま保持される
- [ ] Thread一覧表示は影響なし

### リスク2: iOS実装の後方互換性
**内容**: v4.1クライアントが動作しなくなる
**影響度**: 中
**対策**:
- [ ] サーバー側でrunnerパラメータを受け取っても無視（エラーにしない）
- [ ] レスポンスにrunnerを含めない（クライアント側で不要）

### リスク3: MessageStore履歴混在（重大）
**内容**: 現状のMessageStoreは2次元キー`(roomId, runner)`のため、Thread.runner削除後に同一room・runner内の複数threadで履歴が混在する
**影響度**: 高（4次元履歴管理の根幹に関わる）
**対策**:
- [x] MessageStore.Contextに`threadId`を追加し3次元キーに変更（R-3.3で対応）
- [x] ChatViewModel.setActiveContextを3次元に修正
- [ ] 動作テストで履歴分離を確認（R-4.2で検証）

### リスク4: ThreadListViewのフィルタリング
**内容**: サーバー側フィルタがなくなり、全Thread取得するため遅延の可能性
**影響度**: 低（Thread数は通常50件以下）
**対策**:
- [ ] クライアント側でメモリ内フィルタリング（高速）
- [ ] 将来的にページネーションで最適化可能

---

## 📝 変更の影響範囲

### ✅ 変更なし（影響なし）
- Jobs（runnerはJob側で保持）
- DeviceSessions（runner保持、4次元管理維持）
- ChatViewModel（updateRunner()そのまま使える）
- RoomDetailView（既存実装そのまま動作）

### ⚠️ 変更あり（修正必要）
- **models.py Thread**（runnerカラム削除）
- **main.py Thread API**（runner削除）
- **Thread.swift**（runnerプロパティ削除）
- **APIClient**（runner引数削除）
- **MessageStore.swift**（**重大**: 3次元キー`(roomId, runner, threadId)`に変更）
- **ThreadListViewModel**（runnerフィルタをクライアント側に移行）

---

## 🎉 期待される効果

### ユーザー体験の向上
✅ **同一Thread内でrunner自由切替**
✅ **会話の文脈を保ちながらAI切替**
✅ **直感的なUI（Thread = 会話、Runner = AIモード）**

### 実装のシンプル化
✅ **iOS実装が単純化**（updateRunner()で完結）
✅ **サーバー側の整合性チェック削除**（複雑性低減）
⚠️ **MessageStore 3次元キー対応**（threadId追加で4次元履歴管理達成）

### 保守性の向上
✅ **Threadテーブルの責務明確化**（履歴コンテナのみ）
✅ **Runnerの責務はJob側に集約**（データ整合性向上）
✅ **拡張性向上**（将来的なrunner追加が容易）

---

---

### Refactor-6: iOS SSE・UI修正（追加実装: 2025-01-22）

#### R-6.1 SSEManager.swift: メインスレッドブロッキング修正
- [x] URLSession delegateQueue修正
  - [x] `delegateQueue: nil` → `delegateQueue: .main`（line 22）
  - [x] デリゲートコールバックをメインスレッドで実行
- [x] 不要なDispatchQueue.main.async削除
  - [x] 既にメインスレッドで実行されるため、ラッパー削除（line 88-94）
- [x] ビルド確認
  - [x] コンパイルエラー解消

#### R-6.2 ChatViewModel.swift: 推論中入力有効化修正
- [x] isLoading管理修正
  - [x] Job作成成功後に`isLoading = false`（line 239）
  - [x] 推論中でも入力フィールド有効化
- [x] SSEクリーンアップ追加
  - [x] Terminal status受信時に`fetchFinalResult()`呼び出し（line 348）
  - [x] stdout取得後にSSE接続クリーンアップ（line 350）
- [x] メモリリーク防止
  - [x] Job完了時に確実にSSE接続を解放

#### R-6.3 InputBar.swift: デバッグログ追加
- [x] canSendデバッグログ追加（line 17）
- [x] isLoading変更検知ログ追加（line 43）
- [x] 入力状態のトラッキング強化

#### R-6.4 動作確認
- [x] 推論中画面フリーズ解消確認
- [x] 推論中テキスト入力可能確認
- [x] Claude/Codex応答正常表示確認
- [x] メモリ警告・クラッシュなし確認

---

### Refactor-7: バックエンドCodex 0.63.0互換性対応（追加実装: 2025-01-22）

#### R-7.1 cli_builder.py: reasoning_effort mapping追加
- [x] Codex 0.63.0互換性対応
  - [x] `extra-high` → `xhigh` 自動マッピング（line 40-42）
  - [x] サポート値: none, minimal, low, medium, high, xhigh
- [x] RoomSettingsView.swift修正
  - [x] gpt-5.1-codex-maxのみextra-highオプション表示（line 15-22）

#### R-7.2 job_manager.py: SSEログ強化
- [x] SSEブロードキャストログ追加
  - [x] INFO-levelで全SSEイベント記録（line 183）
  - [x] デバッグ用詳細ログ実装

#### R-7.3 session_manager.py: approval_policy尊重
- [x] hardcoded --full-auto削除
  - [x] settings.jsonのapproval_policyを使用
  - [x] ユーザー設定を優先

---

**更新日**: 2025-01-22
**作成者**: Claude Code
**ステータス**: Refactor-7完了（SSE修正・Codex互換性対応完了）、Refactor-4残タスクあり
