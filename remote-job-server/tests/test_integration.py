"""Integration scenarios covering session flows using JobManager and a stub session manager."""
from __future__ import annotations

import unittest

from database import Base, engine, init_db
from job_manager import JobManager


class StubSessionManager:
    """Simple in-memory session tracker used for integration tests."""

    def __init__(self) -> None:
        self.sessions = {}
        self.calls = []

    def execute_job(
        self,
        runner: str,
        prompt: str,
        device_id: str,
        room_id: str,
        workspace_path: str | None = None,
        continue_session: bool = True,
        settings: dict | None = None,
    ):
        key = (runner, device_id)
        if not continue_session or key not in self.sessions:
            session_id = f"{runner}-{device_id}-{len(self.calls)+1}"
            self.sessions[key] = session_id
        else:
            session_id = self.sessions[key]
        self.calls.append((runner, device_id, prompt, session_id, room_id, workspace_path, settings))
        return {
            "success": True,
            "output": f"ok:{prompt}",
            "error": "",
            "session_id": session_id,
        }

    def get_session_status(self, runner: str, device_id: str, room_id: str):
        key = (runner, device_id)
        session_id = self.sessions.get(key)
        return {"exists": session_id is not None, "session_id": session_id}


class IntegrationTests(unittest.TestCase):
    """Covers Phase 4 scenarios using JobManager with a stub session layer."""

    def setUp(self) -> None:
        Base.metadata.drop_all(bind=engine)
        init_db()
        self.stub = StubSessionManager()
        self.manager = JobManager(session_manager=self.stub)

    def tearDown(self) -> None:
        Base.metadata.drop_all(bind=engine)

    def test_claude_session_resume(self) -> None:
        self.manager.create_job("claude", "first", "dev-a", room_id="room-a", workspace_path="/tmp")
        first = self.stub.sessions[("claude", "dev-a")]
        self.manager.create_job("claude", "second", "dev-a", room_id="room-a", workspace_path="/tmp")
        second = self.stub.sessions[("claude", "dev-a")]
        self.assertEqual(first, second)

    def test_codex_session_resume(self) -> None:
        self.manager.create_job("codex", "hello", "dev-b", room_id="room-b", workspace_path="/tmp")
        self.manager.create_job("codex", "follow", "dev-b", room_id="room-b", workspace_path="/tmp")
        session_id = self.stub.sessions[("codex", "dev-b")]
        self.assertTrue(session_id.startswith("codex-dev-b"))

    def test_session_delete_and_recreate(self) -> None:
        self.manager.create_job("claude", "once", "dev-c", room_id="room-c", workspace_path="/tmp")
        first_session = self.stub.sessions[("claude", "dev-c")]
        self.stub.sessions.pop(("claude", "dev-c"), None)
        self.manager.create_job("claude", "again", "dev-c", room_id="room-c", workspace_path="/tmp")
        second_session = self.stub.sessions[("claude", "dev-c")]
        self.assertNotEqual(first_session, second_session)

    def test_multiple_devices_isolated(self) -> None:
        self.manager.create_job("claude", "dev1", "dev-1", room_id="room-1", workspace_path="/tmp")
        self.manager.create_job("claude", "dev2", "dev-2", room_id="room-2", workspace_path="/tmp")
        self.assertNotEqual(
            self.stub.sessions[("claude", "dev-1")],
            self.stub.sessions[("claude", "dev-2")],
        )


if __name__ == "__main__":
    unittest.main()
