# Database Migrations

このディレクトリにはv4.1仕様準拠のためのマイグレーションスクリプトが格納されています。

## v4.1 対応状況

### ✅ 適用済みマイグレーション

1. **v4_1_fix_room_foreign_keys.py** (最新・推奨)
   - jobs.room_id に `FOREIGN KEY (rooms.id) ON DELETE CASCADE` 追加
   - jobs.thread_id に `FOREIGN KEY (threads.id) ON DELETE SET NULL` 設定
   - device_sessions.room_id に `FOREIGN KEY (rooms.id) ON DELETE CASCADE` 追加
   - device_sessions.thread_id を nullable=True に変更（互換モード対応）
   - 全インデックス再作成（jobs: 7個、device_sessions: 1個）

### 🚫 非推奨マイグレーション

- **DEPRECATED_v4_0_to_v4_1_non_null_thread.py.bak**
  - v4.1の互換モード（thread_id=NULL許容）と矛盾するため無効化
  - 実行しないでください

## マイグレーション手順

### 新規DB作成時
models.py の定義に従って自動生成されるため、マイグレーション不要です。

### 既存DB更新時

```bash
cd remote-job-server
source .venv/bin/activate

# v4.1 完全対応マイグレーション実行
python migrations/v4_1_fix_room_foreign_keys.py --auto-approve
```

## 確認方法

```bash
sqlite3 data/jobs.db

# jobs テーブルのスキーマ確認
.schema jobs

# device_sessions テーブルのスキーマ確認
.schema device_sessions

# インデックス一覧確認
.indexes jobs
.indexes device_sessions
```

## トラブルシューティング

### マイグレーションエラー時
各スクリプトは自動的にバックアップを作成し、エラー時に復元を試みます。

### 手動ロールバック
```bash
# バックアップから復元（マイグレーション前のバックアップが必要）
cp data/jobs.db.backup data/jobs.db
```

## v4.1 仕様ポイント

### データ整合性保証
- **Room削除時**: Jobs と DeviceSessions を CASCADE 削除
- **Thread削除時**: Jobs.thread_id を NULL に設定（Jobs は保持）

### 互換モード対応
- device_sessions.thread_id が NULL 許容
- v3.x クライアントが thread_id なしでセッション管理可能

### パフォーマンス最適化
- 7つのインデックスによる高速クエリ実行
- status, created_at, device_id, room_id での効率的フィルタリング
