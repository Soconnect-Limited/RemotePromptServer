"""
v4.0 → v4.1: jobs.thread_id NOT NULL化

前提条件:
- 全てのjobsにthread_idが割り当てられていること
- THREADS_COMPAT_MODE=trueで互換モード運用中

実行後:
- jobs.thread_id が NOT NULL制約に変更される
- データ整合性が向上
"""
import sqlite3
import sys
from pathlib import Path


def migrate_v4_0_to_v4_1(db_path: str):
    """v4.0 → v4.1マイグレーション: jobs.thread_id NOT NULL化"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        # 1. NULLチェック
        cursor.execute("SELECT COUNT(*) FROM jobs WHERE thread_id IS NULL")
        null_count = cursor.fetchone()[0]
        if null_count > 0:
            raise Exception(
                f"❌ Cannot migrate: {null_count} jobs have NULL thread_id. "
                "Please assign thread_id to all jobs first."
            )
        print(f"✅ Pre-check passed: All {cursor.execute('SELECT COUNT(*) FROM jobs').fetchone()[0]} jobs have thread_id")

        # 2. バックアップテーブル作成
        print("📦 Creating backup table...")
        cursor.execute("DROP TABLE IF EXISTS jobs_backup_v4_0")
        cursor.execute("CREATE TABLE jobs_backup_v4_0 AS SELECT * FROM jobs")
        backup_count = cursor.fetchone()
        print(f"✅ Backup created with all jobs")

        # 3. 新しいjobsテーブル作成（thread_id NOT NULL）
        print("🔧 Creating new jobs table with NOT NULL constraint...")
        cursor.execute("""
            CREATE TABLE jobs_new (
                id VARCHAR(36) NOT NULL,
                runner VARCHAR(50) NOT NULL,
                input_text TEXT NOT NULL,
                device_id VARCHAR(100) NOT NULL,
                room_id VARCHAR(36) NOT NULL,
                thread_id VARCHAR(36) NOT NULL,  -- NOT NULL制約追加
                status VARCHAR(20) NOT NULL,
                exit_code INTEGER,
                stdout TEXT,
                stderr TEXT,
                started_at DATETIME,
                finished_at DATETIME,
                notify_token VARCHAR(200),
                created_at DATETIME NOT NULL,
                PRIMARY KEY (id),
                FOREIGN KEY(room_id) REFERENCES rooms (id),
                FOREIGN KEY(thread_id) REFERENCES threads (id) ON DELETE CASCADE
            )
        """)

        # 4. データ移行
        print("📥 Migrating data to new table...")
        cursor.execute("""
            INSERT INTO jobs_new
            SELECT id, runner, input_text, device_id, room_id, thread_id, status,
                   exit_code, stdout, stderr, started_at, finished_at, notify_token, created_at
            FROM jobs
        """)
        migrated_count = cursor.rowcount
        print(f"✅ Migrated {migrated_count} jobs")

        # 5. インデックス再作成
        print("🔧 Creating indexes...")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_thread_id ON jobs_new(thread_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_room_thread ON jobs_new(room_id, thread_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs_new(created_at)")
        print("✅ Indexes created")

        # 6. テーブル置換
        print("🔄 Replacing tables...")
        cursor.execute("DROP TABLE jobs")
        cursor.execute("ALTER TABLE jobs_new RENAME TO jobs")
        print("✅ Table replaced")

        # 7. 検証
        cursor.execute("PRAGMA table_info(jobs)")
        columns = {row[1]: row for row in cursor.fetchall()}
        thread_id_col = columns.get('thread_id')

        if not thread_id_col:
            raise Exception("❌ Verification failed: thread_id column not found")

        if thread_id_col[3] == 1:  # notnull flag
            print("✅ Verification passed: thread_id is NOT NULL")
        else:
            raise Exception("❌ Verification failed: thread_id is still nullable")

        conn.commit()
        print("\n✅ Migration v4.0 → v4.1 completed successfully!")
        print(f"   - {migrated_count} jobs migrated")
        print(f"   - thread_id is now NOT NULL")
        print(f"   - Backup table: jobs_backup_v4_0")

    except Exception as e:
        conn.rollback()
        print(f"\n❌ Migration failed: {e}")
        print("   Database has been rolled back")
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    db_path = Path(__file__).parent.parent / "data" / "jobs.db"

    if not db_path.exists():
        print(f"❌ Database not found: {db_path}")
        sys.exit(1)

    print("=" * 60)
    print("v4.0 → v4.1 Migration: jobs.thread_id NOT NULL化")
    print("=" * 60)
    print(f"Database: {db_path}")
    print()

    confirmation = input("⚠️  This will modify the database. Continue? (yes/no): ")
    if confirmation.lower() != "yes":
        print("❌ Migration cancelled")
        sys.exit(0)

    migrate_v4_0_to_v4_1(str(db_path))

    print("\n" + "=" * 60)
    print("Next steps:")
    print("1. Update .env: THREADS_COMPAT_MODE=false")
    print("2. Restart server")
    print("3. Verify thread_id is required in API requests")
    print("=" * 60)
