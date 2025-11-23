# Job Cancel Feature Implementation Plan

## 概要
ユーザーがJobを手動でキャンセルできる機能を追加し、タイムアウトを延長する。

## 現状の問題

### タイムアウト設定
- `session_manager.py:116, 219`: `timeout=300` (5分)
- Codexの長時間処理がタイムアウトエラーになる

### キャンセル機能
- ❌ キャンセルAPIエンドポイントなし
- ❌ プロセス管理機構なし (`subprocess.run()`で同期実行)
- ❌ クライアント側のキャンセルUIなし

## 実装方針

### 方針A: 非同期プロセス管理 (推奨)

#### サーバー側
1. `subprocess.Popen()` でプロセスを非同期起動
2. プロセスIDを辞書で管理 (`running_processes: Dict[job_id, Popen]`)
3. バックグラウンドスレッドでstdout/stderrを読み取り、DBに保存
4. 新規エンドポイント: `DELETE /jobs/{job_id}` でプロセスをKILL

#### クライアント側 (iOS)
1. MessageBubbleに「キャンセル」ボタン追加 (status=running時のみ表示)
2. DELETE APIを呼び出し
3. SSE経由で`status: cancelled`イベントを受信

### 方針B: タイムアウト延長のみ (簡易版)

#### 変更点
- `session_manager.py:116, 219`: `timeout=300` → `timeout=1800` (30分)

**メリット**: 最小限の変更
**デメリット**: キャンセル機能なし

---

## Phase 1: タイムアウト延長 (即時対応)

### 修正ファイル
- [x] `session_manager.py`

### 変更内容
```python
# Line 116, 219
timeout=300  # 5分
↓
timeout=1800  # 30分
```

---

## Phase 2: Job Cancel機能実装 (フル実装)

### サーバー側実装

#### 2.1 プロセス管理の追加

**ファイル**: `job_manager.py`

**追加内容**:
```python
from threading import Thread
import subprocess

class JobManager:
    def __init__(self):
        self.running_processes: Dict[str, subprocess.Popen] = {}
        # 既存コード...

    def _execute_job(self, job_id: str, workspace_path: str, settings: Optional[dict]) -> None:
        # subprocess.runをPopenに置き換え
        process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=work_dir,
        )

        self.running_processes[job_id] = process

        # 非同期でstdout/stderrを読み取る
        def monitor_process():
            stdout, stderr = process.communicate(input=prompt, timeout=1800)
            # DB更新...
            self.running_processes.pop(job_id, None)

        Thread(target=monitor_process, daemon=True).start()

    def cancel_job(self, job_id: str) -> bool:
        process = self.running_processes.get(job_id)
        if not process:
            return False

        process.terminate()  # SIGTERM
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()  # SIGKILL

        # DB更新
        db = SessionLocal()
        try:
            job = db.query(Job).filter_by(id=job_id).first()
            if job:
                job.status = "cancelled"
                job.exit_code = -1
                job.finished_at = utcnow()
                db.commit()

                self._broadcast_job_event(
                    job_id,
                    {
                        "status": "cancelled",
                        "finished_at": job.finished_at.isoformat(),
                        "exit_code": -1,
                    },
                    close_stream=True,
                )
        finally:
            db.close()

        self.running_processes.pop(job_id, None)
        return True
```

#### 2.2 DELETE APIエンドポイント追加

**ファイル**: `main.py`

**追加内容**:
```python
@app.delete("/jobs/{job_id}")
async def cancel_job(
    job_id: str,
    api_key: str = Depends(verify_api_key),
):
    """Cancel a running job."""
    success = JOB_MANAGER.cancel_job(job_id)
    if not success:
        raise HTTPException(status_code=404, detail="Job not found or not running")
    return {"status": "cancelled", "job_id": job_id}
```

#### 2.3 models.py更新

**追加ステータス**:
```python
# Line 42-45 (status enumに追加)
status: str  # 'queued', 'running', 'success', 'failed', 'cancelled'
```

---

### クライアント側実装 (iOS)

#### 2.4 APIClient拡張

**ファイル**: `APIClient.swift`

**追加メソッド**:
```swift
func cancelJob(jobId: String) async throws {
    let endpoint = "\(baseURL)/jobs/\(jobId)"
    var request = URLRequest(url: URL(string: endpoint)!)
    request.httpMethod = "DELETE"
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")

    let (_, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw APIError.invalidResponse
    }
}
```

#### 2.5 ChatViewModel拡張

**ファイル**: `ChatViewModel.swift`

**追加メソッド**:
```swift
func cancelJob(_ jobId: String) {
    Task {
        do {
            try await apiClient.cancelJob(jobId: jobId)
            #if DEBUG
            print("DEBUG: Job \(jobId) cancelled")
            #endif
        } catch {
            print("ERROR: Failed to cancel job \(jobId): \(error)")
        }
    }
}
```

#### 2.6 MessageBubble UI更新

**ファイル**: `MessageBubble.swift`

**追加UI**:
```swift
if message.type == .assistant && message.status == .running {
    Button(action: {
        viewModel.cancelJob(message.jobId)
    }) {
        HStack {
            Image(systemName: "xmark.circle.fill")
            Text("キャンセル")
        }
        .foregroundColor(.red)
    }
    .padding(.top, 8)
}
```

---

## 実装チェックリスト

### Phase 1: タイムアウト延長 ⚡️ 即時対応
- [x] R-1.1 session_manager.pyのtimeout値を300→1800に変更
  - [x] Line 116 (Claude)
  - [x] Line 219 (Codex)
- [x] R-1.2 サーバー再起動（PID 91005でポート8443起動中）
- [ ] R-1.3 動作確認
  - [ ] 10分超のCodex処理が完了することを確認

### Phase 2: Cancel機能実装
#### サーバー側
- [ ] R-2.1 job_manager.pyプロセス管理追加
  - [ ] `running_processes`辞書追加
  - [ ] `subprocess.run` → `subprocess.Popen`変更
  - [ ] スレッドでstdout/stderr監視
  - [ ] `cancel_job()`メソッド追加
- [ ] R-2.2 main.py DELETE APIエンドポイント追加
- [ ] R-2.3 models.py status enumに'cancelled'追加

#### クライアント側
- [ ] R-2.4 APIClient.swiftにcancelJob()追加
- [ ] R-2.5 ChatViewModel.swiftにcancelJob()追加
- [ ] R-2.6 MessageBubble.swiftにキャンセルボタン追加
  - [ ] status==running時のみ表示
  - [ ] 赤色の"xmark.circle.fill"アイコン

### 統合テスト
- [ ] R-2.7 キャンセル機能テスト
  - [ ] 長時間Job開始 → キャンセル → status='cancelled'確認
  - [ ] SSE切断確認
  - [ ] プロセス終了確認
- [ ] R-2.8 タイムアウトテスト
  - [ ] 30分超処理でタイムアウト発生確認

---

## 成功基準

- ✅ 30分までの処理がタイムアウトなしで完了
- ✅ ユーザーがUIからJobをキャンセル可能
- ✅ キャンセル後、プロセスが確実に終了
- ✅ SSE経由でcancelledステータスがクライアントに通知される

---

**作成日**: 2025-01-23
**優先度**: Phase 1 (HIGH), Phase 2 (MEDIUM)
