"""
Migration: v4.2 Remove Thread.runner Column
Purpose: Thread.runnerカラムを削除し、Thread=純粋な会話コンテナ化

v4.2仕様:
- threads.runner カラム削除
- idx_threads_room_runner インデックス削除
- 同一Thread内でrunnerを自由に切り替え可能に

実行方法:
    python migrations/v4_2_remove_thread_runner.py --auto-approve

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
    """threads.runner カラムを削除"""
    print("=== v4.2 Remove Thread.runner Migration ===")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        # 1. 現在のスキーマを確認
        print("\n1. 現在のthreadsテーブルスキーマ:")
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='threads';")
        threads_schema = cursor.fetchone()
        if threads_schema:
            print(threads_schema[0])
        else:
            raise Exception("threadsテーブルが存在しません")

        # 2. 外部キー制約をチェック
        cursor.execute("PRAGMA foreign_keys;")
        fk_status = cursor.fetchone()[0]
        print(f"\n2. Foreign Keys: {'ON' if fk_status else 'OFF'}")

        # 3. トランザクション開始
        print("\n3. マイグレーション開始...")
        cursor.execute("PRAGMA foreign_keys=OFF;")

        # 4. 既存データをバックアップ
        cursor.execute("DROP TABLE IF EXISTS threads_backup;")
        cursor.execute("""
            CREATE TABLE threads_backup AS
            SELECT * FROM threads;
        """)
        threads_backup_count = cursor.execute("SELECT COUNT(*) FROM threads_backup;").fetchone()[0]
        print(f"   - Threadsバックアップ作成: {threads_backup_count}件")

        # 5. threadsテーブル削除
        cursor.execute("DROP TABLE threads;")
        print("   - 既存threadsテーブル削除")

        # 6. 新しいthreadsテーブル作成（runnerカラムなし）
        cursor.execute("""
            CREATE TABLE threads (
                id VARCHAR(36) NOT NULL,
                room_id VARCHAR(36) NOT NULL,
                name VARCHAR(100) NOT NULL DEFAULT '無題',
                device_id VARCHAR(100) NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL,
                PRIMARY KEY (id),
                FOREIGN KEY(room_id) REFERENCES rooms (id) ON DELETE CASCADE
            );
        """)
        print("   - 新threadsテーブル作成（runnerカラムなし）")

        # 7. インデックス再作成（idx_threads_room_runnerは作成しない）
        print("   - インデックス再作成中...")
        cursor.execute("CREATE INDEX idx_threads_room_id ON threads (room_id);")
        cursor.execute("CREATE INDEX idx_threads_updated_at ON threads (updated_at DESC);")
        print("   - インデックス再作成完了 (2個)")

        # 8. データ復元（runnerカラムを除外）
        cursor.execute("""
            INSERT INTO threads (id, room_id, name, device_id, created_at, updated_at)
            SELECT id, room_id, name, device_id, created_at, updated_at
            FROM threads_backup;
        """)
        threads_restored_count = cursor.execute("SELECT COUNT(*) FROM threads;").fetchone()[0]
        print(f"   - データ復元: {threads_restored_count}件（runnerカラム除外）")

        # 9. バックアップテーブル削除
        cursor.execute("DROP TABLE threads_backup;")
        print("   - バックアップテーブル削除")

        # 10. 外部キー制約を有効化
        cursor.execute("PRAGMA foreign_keys=ON;")

        # 11. 検証
        print("\n4. 新しいthreadsテーブルスキーマ:")
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='threads';")
        new_threads_schema = cursor.fetchone()[0]
        print(new_threads_schema)

        print("\n5. インデックス一覧:")
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='threads';")
        threads_indexes = cursor.fetchall()
        for idx in threads_indexes:
            print(f"   - {idx[0]}")

        # 検証条件
        runner_removed = "runner" not in new_threads_schema.lower()
        cascade_ok = "FOREIGN KEY(room_id) REFERENCES rooms (id) ON DELETE CASCADE" in new_threads_schema

        if runner_removed and cascade_ok:
            print("\n✅ マイグレーション成功:")
            print("   - runner カラム削除完了")
            print("   - room_id FOREIGN KEY (ON DELETE CASCADE) 維持")
            print("   - インデックス再作成完了 (2個)")
            print(f"   - データ件数: {threads_restored_count}件")
        else:
            if not runner_removed:
                raise Exception("runnerカラムが正しく削除されていません")
            if not cascade_ok:
                raise Exception("外部キー制約が正しく設定されていません")

        conn.commit()
        print("\n=== Migration Completed ===")

    except Exception as e:
        print(f"\n❌ マイグレーションエラー: {e}")
        conn.rollback()

        # エラー時はバックアップから復元を試みる
        try:
            print("\nバックアップから復元を試みています...")

            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='threads_backup';")
            if cursor.fetchone():
                cursor.execute("DROP TABLE IF EXISTS threads;")
                cursor.execute("ALTER TABLE threads_backup RENAME TO threads;")
                print("✅ Threadsバックアップからの復元に成功")

            conn.commit()

        except Exception as restore_error:
            print(f"❌ 復元エラー: {restore_error}")

        sys.exit(1)

    finally:
        conn.close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="v4.2 Remove Thread.runner Migration")
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
