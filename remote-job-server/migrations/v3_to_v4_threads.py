"""
v3.0 -> v4.0 migration: introduce threads and 4D session management.
Idempotent where reasonable so it can be run safely in CI/staging.
"""
from __future__ import annotations

import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Tuple

DEFAULT_DB_PATH = (Path(__file__).resolve().parent.parent / "data" / "jobs.db").as_posix()


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _column_exists(cursor: sqlite3.Cursor, table: str, column: str) -> bool:
    cursor.execute(f"PRAGMA table_info({table})")
    return any(row[1] == column for row in cursor.fetchall())


def migrate_v3_to_v4(db_path: str | None = None) -> None:
    db_path = db_path or DEFAULT_DB_PATH
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. threads table
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS threads (
            id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT '無題',
            runner TEXT NOT NULL,
            device_id TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
        )
        """
    )
    cursor.execute(
        """CREATE INDEX IF NOT EXISTS idx_threads_room_runner ON threads(room_id, runner)"""
    )
    cursor.execute(
        """CREATE INDEX IF NOT EXISTS idx_threads_updated_at ON threads(updated_at DESC)"""
    )

    # 2. default threads per (room, runner)
    cursor.execute(
        """
        SELECT DISTINCT r.id, r.device_id, 'claude' as runner FROM rooms r
        UNION
        SELECT DISTINCT r.id, r.device_id, 'codex' as runner FROM rooms r
        """
    )
    default_threads: Dict[Tuple[str, str], str] = {}
    for room_id, device_id, runner in cursor.fetchall():
        cursor.execute(
            "SELECT id FROM threads WHERE room_id = ? AND runner = ? ORDER BY created_at ASC LIMIT 1",
            (room_id, runner),
        )
        existing = cursor.fetchone()
        if existing:
            default_threads[(room_id, runner)] = existing[0]
            continue
        thread_id = str(uuid.uuid4())
        cursor.execute(
            """
            INSERT INTO threads (id, room_id, name, runner, device_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                thread_id,
                room_id,
                f"{runner.title()} 会話",
                runner,
                device_id,
                utcnow_iso(),
                utcnow_iso(),
            ),
        )
        default_threads[(room_id, runner)] = thread_id

    # 3. jobs.thread_id column
    if not _column_exists(cursor, "jobs", "thread_id"):
        cursor.execute("ALTER TABLE jobs ADD COLUMN thread_id TEXT")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_thread_id ON jobs(thread_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_jobs_room_thread ON jobs(room_id, thread_id)")

    # 4. backfill jobs.thread_id
    cursor.execute("SELECT id, room_id, runner FROM jobs WHERE room_id IS NOT NULL")
    for job_id, room_id, runner in cursor.fetchall():
        thread_id = default_threads.get((room_id, runner))
        if thread_id:
            cursor.execute("UPDATE jobs SET thread_id = ? WHERE id = ?", (thread_id, job_id))

    # 5. device_sessions new schema
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS device_sessions_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            runner TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            UNIQUE(device_id, room_id, runner, thread_id),
            FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
        )
        """
    )
    cursor.execute(
        """CREATE INDEX IF NOT EXISTS idx_device_sessions_lookup ON device_sessions_new(device_id, room_id, runner, thread_id)"""
    )

    if _column_exists(cursor, "device_sessions", "thread_id"):
        # already migrated; skip copy
        pass
    else:
        cursor.execute(
            "SELECT device_id, room_id, runner, session_id, created_at, updated_at FROM device_sessions"
        )
        for device_id, room_id, runner, session_id, created_at, updated_at in cursor.fetchall():
            thread_id = default_threads.get((room_id, runner))
            if not thread_id:
                continue
            cursor.execute(
                """
                INSERT OR IGNORE INTO device_sessions_new
                (device_id, room_id, runner, thread_id, session_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (device_id, room_id, runner, thread_id, session_id, created_at, updated_at),
            )
        cursor.execute("DROP TABLE device_sessions")
        cursor.execute("ALTER TABLE device_sessions_new RENAME TO device_sessions")

    conn.commit()
    conn.close()
    print(f"✅ Migration v3 -> v4 succeeded for {db_path}")


if __name__ == "__main__":
    migrate_v3_to_v4()
