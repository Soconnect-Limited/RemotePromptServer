"""Database-level tests covering Job model persistence."""
from __future__ import annotations

import unittest
from datetime import datetime, timezone

from database import Base, SessionLocal, engine, init_db
from models import Job


class JobModelTests(unittest.TestCase):
    """Verify CRUD operations for the Job model."""

    def setUp(self) -> None:
        Base.metadata.drop_all(bind=engine)
        init_db()
        self.db = SessionLocal()

    def tearDown(self) -> None:
        self.db.close()
        Base.metadata.drop_all(bind=engine)

    def test_job_insert_and_to_dict(self) -> None:
        job = Job(
            id="job-123",
            runner="claude",
            input_text="テスト",
            device_id="device-1",
            status="queued",
            exit_code=None,
            stdout=None,
            stderr=None,
        )
        self.db.add(job)
        self.db.commit()

        stored = self.db.query(Job).filter_by(id="job-123").first()
        self.assertIsNotNone(stored)
        data = stored.to_dict()
        self.assertEqual(data["runner"], "claude")
        self.assertIsNone(data["exit_code"])
        self.assertIn("created_at", data)

    def test_job_update_status_and_timestamps(self) -> None:
        job = Job(
            id="job-456",
            runner="codex",
            input_text="hello",
            device_id="device-2",
            status="queued",
        )
        self.db.add(job)
        self.db.commit()

        job.status = "success"
        job.exit_code = 0
        job.started_at = datetime.now(timezone.utc)
        job.finished_at = datetime.now(timezone.utc)
        self.db.commit()

        updated = self.db.query(Job).filter_by(id="job-456").first()
        self.assertEqual(updated.status, "success")
        self.assertEqual(updated.exit_code, 0)
        self.assertIsNotNone(updated.started_at)
        self.assertIsNotNone(updated.finished_at)


if __name__ == "__main__":
    unittest.main()
