from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import pytest
from fastapi import HTTPException

sys.path.append(str(Path(__file__).resolve().parents[1]))

from auth_helpers import verify_room_ownership  # noqa: E402
from database import Base, engine, init_db, SessionLocal  # noqa: E402
from models import Room, utcnow  # noqa: E402


@pytest.fixture(autouse=True)
def reset_db():
    Base.metadata.drop_all(bind=engine)
    init_db()
    yield
    Base.metadata.drop_all(bind=engine)


def run_async(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def test_verify_room_ownership_success():
    db = SessionLocal()
    try:
        room = Room(
            id="room-1",
            name="Test",
            workspace_path="/tmp",
            icon="folder",
            device_id="dev-1",
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.add(room)
        db.commit()
        verified = run_async(verify_room_ownership("room-1", "dev-1", db))
        assert verified.id == "room-1"
    finally:
        db.close()


def test_verify_room_ownership_not_found():
    db = SessionLocal()
    try:
        with pytest.raises(HTTPException) as exc:
            run_async(verify_room_ownership("missing", "dev-1", db))
        assert exc.value.status_code == 404
    finally:
        db.close()


def test_verify_room_ownership_forbidden():
    db = SessionLocal()
    try:
        room = Room(
            id="room-2",
            name="Test2",
            workspace_path="/tmp",
            icon="folder",
            device_id="owner",
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.add(room)
        db.commit()
        with pytest.raises(HTTPException) as exc:
            run_async(verify_room_ownership("room-2", "other", db))
        assert exc.value.status_code == 403
    finally:
        db.close()
