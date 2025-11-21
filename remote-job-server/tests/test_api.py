"""API tests for FastAPI app using TestClient."""
from __future__ import annotations

import os
from unittest import TestCase
from unittest.mock import MagicMock

os.environ["DATABASE_URL"] = "sqlite:///./data/test_api.db"

from fastapi.testclient import TestClient  # pylint: disable=wrong-import-position

import main  # pylint: disable=wrong-import-position
from database import Base, engine, init_db, SessionLocal  # pylint: disable=wrong-import-position
from models import DeviceSession, Room, Thread, utcnow  # pylint: disable=wrong-import-position


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
            room = Room(
                id="room-xyz",
                name="tmp",
                workspace_path="/tmp",
                icon="folder",
                device_id="dev-2",
                created_at=utcnow(),
                updated_at=utcnow(),
            )
            thread = Thread(
                id="thread-xyz",
                room_id="room-xyz",
                name="thread",
                device_id="dev-2",
                created_at=utcnow(),
                updated_at=utcnow(),
            )
            db.add(room)
            db.add(thread)
            db.add(
                DeviceSession(
                    device_id="dev-2",
                    room_id="room-xyz",
                    runner="claude",
                    thread_id="thread-xyz",
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
            params={
                "device_id": "dev-2",
                "room_id": "room-xyz",
                "runner": "claude",
                "thread_id": "thread-xyz",
            },
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")

    def test_health(self) -> None:
        res = self.client.get("/health")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")

    def test_thread_response_schema_v4_2(self) -> None:
        """v4.2: ThreadResponseにrunnerフィールドが含まれないことを検証（回帰防止）"""
        # Thread作成
        res = self.client.post(
            f"/rooms/{self.room_id}/threads",
            json={"name": "Test Thread"},
            params={"device_id": "dev-1"},
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200, f"Thread creation failed: {res.text}")
        thread_data = res.json()

        # レスポンススキーマ検証
        self.assertIn("id", thread_data)
        self.assertIn("room_id", thread_data)
        self.assertIn("name", thread_data)
        self.assertIn("device_id", thread_data)
        self.assertIn("created_at", thread_data)
        self.assertIn("updated_at", thread_data)

        # v4.2: runnerフィールドが含まれないことを確認
        self.assertNotIn("runner", thread_data, "v4.2: runner field must not exist in ThreadResponse")

        thread_id = thread_data["id"]

        # GET /threads でも同様に検証
        res = self.client.get(
            f"/rooms/{self.room_id}/threads",
            params={"device_id": "dev-1"},
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200)
        threads = res.json()
        self.assertGreater(len(threads), 0)

        for thread in threads:
            self.assertNotIn("runner", thread, "v4.2: runner field must not exist in list response")

        # PATCH /threads でも同様に検証
        res = self.client.patch(
            f"/threads/{thread_id}",
            json={"name": "Updated Thread"},
            params={"device_id": "dev-1"},
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200)
        updated_thread = res.json()
        self.assertNotIn("runner", updated_thread, "v4.2: runner field must not exist in update response")
