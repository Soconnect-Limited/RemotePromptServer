"""
Migration: v4.1 Fix Room Foreign Key Constraints (完全版)
Purpose: jobs.room_id と device_sessions.room_id に ON DELETE CASCADE を追加

v4.1仕様完全準拠のため:
- jobs.room_id に FOREIGN KEY (rooms.id, ON DELETE CASCADE) 追加
- device_sessions.room_id に FOREIGN KEY (rooms.id, ON DELETE CASCADE) 追加
- jobs テーブルの全インデックス再作成 (7個)
- device_sessions テーブルの全インデックス・制約再作成

実行方法:
    python migrations/v4_1_fix_room_foreign_keys.py --auto-approve

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
    """jobs.room_id と device_sessions.room_id に FOREIGN KEY + ON DELETE CASCADE を追加"""
    print("=== v4.1 Fix Room Foreign Key Migration (完全版) ===")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        # 1. 現在のスキーマを確認
        print("\n1. 現在のテーブルスキーマ:")
        print("\n[jobs]")
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='jobs';")
        jobs_schema = cursor.fetchone()[0]
        print(jobs_schema)

        print("\n[device_sessions]")
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='device_sessions';")
        ds_schema = cursor.fetchone()[0]
        print(ds_schema)

        # 2. 外部キー制約をチェック
        cursor.execute("PRAGMA foreign_keys;")
        fk_status = cursor.fetchone()[0]
        print(f"\n2. Foreign Keys: {'ON' if fk_status else 'OFF'}")

        # 3. トランザクション開始
        print("\n3. マイグレーション開始...")
        cursor.execute("PRAGMA foreign_keys=OFF;")

        # ===== jobs テーブル処理 =====
        print("\n[Phase 1: jobs テーブル]")

        # 4. 既存データをバックアップ
        cursor.execute("DROP TABLE IF EXISTS jobs_backup;")
        cursor.execute("""
            CREATE TABLE jobs_backup AS
            SELECT * FROM jobs;
        """)
        jobs_backup_count = cursor.execute("SELECT COUNT(*) FROM jobs_backup;").fetchone()[0]
        print(f"   - Jobsバックアップ作成: {jobs_backup_count}件")

        # 5. jobsテーブル削除
        cursor.execute("DROP TABLE jobs;")
        print("   - 既存jobsテーブル削除")

        # 6. 新しいjobsテーブル作成（room_id FK + thread_id FK付き）
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
                FOREIGN KEY(room_id) REFERENCES rooms (id) ON DELETE CASCADE,
                FOREIGN KEY(thread_id) REFERENCES threads (id) ON DELETE SET NULL
            );
        """)
        print("   - 新jobsテーブル作成（room_id FK CASCADE + thread_id FK SET NULL付き）")

        # 7. 全インデックス再作成
        print("   - インデックス再作成中...")
        cursor.execute("CREATE INDEX idx_jobs_thread_id ON jobs (thread_id);")
        cursor.execute("CREATE INDEX idx_jobs_room_thread ON jobs (room_id, thread_id);")
        cursor.execute("CREATE INDEX idx_jobs_status ON jobs (status);")
        cursor.execute("CREATE INDEX idx_jobs_created_at ON jobs (created_at);")
        cursor.execute("CREATE INDEX idx_jobs_device_id ON jobs (device_id);")
        cursor.execute("CREATE INDEX idx_jobs_room_id ON jobs (room_id);")
        cursor.execute("CREATE INDEX idx_jobs_device_room ON jobs (device_id, room_id);")
        print("   - 全インデックス再作成完了 (7個)")

        # 8. データ復元
        cursor.execute("""
            INSERT INTO jobs
            SELECT * FROM jobs_backup;
        """)
        jobs_restored_count = cursor.execute("SELECT COUNT(*) FROM jobs;").fetchone()[0]
        print(f"   - データ復元: {jobs_restored_count}件")

        # 9. バックアップテーブル削除
        cursor.execute("DROP TABLE jobs_backup;")
        print("   - バックアップテーブル削除")

        # ===== device_sessions テーブル処理 =====
        print("\n[Phase 2: device_sessions テーブル]")

        # 10. 既存データをバックアップ
        cursor.execute("DROP TABLE IF EXISTS device_sessions_backup;")
        cursor.execute("""
            CREATE TABLE device_sessions_backup AS
            SELECT * FROM device_sessions;
        """)
        ds_backup_count = cursor.execute("SELECT COUNT(*) FROM device_sessions_backup;").fetchone()[0]
        print(f"   - DeviceSessionsバックアップ作成: {ds_backup_count}件")

        # 11. device_sessionsテーブル削除
        cursor.execute("DROP TABLE device_sessions;")
        print("   - 既存device_sessionsテーブル削除")

        # 12. 新しいdevice_sessionsテーブル作成（room_id FK + thread_id FK付き）
        cursor.execute("""
            CREATE TABLE device_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_id VARCHAR(100) NOT NULL,
                room_id VARCHAR(36) NOT NULL,
                runner VARCHAR(20) NOT NULL,
                thread_id VARCHAR(36),
                session_id VARCHAR(64) NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL,
                FOREIGN KEY(room_id) REFERENCES rooms (id) ON DELETE CASCADE,
                FOREIGN KEY(thread_id) REFERENCES threads (id) ON DELETE CASCADE,
                CONSTRAINT uq_device_room_runner_thread UNIQUE (device_id, room_id, runner, thread_id)
            );
        """)
        print("   - 新device_sessionsテーブル作成（room_id FK CASCADE + thread_id FK CASCADE付き）")

        # 13. インデックス再作成
        print("   - インデックス再作成中...")
        cursor.execute("CREATE INDEX idx_device_room_runner_thread ON device_sessions (device_id, room_id, runner, thread_id);")
        print("   - インデックス再作成完了 (1個)")

        # 14. データ復元
        cursor.execute("""
            INSERT INTO device_sessions
            SELECT * FROM device_sessions_backup;
        """)
        ds_restored_count = cursor.execute("SELECT COUNT(*) FROM device_sessions;").fetchone()[0]
        print(f"   - データ復元: {ds_restored_count}件")

        # 15. バックアップテーブル削除
        cursor.execute("DROP TABLE device_sessions_backup;")
        print("   - バックアップテーブル削除")

        # 16. 外部キー制約を有効化
        cursor.execute("PRAGMA foreign_keys=ON;")

        # 17. 検証
        print("\n4. 新しいテーブルスキーマ:")
        print("\n[jobs]")
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='jobs';")
        new_jobs_schema = cursor.fetchone()[0]
        print(new_jobs_schema)

        print("\n[device_sessions]")
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='device_sessions';")
        new_ds_schema = cursor.fetchone()[0]
        print(new_ds_schema)

        print("\n5. インデックス一覧:")
        print("\n[jobs]")
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='jobs';")
        jobs_indexes = cursor.fetchall()
        for idx in jobs_indexes:
            print(f"   - {idx[0]}")

        print("\n[device_sessions]")
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='device_sessions';")
        ds_indexes = cursor.fetchall()
        for idx in ds_indexes:
            print(f"   - {idx[0]}")

        # 検証条件
        jobs_ok = (
            "FOREIGN KEY(room_id) REFERENCES rooms (id) ON DELETE CASCADE" in new_jobs_schema
            and "FOREIGN KEY(thread_id) REFERENCES threads (id) ON DELETE SET NULL" in new_jobs_schema
        )
        ds_ok = (
            "FOREIGN KEY(room_id) REFERENCES rooms (id) ON DELETE CASCADE" in new_ds_schema
            and "FOREIGN KEY(thread_id) REFERENCES threads (id) ON DELETE CASCADE" in new_ds_schema
        )

        if jobs_ok and ds_ok:
            print("\n✅ マイグレーション成功:")
            print("   [jobs]")
            print("     - room_id FOREIGN KEY (ON DELETE CASCADE) 追加")
            print("     - thread_id FOREIGN KEY (ON DELETE SET NULL) 設定")
            print("     - 全インデックス再作成完了 (7個)")
            print("   [device_sessions]")
            print("     - room_id FOREIGN KEY (ON DELETE CASCADE) 追加")
            print("     - thread_id FOREIGN KEY (ON DELETE CASCADE) 設定")
            print("     - インデックス・制約再作成完了")
        else:
            raise Exception("外部キー制約が正しく設定されていません")

        conn.commit()
        print("\n=== Migration Completed ===")

    except Exception as e:
        print(f"\n❌ マイグレーションエラー: {e}")
        conn.rollback()

        # エラー時はバックアップから復元を試みる
        try:
            print("\nバックアップから復元を試みています...")

            # jobs復元
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='jobs_backup';")
            if cursor.fetchone():
                cursor.execute("DROP TABLE IF EXISTS jobs;")
                cursor.execute("ALTER TABLE jobs_backup RENAME TO jobs;")
                print("✅ Jobsバックアップからの復元に成功")

            # device_sessions復元
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='device_sessions_backup';")
            if cursor.fetchone():
                cursor.execute("DROP TABLE IF EXISTS device_sessions;")
                cursor.execute("ALTER TABLE device_sessions_backup RENAME TO device_sessions;")
                print("✅ DeviceSessionsバックアップからの復元に成功")

            conn.commit()

        except Exception as restore_error:
            print(f"❌ 復元エラー: {restore_error}")

        sys.exit(1)

    finally:
        conn.close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="v4.1 Room Foreign Key Migration")
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
