"""Database configuration for the Remote Job Server."""
from __future__ import annotations

from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

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
