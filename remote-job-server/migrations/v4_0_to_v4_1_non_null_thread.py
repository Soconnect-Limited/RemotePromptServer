"""
v4.0 -> v4.1 migration: make jobs.thread_id NOT NULL after clients are updated.
Fails fast if any job has NULL thread_id.
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

DEFAULT_DB_PATH = (Path(__file__).resolve().parent.parent / "data" / "jobs.db").as_posix()


def migrate_v4_0_to_v4_1(db_path: str | None = None) -> None:
    db_path = db_path or DEFAULT_DB_PATH
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM jobs WHERE thread_id IS NULL")
    null_count = cursor.fetchone()[0]
    if null_count > 0:
        conn.close()
        raise RuntimeError(f"Cannot migrate: {null_count} jobs have NULL thread_id")

    cursor.execute(
        """
        CREATE TABLE jobs_new (
            id TEXT PRIMARY KEY,
            runner TEXT NOT NULL,
            input_text TEXT NOT NULL,
            device_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            status TEXT NOT NULL,
            exit_code INTEGER,
            stdout TEXT,
            stderr TEXT,
            started_at DATETIME,
            finished_at DATETIME,
            notify_token TEXT,
            created_at DATETIME NOT NULL,
            FOREIGN KEY (room_id) REFERENCES rooms(id),
            FOREIGN KEY (thread_id) REFERENCES threads(id)
        )
        """
    )

    cursor.execute(
        """
        INSERT INTO jobs_new
        (id, runner, input_text, device_id, room_id, thread_id, status, exit_code, stdout, stderr,
         started_at, finished_at, notify_token, created_at)
        SELECT id, runner, input_text, device_id, room_id, thread_id, status, exit_code, stdout, stderr,
               started_at, finished_at, notify_token, created_at
        FROM jobs
        """
    )

    cursor.execute("DROP TABLE jobs")
    cursor.execute("ALTER TABLE jobs_new RENAME TO jobs")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_thread_id ON jobs(thread_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_room_thread ON jobs(room_id, thread_id)")

    conn.commit()
    conn.close()
    print(f"✅ Migration v4.0 -> v4.1 succeeded for {db_path}")


if __name__ == "__main__":
    migrate_v4_0_to_v4_1()
