# Phase B Refactor-9: 二重fetchFinalResult修正とハング解消

## 📋 問題概要

### 現象
- チャット送信を繰り返すと徐々にハングする
- 6往復で約47MB増加（8MB/往復）
- 最初は動作するが徐々に重くなる

### 根本原因

#### 1. 二重fetchFinalResultの問題
```swift
// ChatViewModel.swift

// 1回目: $jobStatus購読でsuccess受信時（line 336-349）
if status == "success" || status == "failed" {
    guard !self.finalResultFetched.contains(jobId) else { return }
    self.finalResultFetched.insert(jobId)
    Task { @MainActor in
        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
        self.cleanupConnection(for: jobId)  // ← disconnect()呼び出し
        self.finalResultFetched.remove(jobId)
    }
}

// 2回目: $isConnected購読でfalse受信時（line 359-374）
// disconnect()によってisConnected=falseになり、再度トリガー
if !connected {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒待機
        guard !self.finalResultFetched.contains(jobId) else { return }  // ← タイミング問題
        self.finalResultFetched.insert(jobId)
        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
        self.cleanupConnection(for: jobId)
        self.finalResultFetched.remove(jobId)
    }
}
```

**タイミング問題：**
```
Time 0ms:    success受信 → finalResultFetched.insert(jobId) → Task開始
Time 1ms:    cleanupConnection() → disconnect() → isConnected=false
Time 2ms:    $isConnected購読が発火 → 別のTask開始
Time 500ms:  0.5秒sleep完了 → finalResultFetched確認
Time 501ms:  1回目のTaskがfinalResultFetched.remove(jobId)実行 ← ★ここで解除
Time 502ms:  2回目のTaskがチェック → 通過 → 二重fetch発生
```

#### 2. メインスレッドブロッキング
- SSEManager: `delegateQueue: .main`（line 54）
- 全ての`@Published`更新が`DispatchQueue.main.async`
- メインスレッドのRunLoopが詰まる

#### 3. メモリリーク
- SSEManager: connect()ごとに新規URLSession生成（line 54）
- disconnect()でinvalidateするが、参照が残る可能性

---

## 🎯 修正方針

### Phase 1: 二重fetch防止の根本修正
- `finalResultFetched`のタイミング問題を解決
- `$isConnected`購読の不要なfetch呼び出しを削除

### Phase 2: メインスレッドブロッキング解消
- SSEManagerのdelegateQueueをバックグラウンドに変更
- `DispatchQueue.main.async`の適切な配置

### Phase 3: メモリ最適化
- URLSessionの再利用（毎回生成しない）
- SSEManagerインスタンスの適切な解放確認

---

## 📝 実装計画

### Phase 1: 二重fetch防止（最優先）

#### ☐ Step 1.1: `$jobStatus`購読の修正
**ファイル:** `ChatViewModel.swift` (line 328-351)

**現状の問題:**
```swift
if status == "success" || status == "failed" {
    guard !self.finalResultFetched.contains(jobId) else {
        print("DEBUG: Terminal status already fetched for job: \(jobId)")
        return
    }
    self.finalResultFetched.insert(jobId)
    Task { @MainActor in
        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
        self.cleanupConnection(for: jobId)
        self.finalResultFetched.remove(jobId)  // ← removeのタイミングが早すぎる
    }
}
```

**修正案:**
```swift
if status == "success" || status == "failed" {
    guard !self.finalResultFetched.contains(jobId) else {
        print("DEBUG: Terminal status already fetched for job: \(jobId)")
        return
    }
    self.finalResultFetched.insert(jobId)
    Task { @MainActor in
        defer {
            // 例外やエラーでも確実にフラグをクリア
            self.finalResultFetched.remove(jobId)
            print("DEBUG: finalResultFetched cleared in defer for job: \(jobId)")
        }
        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
        self.cleanupConnection(for: jobId)
    }
}
```

**期待効果:**
- 一度fetchしたJobは二度とfetchされない
- `defer`により例外発生時も確実にフラグクリア
- `cleanupConnection()`後にフラグ解放（レースコンディション対策）

**リスク対策:**
- ⚠️ `fetchFinalResult`が途中でthrowした場合、`cleanupConnection()`が呼ばれずフラグが残る
- ✅ `defer`により必ずフラグクリアされる
- ✅ cleanupConnection呼び出し後にフラグ解放（二重実行の猶予期間確保）

---

#### ☐ Step 1.2: `$isConnected`購読の簡素化
**ファイル:** `ChatViewModel.swift` (line 353-376)

**現状の問題:**
```swift
if !connected {
    print("DEBUG: SSE disconnected, scheduling final result fetch")
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !self.finalResultFetched.contains(jobId) else {
            print("DEBUG: Final result already fetched for job: \(jobId) on disconnect")
            return
        }
        self.finalResultFetched.insert(jobId)
        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
        self.cleanupConnection(for: jobId)
        self.finalResultFetched.remove(jobId)
    }
}
```

**修正案:**
```swift
if !connected {
    print("DEBUG: SSE disconnected")
    // Terminal statusを受信せずに切断された場合のみfetch
    guard !self.finalResultFetched.contains(jobId) else {
        print("DEBUG: Final result already fetched/scheduled for job: \(jobId)")
        return
    }
    self.finalResultFetched.insert(jobId)
    Task { @MainActor in
        defer {
            // 例外やエラーでも確実にフラグをクリア
            self.finalResultFetched.remove(jobId)
            print("DEBUG: finalResultFetched cleared in defer (disconnect) for job: \(jobId)")
        }
        await self.fetchFinalResult(jobId: jobId, messageId: messageId)
        self.cleanupConnection(for: jobId)
    }
}
```

**期待効果:**
- 0.5秒のsleep削除（不要な遅延除去）
- Terminal status未受信時のみfetch（正常系では実行されない）
- `defer`による確実なフラグクリア（Step 1.1と同様）

---

#### ☐ Step 1.3: `cleanupConnection()`の修正
**ファイル:** `ChatViewModel.swift` (line 390-417)

**現状:**
```swift
private func cleanupConnection(for jobId: String) {
    // ... cleanup処理 ...
    sseConnections.removeValue(forKey: jobId)
    sseCancellables.removeValue(forKey: jobId)?.forEach { $0.cancel() }
    finalResultFetched.remove(jobId)  // ← ここで解放
}
```

**修正案:**
```swift
private func cleanupConnection(for jobId: String) {
    // ... cleanup処理 ...
    sseConnections.removeValue(forKey: jobId)
    sseCancellables.removeValue(forKey: jobId)?.forEach { $0.cancel() }

    // finalResultFetchedはTask内のdeferで管理するため、ここでは削除しない
    // （Step 1.1/1.2のdeferが責務を持つ）
    print("DEBUG: cleanupConnection() - finalResultFetched managed by caller's defer")
}
```

**期待効果:**
- `finalResultFetched`の管理をTask内のdeferに一元化
- cleanupConnection()は純粋なリソース解放のみ担当
- レースコンディションの発生箇所を削減

**設計変更:**
- ❌ 旧: cleanupConnection()でフラグクリア → タイミング問題
- ✅ 新: Task内のdeferでフラグクリア → 確実な管理

---

### Phase 2: メインスレッドブロッキング解消

#### ☐ Step 2.1: SSEManagerのdelegateQueue変更
**ファイル:** `SSEManager.swift` (line 36-80)

**現状の問題:**
```swift
// line 54
session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
```

**修正案:**
```swift
// init()を追加
override init() {
    super.init()
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    config.httpAdditionalHeaders = [
        "Accept": "text/event-stream",
        "Cache-Control": "no-cache",
        "Accept-Encoding": "identity",
    ]
    // バックグラウンドキュー使用
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInitiated
    session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    print("DEBUG: SSEManager.init() - Created URLSession with background delegateQueue")
}

func connect(jobId: String) {
    // URLSession生成を削除（init()で生成済み）
    // 既存のsession再利用
}
```

**期待効果:**
- SSE処理がバックグラウンドで実行
- メインスレッドブロッキング解消
- URLSessionの再利用でメモリ効率向上

**リスク対策:**
- ⚠️ 長時間接続後にURLSessionが無効化される可能性
- ✅ フォールバック戦略を追加:

```swift
func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    print("DEBUG: urlSession(didCompleteWithError:) - error: \(error?.localizedDescription ?? "nil")")

    // セッションが無効化された場合は再生成
    if let error = error as NSError?,
       error.domain == NSURLErrorDomain,
       error.code == NSURLErrorNetworkConnectionLost {
        print("DEBUG: URLSession invalidated, recreating in next connect()")
        session?.invalidateAndCancel()
        session = nil  // 次回connect()で再生成
    }

    DispatchQueue.main.async {
        self.isConnected = false
        if let error = error {
            self.errorMessage = error.localizedDescription
        }
    }
    if error == nil {
        sseState = .success
    } else {
        sseState = .failed
    }
}

func connect(jobId: String) {
    // セッションが無効な場合は再生成
    if session == nil {
        let config = URLSessionConfiguration.default
        // ... config設定 ...
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        print("DEBUG: SSEManager.connect() - Recreated URLSession")
    }
    // ... 既存のconnect処理 ...
}
```

---

#### ☐ Step 2.2: @Published更新の最適化
**ファイル:** `SSEManager.swift` (line 72-75, 94-97, 152-154, 171-176)

**全ての`@Published`更新を`DispatchQueue.main.async`でラップ（既に適用済み）:**
```swift
// connect() - line 72-75
DispatchQueue.main.async {
    self.isConnected = true
}

// disconnect() - line 94-97
DispatchQueue.main.async {
    self.isConnected = false
}

// urlSession(didReceive:) - line 152-154
DispatchQueue.main.async {
    self.jobStatus = event.status
}

// urlSession(didCompleteWithError:) - line 171-176
DispatchQueue.main.async {
    self.isConnected = false
    if let error = error {
        self.errorMessage = error.localizedDescription
    }
}
```

**期待効果:**
- バックグラウンドスレッドからのUI更新が安全
- SwiftUIとの連携が正常動作

---

#### ☐ Step 2.3: ChatViewModelのCombine購読最適化
**ファイル:** `ChatViewModel.swift` (line 328-385)

**現状:**
```swift
manager.$jobStatus
    .receive(on: DispatchQueue.main)  // ← 不要（SSEManager側で既にmain dispatch）
    .sink { ... }
```

**修正案:**
```swift
manager.$jobStatus
    // .receive(on:)を削除（SSEManager側で既にmain.async実行）
    .sink { ... }
```

**期待効果:**
- 二重のスレッド切り替え削除
- パフォーマンス向上

---

### Phase 3: メモリ最適化

#### ☐ Step 3.1: URLSession再利用の確認
**ファイル:** `SSEManager.swift`

**修正内容（Phase 2.1で実施）:**
- init()でURLSession生成
- connect()では再利用
- disconnect()でinvalidateしない（deinitで実施）

**変更:**
```swift
func disconnect() {
    task?.cancel()
    task = nil
    buffer.removeAll()

    // sessionは再利用するためinvalidateしない
    print("DEBUG: SSEManager.disconnect() - Task cancelled, session kept for reuse")

    DispatchQueue.main.async {
        self.isConnected = false
    }
    sseState = .disconnected
}

deinit {
    session?.invalidateAndCancel()
    print("DEBUG: SSEManager deinit - URLSession invalidated")
}
```

**期待効果:**
- URLSession生成コスト削減
- メモリ使用量削減

---

#### ☐ Step 3.2: SSEManagerインスタンスの解放確認
**ファイル:** `ChatViewModel.swift`

**確認項目:**
```swift
// cleanupConnection()でSSEManagerを確実に削除
sseConnections.removeValue(forKey: jobId)  // ← Strong参照解除

// deinitログ確認
// SSEManager deinitが呼ばれることを確認
```

**テスト方法:**
```bash
# Xcodeコンソールで確認
# 各Job完了後に以下が出力されるか
DEBUG: SSEManager deinit - URLSession invalidated
```

---

## 🧪 テスト計画

### Test 1: 二重fetch確認
**目的:** fetchFinalResultが1回のみ呼ばれることを確認

**手順:**
1. アプリ起動
2. メッセージ送信
3. Xcodeコンソールで以下を確認:
```
DEBUG: Received job status update: success
DEBUG: Fetching final result for job XXX
DEBUG: Successfully fetched job, status: success
DEBUG: cleanupConnection() called
```
- "Fetching final result"が**1回のみ**出力されること

**成功基準:**
- ✅ 各Jobで"Fetching final result"が1回のみ
- ❌ 2回以上出力される場合は失敗

---

### Test 2: ハング耐性テスト
**目的:** 連続送信でハングしないことを確認

**手順:**
1. アプリ起動
2. 10回連続でメッセージ送信
3. 各送信後、入力フィールドがすぐ操作可能か確認

**成功基準:**
- ✅ 10回全て正常に送受信完了
- ✅ 入力フィールドが常に操作可能
- ❌ ハングやフリーズが発生した場合は失敗

---

### Test 3: メモリリークテスト
**目的:** メモリ使用量が安定していることを確認

**手順:**
1. アプリ起動時のメモリ使用量を記録（A）
2. 20回メッセージ送信
3. 最終メモリ使用量を記録（B）
4. 増加量 = B - A を計算

**成功基準:**
- ✅ 増加量が40MB未満（2MB/往復未満）
- ⚠️ 40-80MB（要調査）
- ❌ 80MB以上（失敗）

**ログ確認:**
```
DEBUG: [MEM] before sendMessage RSS=XXX MB
DEBUG: [MEM] after cleanup RSS=YYY MB
```

---

### Test 4: スレッド動作確認
**目的:** SSE処理がバックグラウンドで実行されることを確認

**手順:**
1. メッセージ送信
2. Xcodeコンソールで以下を確認:
```
DEBUG: [SSE-DATA] received: XXX bytes [thread:bg]  ← bgであること
DEBUG: [SSE-DECODE] SUCCESS - status: running
```

**成功基準:**
- ✅ `[thread:bg]`が表示される
- ❌ `[thread:main]`の場合は失敗

**スレッド判定の実装:**
```swift
// SSEManager.swiftで使用
let thread = OperationQueue.current == OperationQueue.main ? "main" : "bg"

// または、より正確な判定:
let isMainThread = Thread.isMainThread
let thread = isMainThread ? "main" : "bg[\(Thread.current)]"
print("DEBUG: [SSE-DATA] received on thread: \(thread)")
```

**注意:**
- `Thread.isMain`は非推奨（iOS 13.0+）
- `Thread.isMainThread`または`OperationQueue.current == .main`を使用
- OperationQueue経由でもログがmainになるケースは、`Thread.current`でスレッドIDを出力して確認

---

## 📊 期待される改善効果

### Before（現状）
- 6往復で約47MB増加（8MB/往復）
- 連続送信でハング発生
- 二重fetchFinalResult実行

### After（修正後）
- メモリ増加を2MB/往復以下に抑制
- 20回以上連続送信可能
- fetchFinalResultが1回のみ実行
- UI反応速度向上

---

## 🚀 実装順序

1. **Phase 1.1-1.3** → 二重fetch修正（最優先）
2. **Test 1** → 二重fetch確認
3. **Phase 2.1-2.3** → メインスレッドブロッキング解消
4. **Test 2, 4** → ハング耐性・スレッド確認
5. **Phase 3.1-3.2** → メモリ最適化
6. **Test 3** → メモリリーク確認
7. **全体統合テスト** → 20回連続送信

---

## 📌 注意事項

### 重要な変更点
1. `finalResultFetched.remove(jobId)`のタイミング変更
   - Task完了時 → cleanup後1秒遅延
2. URLSession生成タイミング変更
   - connect()ごと → init()で1回のみ
3. delegateQueue変更
   - `.main` → バックグラウンドキュー

### 互換性
- iOS 15.0以降（変更なし）
- 既存のSSE APIプロトコル互換

### リスク
- **低**: `finalResultFetched`の管理方法変更
  - 対策: Task内のdeferで確実にクリア（例外発生時も対応）
- **低**: バックグラウンドスレッド化による未知のバグ
  - 対策: 全ての@Published更新を`main.async`でラップ済み
- **低**: URLSession長時間接続後の無効化
  - 対策: NSURLErrorNetworkConnectionLost検知時に再生成

---

## ✅ 完了条件

- [ ] Phase 1完了: 二重fetch修正
- [ ] Phase 2完了: メインスレッドブロッキング解消
- [ ] Phase 3完了: メモリ最適化
- [ ] Test 1-4全て合格
- [ ] 20回連続送信テスト合格
- [ ] コミット作成
- [ ] Master_Specification.md更新

---

**作成日:** 2025-11-24
**バージョン:** v1.0
**対象コンポーネント:** SSEManager, ChatViewModel
