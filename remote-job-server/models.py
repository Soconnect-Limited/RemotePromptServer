"""SQLAlchemy model definitions for the Remote Job Server."""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Integer, String, Text, UniqueConstraint, Index

from db import Base


def utcnow() -> datetime:
    """Return current UTC time as timezone-aware datetime."""
    return datetime.now(timezone.utc)


class Room(Base):
    __tablename__ = "rooms"

    id = Column(String(36), primary_key=True)  # UUID
    name = Column(String(100), nullable=False)
    workspace_path = Column(String(500), nullable=False)
    icon = Column(String(50), nullable=False, default="folder")
    device_id = Column(String(100), nullable=False)
    settings = Column(Text, nullable=True)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "workspace_path": self.workspace_path,
            "icon": self.icon,
            "device_id": self.device_id,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


class DeviceSession(Base):
    __tablename__ = "device_sessions"
    __table_args__ = (
        UniqueConstraint("device_id", "room_id", "runner", name="uq_device_room_runner"),
        Index("idx_device_room_runner", "device_id", "room_id", "runner"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    device_id = Column(String(100), nullable=False)
    room_id = Column(String(36), nullable=False)
    runner = Column(String(20), nullable=False)
    session_id = Column(String(64), nullable=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(
        DateTime,
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
    )


class Device(Base):
    __tablename__ = "devices"

    id = Column(Integer, primary_key=True, autoincrement=True)
    device_id = Column(String(100), unique=True, nullable=False)
    device_token = Column(String(255), nullable=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(
        DateTime,
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
    )


class Job(Base):
    __tablename__ = "jobs"

    id = Column(String(36), primary_key=True)
    runner = Column(String(20), nullable=False)
    input_text = Column(Text, nullable=False)
    device_id = Column(String(100), nullable=False)
    room_id = Column(String(36), nullable=False)
    status = Column(String(20), nullable=False)
    exit_code = Column(Integer)
    stdout = Column(Text)
    stderr = Column(Text)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    notify_token = Column(String(255))
    created_at = Column(DateTime, nullable=False, default=utcnow)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "runner": self.runner,
            "input_text": self.input_text,
            "device_id": self.device_id,
            "room_id": self.room_id,
            "status": self.status,
            "exit_code": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "finished_at": self.finished_at.isoformat() if self.finished_at else None,
        }
