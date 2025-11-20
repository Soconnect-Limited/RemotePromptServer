"""API tests for FastAPI app using TestClient."""
from __future__ import annotations

import os
from unittest import TestCase
from unittest.mock import MagicMock

os.environ["DATABASE_URL"] = "sqlite:///./data/test_api.db"

from fastapi.testclient import TestClient  # pylint: disable=wrong-import-position

import main  # pylint: disable=wrong-import-position
from database import Base, engine, init_db, SessionLocal  # pylint: disable=wrong-import-position
from models import DeviceSession, utcnow  # pylint: disable=wrong-import-position


class APITests(TestCase):
    """Covers register_device, jobs, sessions, health endpoints."""

    def setUp(self) -> None:
        Base.metadata.drop_all(bind=engine)
        init_db()
        self.client = TestClient(main.app)
        self.headers = {"x-api-key": main.settings.api_key}
        fake_session = MagicMock()
        fake_session.execute_job.return_value = {
            "success": True,
            "output": "done",
            "error": "",
        }
        fake_session.get_session_status.return_value = {
            "exists": False,
            "session_id": None,
        }
        main.job_manager.session_manager = fake_session
        main.session_manager = fake_session

        room_res = self.client.post(
            "/rooms",
            json={
                "device_id": "dev-1",
                "name": "test room",
                "workspace_path": "/Users/macstudio/Projects/RemotePrompt",
                "icon": "📁",
            },
            headers=self.headers,
        )
        self.room_id = room_res.json()["id"]

    def tearDown(self) -> None:
        Base.metadata.drop_all(bind=engine)

    def test_job_flow(self) -> None:
        res = self.client.post(
            "/register_device",
            json={"device_id": "dev-1", "device_token": "token"},
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200)

        res = self.client.post(
            "/jobs",
            json={
                "runner": "claude",
                "input_text": "hello",
                "device_id": "dev-1",
                "room_id": self.room_id,
            },
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200)
        job_id = res.json()["id"]

        res = self.client.get("/jobs", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertGreaterEqual(len(res.json()), 1)

        res = self.client.get(f"/jobs/{job_id}", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["id"], job_id)

    def test_session_endpoints(self) -> None:
        db = SessionLocal()
        try:
            db.add(
                DeviceSession(
                    device_id="dev-2",
                    room_id="room-xyz",
                    runner="claude",
                    session_id="session-1",
                    created_at=utcnow(),
                    updated_at=utcnow(),
                )
            )
            db.commit()
        finally:
            db.close()

        res = self.client.delete(
            "/sessions",
            params={"device_id": "dev-2", "room_id": "room-xyz", "runner": "claude"},
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")

    def test_health(self) -> None:
        res = self.client.get("/health")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")
