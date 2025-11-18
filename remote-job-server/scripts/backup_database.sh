#!/bin/bash
# SQLite データベースバックアップスクリプト

# 設定
PROJECT_DIR="/Users/macstudio/Projects/RemotePrompt/remote-job-server"
DB_FILE="$PROJECT_DIR/data/jobs.db"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/jobs_${TIMESTAMP}.db"

# バックアップディレクトリ作成
mkdir -p "$BACKUP_DIR"

# データベースが存在する場合のみバックアップ
if [ -f "$DB_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting database backup..."

    # SQLite バックアップコマンド（安全にバックアップ）
    sqlite3 "$DB_FILE" ".backup '$BACKUP_FILE'"

    if [ $? -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Backup successful: $BACKUP_FILE"

        # ファイルサイズ確認
        DB_SIZE=$(du -h "$DB_FILE" | cut -f1)
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo "   Database size: $DB_SIZE"
        echo "   Backup size:   $BACKUP_SIZE"

        # 7日以上古いバックアップを削除
        find "$BACKUP_DIR" -name "jobs_*.db" -mtime +7 -delete
        echo "   Old backups (>7 days) cleaned up"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Backup failed"
        exit 1
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  Database file not found: $DB_FILE"
    exit 1
fi
