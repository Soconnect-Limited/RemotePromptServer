# Phase B Refactor-8: SSEメモリリーク・UI凍結問題の根本修正

**作成日**: 2025-01-22
**ステータス**: 実装中
**優先度**: 🔴 Critical（メモリリーク・UI凍結によるアプリクラッシュ）

---

## 問題の概要

### 発生した症状
- ✅ **Claude/Codex共通**: 推論中または推論完了後にUI凍結（タッチ入力不可）
- ✅ **Claude/Codex共通**: メモリリークによるOSからの強制終了
  ```
  The app "RemotePrompt" has been killed by the operating system
  because it is using too much memory.
  ```

### 根本原因（7つの問題点）

#### 問題1: 重複した`fetchFinalResult()`呼び出し
**場所**: `ChatViewModel.swift:323-328`, `ChatViewModel.swift:385-388`

**詳細**:
- Terminal statusイベント受信時（line 385-388）: `fetchFinalResult()` → SSE切断待ち
- SSE切断イベント受信時（line 323-328）: 0.5秒待機 → `fetchFinalResult()` → `cleanupConnection()`
- **結果**: 1つのJob完了に対して`fetchFinalResult()`が2回実行される

**影響**: メモリリーク、過剰なAPI呼び出し

---

#### 問題2: SSEManagerのメモリリーク（URLSession強参照サイクル）⭐️ CRITICAL
**場所**: `SSEManager.swift:22`

**詳細**:
```swift
session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
```

**問題**:
- `URLSession`が`delegate: self`で強参照
- `SSEManager`自身も`session`を強参照
- **強参照サイクル**が発生し、`deinit`が呼ばれない

**証拠**: `ChatViewModel.deinit` (line 467-471) でSSE切断処理があるが、強参照サイクルのためViewModelがdeinitされていない可能性

---

#### 問題3: Combineの購読解除漏れ
**場所**: `ChatViewModel.swift:302-343`

**問題**:
- `cleanupConnection()`で`sseCancellables.removeValue(forKey:)`と`.forEach { $0.cancel() }`を実行
- しかし、**SSEManagerインスタンス自体は`sseConnections`辞書に残り続ける**（メモリ解放されない）

---

#### 問題4: `isConnected`のタイミング問題
**場所**: `SSEManager.swift:45-47`, `SSEManager.swift:108-113`

**問題**:
- `task?.resume()`直後に`isConnected = true`を設定
- **実際の接続確立前に`isConnected`が`true`になる**
- `dropFirst()`で初期値をスキップするが、resume()直後の`true`もスキップされない

---

#### 問題5: `cleanupConnection()`のguard不足
**場所**: `ChatViewModel.swift:348-357`

**問題**:
- guardで`sseConnections[jobId]`の存在確認のみ
- **`sseCancellables[jobId]`の存在確認がない**
- 片方だけクリーンアップされる可能性

---

#### 問題6: SSE切断タイミングの競合
**場所**: `ChatViewModel.swift:313-331`, `ChatViewModel.swift:359-390`

**シーケンス**:
```
[Server] success event送信
   ↓
[SSEManager] jobStatus = "success" (line 93)
   ↓
[ChatViewModel] updateMessageStatus() 実行 (line 309)
   ↓
   Terminal status検出 → fetchFinalResult() (1回目)
   ↓
[Server] SSE接続切断
   ↓
[SSEManager] isConnected = false
   ↓
[ChatViewModel] SSE切断イベント (line 316)
   ↓
   0.5秒待機 → fetchFinalResult() (2回目) → cleanupConnection()
```

**問題**: 2回の`fetchFinalResult()`呼び出しが0.5秒以内に連続実行される

---

#### 問題7: InputBarの`disabled(isLoading)`の不整合
**場所**: `InputBar.swift:43`

**問題**:
- `ChatViewModel.sendMessage()`でJob作成後に`isLoading = false`を設定
- しかし、**SSE接続中は`isLoading = false`のまま**
- メモリリークが発生すると、UIは有効でも実質的に操作不能になる

---

#### 問題8: Message ID重複によるSwiftUI ForEach警告 ⭐️ NEW
**場所**: `ChatViewModel.swift:122-152` (`convertJobsToMessages`)

**詳細**:
実機ログで以下の警告が大量発生：
```
ForEach<Array<Message>, String, IDView<MessageBubble, String>>:
the ID 2b6687d2-d694-4695-9065-cbc7104017be-assistant occurs multiple times
within the collection, this will give undefined results!
```

**原因推測**:
- `convertJobsToMessages()` で `"\(job.id)-user"` / `"\(job.id)-assistant"` としてMessage IDを生成
- 同じJob IDが複数回変換され、重複IDが発生
- `fetchHistory()` と `recoverIncompleteJobs()` の両方から同じJobが処理される可能性

**影響**:
- SwiftUIの`ForEach`がundefined behaviorを引き起こす
- **UI凍結の直接原因の可能性が高い**
- View更新のパフォーマンス劣化

---

## 修正計画

### Refactor-8.1: SSEManager強参照サイクル解消 ⭐️ CRITICAL

#### R-8.1.1 URLSession invalidate追加
- [ ] `disconnect()`メソッド修正
  - [ ] `session.invalidateAndCancel()`を呼び出し
  - [ ] セッションを明示的に破棄
  - [ ] `task = nil`の後に実行

#### R-8.1.2 deinitでの確実な破棄
- [ ] `SSEManager`に`deinit`追加
  - [ ] `session.invalidateAndCancel()`を呼び出し
  - [ ] デバッグログ追加（`print("SSEManager deinit")`）

#### R-8.1.3 動作確認
- [ ] SSEManager deinitログが出力されることを確認
- [ ] URLSessionがメモリから解放されることを確認

---

### Refactor-8.2: fetchFinalResult重複呼び出し排除

#### R-8.2.1 updateMessageStatus修正
- [ ] Terminal status受信時の`fetchFinalResult()`呼び出しを削除
  - [ ] `ChatViewModel.swift:351-357`を削除
  - [ ] Terminal statusではメッセージステータス更新のみ実行

#### R-8.2.2 SSE切断イベントのみで最終結果取得
- [ ] `ChatViewModel.swift:291-302`を維持
  - [ ] SSE切断後に0.5秒待機
  - [ ] `fetchFinalResult()`呼び出し
  - [ ] `cleanupConnection()`呼び出し

#### R-8.2.3 動作確認
- [ ] `fetchFinalResult()`が1回のみ実行されることをログで確認
- [ ] stdout正常表示確認

---

### Refactor-8.3: cleanupConnection改善

#### R-8.3.1 両辞書の同時クリア
- [ ] `cleanupConnection()`修正
  - [ ] `sseConnections`と`sseCancellables`両方の存在確認
  - [ ] 両方が存在する場合のみクリーンアップ実行
  - [ ] `session.invalidateAndCancel()`呼び出し追加

#### R-8.3.2 デバッグログ強化
- [ ] クリーンアップ前後のメモリ状態ログ追加
- [ ] 辞書のキー数をログ出力

---

### Refactor-8.4: isConnectedタイミング修正

#### R-8.4.1 connect()での即時設定削除
- [ ] `SSEManager.swift:45-47`削除
  - [ ] `isConnected = true`を`connect()`から削除

#### R-8.4.2 初回データ受信時に設定
- [ ] `urlSession(_:dataTask:didReceive:)`修正
  - [ ] 初回データ受信時に`isConnected = true`を設定
  - [ ] フラグ追加（`private var hasReceivedData = false`）

---

### Refactor-8.5: 統合テスト

#### R-8.5.1 メモリリークテスト
- [ ] Xcode Instruments（Leaks）で検証
- [ ] 10回連続メッセージ送信
- [ ] SSEManager deinitログ確認

#### R-8.5.2 UI凍結テスト
- [ ] Claude/Codex各5回メッセージ送信
- [ ] 推論中にタッチ入力可能確認
- [ ] メモリ警告・クラッシュなし確認

#### R-8.5.3 stdout表示テスト
- [ ] 長文応答（1000文字以上）正常表示
- [ ] エラー時のstderr表示確認

---

## 実装チェックリスト

### Phase 1: CRITICAL修正（問題2・問題1）
- [x] R-8.1.1 URLSession再利用問題修正（✅ 完了 - 方針A採用）
  - [x] `session`をオプショナル型に変更
  - [x] `connect()`で毎回新しいURLSessionを生成
  - [x] `disconnect()`で`session = nil`設定
  - **修正内容**: 無効化されたsessionの再利用を完全回避
- [x] R-8.1.2 deinitログ強化（✅ 完了）
- [ ] R-8.1.3 動作確認（実機テストで連続4回以上のメッセージ送信確認待ち）
  - [ ] `DEBUG: SSEManager deinit`ログ確認
  - [ ] 4回目以降のメッセージでSSE正常受信確認
- [ ] R-8.2.1 updateMessageStatus修正
- [ ] R-8.2.2 SSE切断イベントのみで最終結果取得
- [ ] R-8.2.3 動作確認

### Phase 2: 改善修正（問題3・問題5）
- [x] R-8.3.1 両辞書の同時クリア（✅ Combine購読格納バグ修正完了）
  - **修正内容**: `sseCancellables[jobId] = Set<AnyCancellable>()` を先に作成し、`.store(in: &sseCancellables[jobId]!)` で直接格納
  - **検証**: 実機ログで `cleanupConnection() - After cleanup - sseConnections.count: 0, sseCancellables.count: 0` 確認
- [x] R-8.3.2 デバッグログ強化（`cleanupConnection()`で辞書カウント出力追加済み）

### Phase 3: Message ID重複排除（問題8） ⭐️ CRITICAL
- [x] R-8.6.1 fetchHistory()に重複排除ロジック追加（✅ 完了）
  - [x] `loadMoreMessages`時に既存Message IDを`Set`で収集
  - [x] 新規取得した履歴から既存IDを除外
  - [x] デバッグログで重複検出・除外件数を出力
  - **修正内容**: `ChatViewModel.swift:109-125`で重複ID除外ロジック追加
- [x] R-8.6.2 動作確認（✅ 実機テスト完了）
  - [x] ForEach警告が出力されないことを確認（実機ログで警告なし）
  - [x] 履歴ページネーションで重複なく正常表示

### Phase 4: タイミング修正（問題4）
- [ ] R-8.4.1 connect()での即時設定削除
- [ ] R-8.4.2 初回データ受信時に設定

### Phase 5: 統合テスト
- [ ] R-8.5.1 メモリリークテスト（要長時間稼働テスト）
  - [ ] `DEBUG: SSEManager deinit`ログ確認
  - [ ] Xcode Instruments Leaksで検証
- [x] R-8.5.2 UI凍結テスト（✅ 実機テスト完了）
  - [x] Claude/Codex両方で推論中にタッチ入力可能確認
  - [x] 「画面のロックなし」確認
- [x] R-8.5.3 stdout表示テスト（✅ 実機テスト完了）
  - [x] Claude/Codex両方でstdout正常表示
  - [x] エラーなし確認

---

## 成功基準

- ⏳ **メモリリーク解消**: Instruments Leaksで0件（長時間稼働テスト待ち）
- ✅ **UI凍結解消**: 推論中もタッチ入力可能（実機テスト完了）
- ✅ **stdout正常表示**: 全応答が正しく表示される（実機テスト完了）
- ⏳ **安定性**: 連続10回送信でクラッシュなし（要追加テスト）

---

## 完了した修正のまとめ

### Phase 2 & Phase 3: CRITICAL修正完了（2025-01-22）

#### 修正1: Combine購読格納バグ修正
**問題**: `Set<AnyCancellable>`の値型セマンティクスにより、ローカル変数→辞書へのコピー時に購読が失われ、メモリリーク

**修正**: `ChatViewModel.swift:315-344`
```swift
// 辞書に直接Set作成し、購読を直接格納
sseCancellables[jobId] = Set<AnyCancellable>()
manager.$jobStatus
    .receive(on: DispatchQueue.main)
    .sink { ... }
    .store(in: &sseCancellables[jobId]!)
```

**検証**: 実機ログで`cleanupConnection() - After cleanup - sseCancellables.count: 0`確認

---

#### 修正2: Message ID重複排除
**問題**: `fetchHistory(reset: false)`時に既存メッセージと新規履歴を単純結合し、SwiftUI ForEach警告とUI凍結発生

**修正**: `ChatViewModel.swift:109-125`
```swift
if reset {
    combinedMessages = historicalMessages
} else {
    let existingIds = Set(messages.map { $0.id })
    let newMessages = historicalMessages.filter { !existingIds.contains($0.id) }
    combinedMessages = newMessages + messages
}
```

**検証**: 実機ログでForEach ID重複警告なし、UI凍結解消

---

#### デバッグログ追加
**追加箇所**:
- `SSEManager.swift:44-48`: connect()開始ログ
- `SSEManager.swift:70`: didReceive data呼び出し確認
- `SSEManager.swift:108`: didCompleteWithError呼び出し確認

**目的**: URLSessionデリゲートメソッド呼び出し状況の可視化

---

**更新日**: 2025-01-23
**完了日**: 2025-01-22 (Phase 2 & 3)
**次ステップ**: Phase 1残タスク（fetchFinalResult重複呼び出し排除）、メモリリーク長時間稼働テスト

---

## 🔴 CRITICAL: メモリ3GB+クラッシュの根本原因特定（2025-01-23）

### 調査対象ログ
**ファイル**: `Logs/202511230026Xcode_log.md`
**症状**: 10回のメッセージ送信後、メモリ3GB+到達でiOSがアプリを強制終了

### 問題9: InputBar.canSendでのデバッグログ過剰出力 ⭐️ CRITICAL

**場所**: `InputBar.swift:14-19`

**問題コード**:
```swift
private var canSend: Bool {
    let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let result = hasText && !isLoading
    print("DEBUG: InputBar canSend - hasText: \(hasText), isLoading: \(isLoading), result: \(result)")  // ← 問題
    return result
}
```

**根本原因**:
1. **Computed propertyでのprint()**: SwiftUIの`body`再評価のたびに実行される
2. **複数箇所参照**: `canSend`は`body`内で3箇所（line 56, 65, 68）で参照
3. **1回の再描画で6回評価**: foregroundStyle、disabled、if条件で複数回読み取られる
4. **キーボード入力での連鎖**: 1文字入力ごとに`@Binding var text`変更 → `body`再描画 → `canSend`評価×6

**実証データ（ログ分析結果）**:
```bash
総ログ行数: 3297行
InputBar canSend呼び出し: 1192回（36%）
キーボード入力（text changed）: 約200回
1文字あたりのcanSend評価: 1192 ÷ 200 ≈ 6回

navigationDestination警告: 41回（View階層問題）
Swift Concurrency警告: 1回（unsafeForcedSync）
```

**メモリクラッシュのメカニズム**:
```
キーボード入力（200文字）
  ↓
View再描画（200回+）
  ↓
canSend評価（1192回 = 6回/再描画）
  ↓
print()呼び出し（1192回）
  ↓
文字列フォーマット・メモリ確保（~179KB）
  ↓
trimmingCharacters（1192回の一時String生成）
  ↓
GC負荷増大 + main threadブロック（~357ms）
  ↓
他View再描画（SSE更新、メッセージ追加）との競合
  ↓
メモリ累積（3GB+）
  ↓
iOS: "Too much memory" → プロセス強制終了
```

**10番目のJobでクラッシュした理由**:
- 9回のJobで既にメモリ2.8GB前後まで蓄積
- 10番目のJob開始時のキーボード入力でView再描画オーバーヘッド
- `urlSession(didCompleteWithError:)`実行後、`isConnected`の`@Published`更新がmain threadにdispatchされる前に**メモリ限界突破**
- ログが`DEBUG: urlSession(didCompleteWithError:)`で終了（次の"SSE disconnected"ログなし）

**影響範囲**:
- ❌ メモリ圧迫: 1192回 × 150バイト ≈ 179KB（ログメモリ） + GCオーバーヘッド
- ❌ パフォーマンス: 1192回 × 0.3ms ≈ 357ms のmain threadブロック
- ❌ UI応答性: SwiftUI再描画サイクル遅延 → 体感的なUI凍結

**SSEは正常動作していた証拠**:
- ✅ 10回のJob実行、10回の`urlSession(didReceive:)`成功
- ✅ 9回のSSEManager deinit確認（メモリリーク解消済み）
- ✅ 各Job応答サイズ: 90 bytes（小さい）
- ✅ 履歴読み込み: 5回のみ（正常）

---

### Refactor-8.7: デバッグログ過剰出力の削減 ⭐️ CRITICAL

#### R-8.7.1 InputBar.canSendのデバッグログ削除
- [ ] `InputBar.swift:17`のprint()を削除
  - [ ] Computed propertyから副作用（print）を除去
  - [ ] Release buildではデバッグログを完全無効化

#### R-8.7.2 その他のデバッグログ最適化
- [ ] `InputBar.swift:46-53`のonChangeデバッグログを条件付きコンパイル化
  ```swift
  #if DEBUG
  .onChange(of: text) { print("DEBUG: ...") }
  #endif
  ```
- [ ] ChatViewModel、SSEManagerの重要ログのみ残し、冗長ログを削除

#### R-8.7.3 navigationDestination警告の修正
- [ ] View階層の重複navigationDestinationを特定
- [ ] 最上位Viewに1つのみ配置

#### R-8.7.4 動作確認
- [ ] Xcode Instrumentsでメモリプロファイリング
- [ ] 10回連続メッセージ送信でメモリ使用量を測定
- [ ] 目標: 500MB以下（現状3GB+から85%削減）

---

## 修正優先順位（更新）

### Phase 0: CRITICAL緊急修正（問題9）🔥 NEW
- [x] R-8.7.1 InputBar.canSendログ削除（即座実施）⭐️ 最優先 ✅ 完了
  - [x] `InputBar.swift:14-19`のprint()を削除
  - [x] Computed propertyから副作用（print）を除去
- [x] R-8.7.2 条件付きコンパイルでログ最適化 ✅ 完了
  - [x] `InputBar.swift:43-53`のonChangeデバッグログを`#if DEBUG`で囲む
- [ ] R-8.7.5 @Published更新の最適化（View再描画連鎖の抑制）NEW
- [ ] R-8.7.4 メモリプロファイリングテスト

---

### 追加調査結果（2025-01-23 ユーザー観察反映）

**ユーザー報告**:
> 最後の送信直後にメモリ使用率が鰻登りに上がっていってたよ。それまでは使用率は上がっていってはいたものの、最終送信前は200Mくらいだった。

**新しい仮説: View再描画の連鎖反応**

10番目のJob送信直後のメモリ急増（200MB → 3GB+）は以下のメカニズム:

```
10番目Job送信 ("Y")
  ↓
SSE success受信 → jobStatus = "success"
  ↓
urlSession(didCompleteWithError:) → isConnected = false (@Published更新)
  ↓
ChatView全体再描画（20+メッセージ）
  ↓
各MessageBubble + InputBar再描画
  ↓
canSend computed property評価（20メッセージ × 6回/メッセージ = 120回）
  ↓
print() + trimmingCharacters（120回の副作用）
  ↓
SwiftUI差分検出 → さらなる再描画トリガー
  ↓
再描画連鎖ループ → GC追いつかず
  ↓
メモリ3GB+ → iOSが強制終了
```

**証拠**:
- ログ3296行目までは正常（"Terminal status received"まで出力）
- ログ3297行目で終了（次の"SSE disconnected"なし）
- `isConnected = false`のdispatch直後にクラッシュ

---

#### R-8.7.5 @Published更新の最適化
- [ ] SSEManager.swiftの`@Published`更新をバッチ化
  - [ ] `isConnected`と`jobStatus`の同時更新を1つのDispatchQueue.main.asyncに集約
  - [ ] 不要な中間状態の`@Published`更新を削減
- [ ] ChatViewModelの`messages`更新をバッチ化
  - [ ] 複数メッセージの更新を1回の配列置換に集約
