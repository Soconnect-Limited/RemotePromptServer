"""
v4.0 -> v3.0 rollback: remove thread layer.
This drops thread_id from jobs/device_sessions and removes threads table.
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

DEFAULT_DB_PATH = (Path(__file__).resolve().parent.parent / "data" / "jobs.db").as_posix()


def rollback_v4_to_v3(db_path: str | None = None) -> None:
    db_path = db_path or DEFAULT_DB_PATH
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. jobs without thread_id
    cursor.execute(
        """
        CREATE TABLE jobs_temp AS
        SELECT id, runner, input_text, device_id, room_id, status, exit_code, stdout, stderr,
               started_at, finished_at, notify_token, created_at
        FROM jobs
        """
    )
    cursor.execute("DROP TABLE jobs")
    cursor.execute("ALTER TABLE jobs_temp RENAME TO jobs")

    # 2. device_sessions back to 3D uniqueness (keep one session per device/room/runner)
    cursor.execute(
        """
        CREATE TABLE device_sessions_old (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            runner TEXT NOT NULL,
            session_id TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            UNIQUE(device_id, room_id, runner)
        )
        """
    )
    cursor.execute(
        """
        INSERT INTO device_sessions_old (device_id, room_id, runner, session_id, created_at, updated_at)
        SELECT device_id, room_id, runner, session_id, created_at, updated_at
        FROM device_sessions
        WHERE id IN (
            SELECT MAX(id) FROM device_sessions GROUP BY device_id, room_id, runner
        )
        """
    )
    cursor.execute("DROP TABLE device_sessions")
    cursor.execute("ALTER TABLE device_sessions_old RENAME TO device_sessions")

    # 3. drop threads table
    cursor.execute("DROP TABLE IF EXISTS threads")

    conn.commit()
    conn.close()
    print(f"✅ Rollback v4 -> v3 completed for {db_path}")


if __name__ == "__main__":
    rollback_v4_to_v3()
