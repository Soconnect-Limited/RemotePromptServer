"""API error scenario tests."""
from __future__ import annotations

from unittest import TestCase
from unittest.mock import MagicMock

from fastapi.testclient import TestClient

import main
from database import Base, engine, init_db


class APIErrorTests(TestCase):
    def setUp(self) -> None:
        Base.metadata.drop_all(bind=engine)
        init_db()
        self.client = TestClient(main.app)
        self.headers = {"x-api-key": main.settings.api_key}

    def tearDown(self) -> None:
        Base.metadata.drop_all(bind=engine)

    def test_invalid_runner_returns_400(self) -> None:
        res = self.client.post(
            "/jobs",
            json={
                "runner": "invalid",
                "input_text": "test",
                "device_id": "err",
                "room_id": "room-x",
            },
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 400)

    def test_job_not_found(self) -> None:
        main.job_manager.session_manager = MagicMock()
        main.session_manager = MagicMock()
        res = self.client.get("/jobs/missing", headers=self.headers)
        self.assertEqual(res.status_code, 404)
