"""Unit tests for session_manager module (CLI subprocess mocked)."""
from __future__ import annotations

import subprocess
import uuid
from unittest import TestCase
from unittest.mock import MagicMock, patch

from database import Base, SessionLocal, engine, init_db
from models import DeviceSession
from session_manager import ClaudeSessionManager, CodexSessionManager


class SessionManagerTestCase(TestCase):
    """Tests verifying DB persistence logic with mocked subprocess calls."""

    def setUp(self) -> None:
        Base.metadata.drop_all(bind=engine)
        init_db()

    def tearDown(self) -> None:
        Base.metadata.drop_all(bind=engine)

    @patch("session_manager.subprocess.run")
    @patch("session_manager.uuid.uuid4")
    def test_claude_session_persists_new_id(
        self,
        mock_uuid: MagicMock,
        mock_run: MagicMock,
    ) -> None:
        fake_uuid = uuid.UUID("019a9134-ad13-46d1-9579-efff00095049")
        mock_uuid.return_value = fake_uuid
        mock_run.return_value = subprocess.CompletedProcess(
            args=["claude"],
            returncode=0,
            stdout="response",
            stderr="",
        )

        manager = ClaudeSessionManager(trusted_directory=".")
        result = manager.execute_job("hello", "device-a")

        self.assertTrue(result["success"])
        self.assertEqual(result["session_id"], str(fake_uuid))

        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id="device-a", runner="claude")
                .first()
            )
            self.assertIsNotNone(record)
            self.assertEqual(record.session_id, str(fake_uuid))
        finally:
            db.close()

    @patch("session_manager.subprocess.run")
    def test_codex_session_extracts_and_persists(
        self,
        mock_run: MagicMock,
    ) -> None:
        session_output = """codex exec
session id: 123e4567-e89b-12d3-a456-426614174000
**結論** ok
"""
        mock_run.return_value = subprocess.CompletedProcess(
            args=["codex"],
            returncode=0,
            stdout=session_output,
            stderr="",
        )

        manager = CodexSessionManager()
        result = manager.execute_job("hi", "device-b")

        self.assertTrue(result["success"])
        self.assertEqual(
            result["session_id"], "123e4567-e89b-12d3-a456-426614174000"
        )

        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id="device-b", runner="codex")
                .first()
            )
            self.assertIsNotNone(record)
            self.assertEqual(
                record.session_id,
                "123e4567-e89b-12d3-a456-426614174000",
            )
        finally:
            db.close()
