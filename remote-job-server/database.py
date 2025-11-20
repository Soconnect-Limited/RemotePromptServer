"""Database configuration for the Remote Job Server."""
from __future__ import annotations

from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy import text

from config import settings
from db import Base

DATABASE_URL = settings.database_url


engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


@contextmanager
def session_scope() -> Generator:
    """Provide a transactional scope for DB operations."""
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def init_db() -> None:
    """Create database tables based on model metadata."""
    # Import inside function to ensure models register with the Base metadata.
    from models import Device, DeviceSession, Job, Room  # pylint: disable=import-outside-toplevel

    Base.metadata.create_all(bind=engine)
    _ensure_room_settings_column()


def _ensure_room_settings_column() -> None:
    """SQLite用: roomsテーブルにsettings列が無ければ追加する。

    Alembicを使わない簡易マイグレーション。既存環境の互換性を保つため、
    起動時にのみ実行する。
    """

    with engine.begin() as conn:
        result = conn.execute(text("PRAGMA table_info(rooms)"))
        columns = [row[1] for row in result.fetchall()]
        if "settings" not in columns:
            conn.execute(text("ALTER TABLE rooms ADD COLUMN settings TEXT"))
