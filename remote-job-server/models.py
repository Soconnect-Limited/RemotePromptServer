"""SQLAlchemy model definitions for the Remote Job Server."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Index,
    ForeignKey,
)
from sqlalchemy.orm import relationship

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
    sort_order = Column(Integer, nullable=False, default=0)  # 並び順（小さいほど上）
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    # Relationships
    threads = relationship("Thread", back_populates="room", cascade="all, delete-orphan")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "workspace_path": self.workspace_path,
            "icon": self.icon,
            "device_id": self.device_id,
            "sort_order": self.sort_order,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


class Thread(Base):
    __tablename__ = "threads"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(100), nullable=False, default="無題")
    # v4.2: runnerカラム削除 - Thread内で任意のrunnerを使用可能
    device_id = Column(String(100), nullable=False)
    # v4.3: 未読フラグ - 推論完了時にtrue、スレッド表示時にfalse
    has_unread = Column(Boolean, nullable=False, default=False)
    # v4.3.1: runner別未読フラグ（JSON配列: ["claude", "codex"]など）
    unread_runners = Column(Text, nullable=True, default="[]")
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow, index=True)

    # Relationships
    room = relationship("Room", back_populates="threads")
    jobs = relationship("Job", back_populates="thread")  # v4.1: Thread削除時にJobsはCASCADE削除せず、thread_id=NULLに設定
    sessions = relationship("DeviceSession", back_populates="thread", cascade="all, delete-orphan")

    __table_args__ = (
        # v4.2: idx_threads_room_runner削除 - runnerカラムがなくなったため
        Index("idx_threads_updated_at", "updated_at"),
    )

    def to_dict(self) -> dict:
        import json
        unread_list = []
        if self.unread_runners:
            try:
                unread_list = json.loads(self.unread_runners)
            except (json.JSONDecodeError, TypeError):
                unread_list = []
        return {
            "id": self.id,
            "room_id": self.room_id,
            "name": self.name,
            # v4.2: runnerフィールド削除
            "device_id": self.device_id,
            # v4.3: 未読フラグ（後方互換性のため残す）
            "has_unread": self.has_unread or len(unread_list) > 0,
            # v4.3.1: runner別未読リスト
            "unread_runners": unread_list,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


class DeviceSession(Base):
    __tablename__ = "device_sessions"
    __table_args__ = (
        UniqueConstraint(
            "device_id",
            "room_id",
            "runner",
            "thread_id",
            name="uq_device_room_runner_thread",
        ),
        Index("idx_device_room_runner_thread", "device_id", "room_id", "runner", "thread_id"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    device_id = Column(String(100), nullable=False)
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)  # v4.1: Room削除でCASCADE削除
    runner = Column(String(20), nullable=False)
    thread_id = Column(String(36), ForeignKey("threads.id", ondelete="CASCADE"), nullable=True)  # v4.1: 互換モード対応でNULL許容
    session_id = Column(String(64), nullable=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    # Relationships
    thread = relationship("Thread", back_populates="sessions")


class Device(Base):
    __tablename__ = "devices"

    id = Column(Integer, primary_key=True, autoincrement=True)
    device_id = Column(String(100), unique=True, nullable=False)
    device_token = Column(String(255), nullable=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)


class Job(Base):
    __tablename__ = "jobs"

    id = Column(String(36), primary_key=True)
    runner = Column(String(20), nullable=False)
    input_text = Column(Text, nullable=False)
    device_id = Column(String(100), nullable=False)
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)  # v4.1: Room削除でCASCADE削除
    thread_id = Column(String(36), ForeignKey("threads.id", ondelete="SET NULL"), nullable=True)  # v4.1: Thread削除時にNULL設定
    status = Column(String(20), nullable=False)
    exit_code = Column(Integer)
    stdout = Column(Text)
    stderr = Column(Text)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    notify_token = Column(String(255))
    created_at = Column(DateTime, nullable=False, default=utcnow)

    # Relationships
    thread = relationship("Thread", back_populates="jobs")

    __table_args__ = (
        Index("idx_jobs_thread_id", "thread_id"),
        Index("idx_jobs_room_thread", "room_id", "thread_id"),
        Index("idx_jobs_status", "status"),  # v4.1: ステータスフィルタ用
        Index("idx_jobs_created_at", "created_at"),  # v4.1: 作成日時ソート用
        Index("idx_jobs_device_id", "device_id"),  # v4.1: デバイス別フィルタ用
        Index("idx_jobs_room_id", "room_id"),  # v4.1: Room別フィルタ用
        Index("idx_jobs_device_room", "device_id", "room_id"),  # v4.1: デバイス+Room複合検索用
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "runner": self.runner,
            "input_text": self.input_text,
            "device_id": self.device_id,
            "room_id": self.room_id,
            "thread_id": self.thread_id,
            "status": self.status,
            "exit_code": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "finished_at": self.finished_at.isoformat() if self.finished_at else None,
            "notify_token": self.notify_token,
        }


class InvitationCode(Base):
    """招待コード管理テーブル。

    招待制でサブドメイン登録を許可するためのコード。
    """
    __tablename__ = "invitation_codes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    code = Column(String(32), unique=True, nullable=False, index=True)  # 招待コード（16文字のランダム文字列）
    created_by_device_id = Column(String(100), nullable=False)  # 招待コード発行者のdevice_id
    used_by_device_id = Column(String(100), nullable=True)  # 使用者のdevice_id（未使用はNULL）
    used_at = Column(DateTime, nullable=True)  # 使用日時
    expires_at = Column(DateTime, nullable=False)  # 有効期限
    created_at = Column(DateTime, nullable=False, default=utcnow)

    def is_valid(self) -> bool:
        """招待コードが有効かどうか。"""
        if self.used_by_device_id is not None:
            return False
        # timezone-awareとnaiveの比較を安全に行う
        now = utcnow()
        expires = self.expires_at
        if expires.tzinfo is None:
            from datetime import timezone
            expires = expires.replace(tzinfo=timezone.utc)
        if expires < now:
            return False
        return True

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "code": self.code,
            "created_by_device_id": self.created_by_device_id,
            "used_by_device_id": self.used_by_device_id,
            "used_at": self.used_at.isoformat() if self.used_at else None,
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "is_valid": self.is_valid(),
        }


class SubdomainRegistration(Base):
    """サブドメイン登録テーブル。

    1デバイスにつき1サブドメインのみ登録可能。
    """
    __tablename__ = "subdomain_registrations"

    id = Column(Integer, primary_key=True, autoincrement=True)
    device_id = Column(String(100), unique=True, nullable=False, index=True)  # 1デバイス1サブドメイン
    subdomain = Column(String(50), unique=True, nullable=False, index=True)  # サブドメイン名（ランダム8文字）
    tailscale_ip = Column(String(45), nullable=False)  # Tailscale IP (100.x.x.x)
    cloudflare_record_id = Column(String(50), nullable=True)  # CloudflareのDNSレコードID
    invitation_code_id = Column(Integer, ForeignKey("invitation_codes.id"), nullable=False)  # 使用した招待コード
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    # Relationships
    invitation_code = relationship("InvitationCode")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "device_id": self.device_id,
            "subdomain": self.subdomain,
            "full_domain": f"{self.subdomain}.remoteprompt.net",
            "tailscale_ip": self.tailscale_ip,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
