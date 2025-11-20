"""Unit tests for JobManager with mocked SessionManager."""
from __future__ import annotations

import unittest
from unittest.mock import MagicMock

from database import Base, SessionLocal, engine, init_db
from job_manager import JobManager
from models import Job


class JobManagerTests(unittest.TestCase):
    """Confirm JobManager coordinates execution and persistence."""

    def setUp(self) -> None:
        Base.metadata.drop_all(bind=engine)
        init_db()

    def tearDown(self) -> None:
        Base.metadata.drop_all(bind=engine)

    def test_create_job_and_execute_success(self) -> None:
        fake_session = MagicMock()
        fake_session.execute_job.return_value = {
            "success": True,
            "output": "done",
            "error": "",
        }
        manager = JobManager(session_manager=fake_session)

        job_dict = manager.create_job(
            "claude",
            "say hi",
            "dev-1",
            room_id="room-1",
            workspace_path="/tmp",
        )
        self.assertEqual(job_dict["status"], "queued")

        db = SessionLocal()
        try:
            job = db.query(Job).filter_by(id=job_dict["id"]).first()
            self.assertEqual(job.status, "success")
            self.assertEqual(job.exit_code, 0)
            self.assertEqual(job.stdout, "done")
        finally:
            db.close()

    def test_create_job_failure_path(self) -> None:
        fake_session = MagicMock()
        fake_session.execute_job.return_value = {
            "success": False,
            "output": "",
            "error": "boom",
        }
        manager = JobManager(session_manager=fake_session)

        job_dict = manager.create_job(
            "codex",
            "fail",
            "dev-2",
            room_id="room-2",
            workspace_path="/tmp",
        )

        db = SessionLocal()
        try:
            job = db.query(Job).filter_by(id=job_dict["id"]).first()
            self.assertEqual(job.status, "failed")
            self.assertEqual(job.exit_code, 1)
            self.assertEqual(job.stderr, "boom")
        finally:
            db.close()

    def test_get_jobs_filters(self) -> None:
        fake_session = MagicMock()
        fake_session.execute_job.return_value = {"success": True, "output": "", "error": ""}
        manager = JobManager(session_manager=fake_session)
        manager.create_job("claude", "one", "device-a", room_id="room-a", workspace_path="/tmp")
        manager.create_job("claude", "two", "device-b", room_id="room-b", workspace_path="/tmp")

        jobs = manager.get_jobs(device_id="device-a")
        self.assertEqual(len(jobs), 1)
        self.assertEqual(jobs[0]["device_id"], "device-a")


if __name__ == "__main__":
    unittest.main()
