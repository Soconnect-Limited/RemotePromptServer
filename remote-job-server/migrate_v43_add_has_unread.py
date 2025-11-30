#!/usr/bin/env python3
"""
v4.3.1 Migration: Add has_unread and unread_runners columns to threads table

Usage:
    python migrate_v43_add_has_unread.py

This script safely adds the has_unread and unread_runners columns to the threads table.
"""

import sqlite3
import os
import sys

DB_PATH = os.environ.get("DATABASE_PATH", "jobs.db")


def main():
    if not os.path.exists(DB_PATH):
        print(f"Error: Database not found at {DB_PATH}")
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        # Check existing columns
        cursor.execute("PRAGMA table_info(threads)")
        columns = [row[1] for row in cursor.fetchall()]

        # v4.3: Add has_unread column
        if "has_unread" not in columns:
            print("Adding 'has_unread' column to threads table...")
            cursor.execute("""
                ALTER TABLE threads
                ADD COLUMN has_unread BOOLEAN NOT NULL DEFAULT 0
            """)
            conn.commit()
            print("Column 'has_unread' added.")
        else:
            print("Column 'has_unread' already exists. Skipping.")

        # v4.3.1: Add unread_runners column
        if "unread_runners" not in columns:
            print("Adding 'unread_runners' column to threads table...")
            cursor.execute("""
                ALTER TABLE threads
                ADD COLUMN unread_runners TEXT DEFAULT '[]'
            """)
            conn.commit()
            print("Column 'unread_runners' added.")
        else:
            print("Column 'unread_runners' already exists. Skipping.")

        # Verify
        cursor.execute("PRAGMA table_info(threads)")
        columns = [row[1] for row in cursor.fetchall()]
        print(f"Columns in threads table: {columns}")
        print("Migration completed successfully!")

    except Exception as e:
        print(f"Migration failed: {e}")
        conn.rollback()
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
