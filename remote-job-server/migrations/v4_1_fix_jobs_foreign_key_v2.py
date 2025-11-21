"""
Migration: v4.1 Fix Jobs Foreign Key Constraint v2 (完全版)
Purpose: jobs.thread_id のFOREIGN KEY制約を ON DELETE SET NULL に変更
         + room_id FOREIGN KEY追加 + 全インデックス再作成

v4.1仕様に完全準拠するため:
- Thread削除時にJobsをCASCADE削除せず、jobs.thread_id を NULL に設定
- jobs.room_id のFOREIGN KEY制約を追加
- 全インデックスを再作成 (status, created_at, device_id, room_id, device_room)

実行方法:
    python migrations/v4_1_fix_jobs_foreign_key_v2.py

ロールバック:
    データベースのバックアップから復元してください。
"""

import sqlite3
import sys
from pathlib import Path

# プロジェクトルートを sys.path に追加
sys.path.insert(0, str(Path(__file__).parent.parent))

DB_PATH = "data/jobs.db"


def migrate():
    """jobs.thread_id 外部キー制約を ON DELETE SET NULL に変更 + room_id FK追加 + 全インデックス再作成"""
    print("=== v4.1 Fix Jobs Foreign Key Migration v2 (完全版) ===")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        # 1. 現在のスキーマを確認
        print("\n1. 現在のjobsテーブルスキーマ:")
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='jobs';")
        current_schema = cursor.fetchone()[0]
        print(current_schema)

        # 2. 外部キー制約をチェック
        cursor.execute("PRAGMA foreign_keys;")
        fk_status = cursor.fetchone()[0]
        print(f"\n2. Foreign Keys: {'ON' if fk_status else 'OFF'}")

        # 3. トランザクション開始
        print("\n3. マイグレーション開始...")
        cursor.execute("PRAGMA foreign_keys=OFF;")

        # 4. 既存データをバックアップ
        cursor.execute("DROP TABLE IF EXISTS jobs_backup;")
        cursor.execute("""
            CREATE TABLE jobs_backup AS
            SELECT * FROM jobs;
        """)
        backup_count = cursor.execute("SELECT COUNT(*) FROM jobs_backup;").fetchone()[0]
        print(f"   - Jobsバックアップ作成: {backup_count}件")

        # 5. jobsテーブル削除
        cursor.execute("DROP TABLE jobs;")
        print("   - 既存jobsテーブル削除")

        # 6. 新しいjobsテーブル作成（room_id FK + thread_id ON DELETE SET NULL付き）
        cursor.execute("""
            CREATE TABLE jobs (
                id VARCHAR(36) NOT NULL,
                runner VARCHAR(20) NOT NULL,
                input_text TEXT NOT NULL,
                device_id VARCHAR(100) NOT NULL,
                room_id VARCHAR(36) NOT NULL,
                thread_id VARCHAR(36),
                status VARCHAR(20) NOT NULL,
                exit_code INTEGER,
                stdout TEXT,
                stderr TEXT,
                started_at DATETIME,
                finished_at DATETIME,
                notify_token VARCHAR(255),
                created_at DATETIME NOT NULL,
                PRIMARY KEY (id),
                FOREIGN KEY(room_id) REFERENCES rooms (id),
                FOREIGN KEY(thread_id) REFERENCES threads (id) ON DELETE SET NULL
            );
        """)
        print("   - 新jobsテーブル作成（room_id FK + thread_id ON DELETE SET NULL付き）")

        # 7. 全インデックス再作成
        print("   - インデックス再作成中...")
        cursor.execute("CREATE INDEX idx_jobs_thread_id ON jobs (thread_id);")
        cursor.execute("CREATE INDEX idx_jobs_room_thread ON jobs (room_id, thread_id);")
        cursor.execute("CREATE INDEX idx_jobs_status ON jobs (status);")  # 追加
        cursor.execute("CREATE INDEX idx_jobs_created_at ON jobs (created_at);")  # 追加
        cursor.execute("CREATE INDEX idx_jobs_device_id ON jobs (device_id);")  # 追加
        cursor.execute("CREATE INDEX idx_jobs_room_id ON jobs (room_id);")  # 追加
        cursor.execute("CREATE INDEX idx_jobs_device_room ON jobs (device_id, room_id);")  # 追加
        print("   - 全インデックス再作成完了 (7個)")

        # 8. データ復元
        cursor.execute("""
            INSERT INTO jobs
            SELECT * FROM jobs_backup;
        """)
        restored_count = cursor.execute("SELECT COUNT(*) FROM jobs;").fetchone()[0]
        print(f"   - データ復元: {restored_count}件")

        # 9. バックアップテーブル削除
        cursor.execute("DROP TABLE jobs_backup;")
        print("   - バックアップテーブル削除")

        # 10. 外部キー制約を有効化
        cursor.execute("PRAGMA foreign_keys=ON;")

        # 11. 検証
        print("\n4. 新しいjobsテーブルスキーマ:")
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='jobs';")
        new_schema = cursor.fetchone()[0]
        print(new_schema)

        print("\n5. インデックス一覧:")
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='jobs';")
        indexes = cursor.fetchall()
        for idx in indexes:
            print(f"   - {idx[0]}")

        if "ON DELETE SET NULL" in new_schema and "REFERENCES rooms" in new_schema:
            print("\n✅ マイグレーション成功:")
            print("   - room_id FOREIGN KEY 追加")
            print("   - thread_id ON DELETE SET NULL 制約設定")
            print("   - 全インデックス再作成完了")
        else:
            raise Exception("外部キー制約が正しく設定されていません")

        conn.commit()
        print("\n=== Migration Completed ===")

    except Exception as e:
        print(f"\n❌ マイグレーションエラー: {e}")
        conn.rollback()

        # エラー時はバックアップから復元を試みる
        try:
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='jobs_backup';")
            if cursor.fetchone():
                print("\nバックアップから復元を試みています...")
                cursor.execute("DROP TABLE IF EXISTS jobs;")
                cursor.execute("ALTER TABLE jobs_backup RENAME TO jobs;")
                # 元のインデックスを再作成
                cursor.execute("CREATE INDEX idx_jobs_thread_id ON jobs (thread_id);")
                cursor.execute("CREATE INDEX idx_jobs_room_thread ON jobs (room_id, thread_id);")
                conn.commit()
                print("✅ バックアップからの復元に成功しました")
        except Exception as restore_error:
            print(f"❌ 復元エラー: {restore_error}")

        sys.exit(1)

    finally:
        conn.close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="v4.1 Jobs Table Migration")
    parser.add_argument(
        "--auto-approve",
        action="store_true",
        help="Skip confirmation prompt and execute migration immediately",
    )
    args = parser.parse_args()

    print(f"データベースパス: {DB_PATH}\n")

    # 確認プロンプト (--auto-approve が指定されていない場合)
    if not args.auto_approve:
        response = input("マイグレーションを実行しますか？ (yes/no): ")
        if response.lower() != "yes":
            print("マイグレーションをキャンセルしました")
            sys.exit(0)

    migrate()
