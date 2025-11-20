"""Lightweight performance-style tests for JobManager."""
from __future__ import annotations

import unittest

from database import Base, engine, init_db
from job_manager import JobManager


class FastStubSessionManager:
    def __init__(self) -> None:
        self.count = 0

    def execute_job(
        self,
        runner: str,
        prompt: str,
        device_id: str,
        room_id: str,
        workspace_path: str | None = None,
        continue_session: bool = True,
        settings: dict | None = None,
        thread_id: str | None = None,
    ):
        self.count += 1
        return {"success": True, "output": prompt, "error": ""}

    def get_session_status(self, runner: str, device_id: str, room_id: str, thread_id: str):
        return {"exists": False, "session_id": None}


class PerformanceTests(unittest.TestCase):
    def setUp(self) -> None:
        Base.metadata.drop_all(bind=engine)
        init_db()
        self.stub = FastStubSessionManager()
        self.manager = JobManager(session_manager=self.stub)

    def tearDown(self) -> None:
        Base.metadata.drop_all(bind=engine)

    def test_three_jobs_quickly(self) -> None:
        for idx in range(3):
            self.manager.create_job("claude", f"load-{idx}", "perf-device", room_id="room-perf", workspace_path="/tmp", thread_id=f"t{idx}")
        self.assertEqual(self.stub.count, 3)

    def test_long_running_prompt_placeholder(self) -> None:
        self.manager.create_job("codex", "long-run", "perf-device-2", room_id="room-perf2", workspace_path="/tmp", thread_id="t-long")
        self.assertEqual(self.stub.count, 1)

    def test_timeout_result_sets_failed_status(self) -> None:
        class TimeoutStub(FastStubSessionManager):
            def execute_job(self, runner, prompt, device_id, room_id, workspace_path=None, continue_session=True, settings=None, thread_id=None):  # type: ignore[override]
                raise TimeoutError("simulated timeout")

        stub = TimeoutStub()
        manager = JobManager(session_manager=stub)
        manager.create_job("claude", "timeout", "device-timeout", room_id="room-timeout", workspace_path="/tmp", thread_id="t-timeout")
        # Fetch job to ensure status == failed
        from models import Job  # local import to avoid circular
        from database import SessionLocal

        db = SessionLocal()
        try:
            job = db.query(Job).filter_by(device_id="device-timeout").first()
            self.assertEqual(job.status, "failed")
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
