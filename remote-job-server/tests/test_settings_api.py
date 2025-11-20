"""Tests for room settings GET/PUT endpoints."""
from __future__ import annotations

import os
from unittest import TestCase

os.environ["DATABASE_URL"] = "sqlite:///./data/test_settings.db"

from fastapi.testclient import TestClient  # pylint: disable=wrong-import-position

import main  # pylint: disable=wrong-import-position
from database import Base, engine, init_db  # pylint: disable=wrong-import-position


class RoomSettingsAPITests(TestCase):
    def setUp(self) -> None:
        Base.metadata.drop_all(bind=engine)
        init_db()
        self.client = TestClient(main.app)
        self.headers = {"x-api-key": main.settings.api_key}
        # create room
        res = self.client.post(
            "/rooms",
            json={
                "device_id": "dev-rooms",
                "name": "room",
                "workspace_path": "/Users/macstudio/Projects/RemotePrompt",
                "icon": "📁",
            },
            headers=self.headers,
        )
        assert res.status_code == 200
        self.room_id = res.json()["id"]

    def tearDown(self) -> None:
        Base.metadata.drop_all(bind=engine)

    def test_get_settings_null(self) -> None:
        res = self.client.get(
            f"/rooms/{self.room_id}/settings",
            params={"device_id": "dev-rooms"},
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200)
        self.assertIsNone(res.json()["settings"])

    def test_put_settings_success(self) -> None:
        payload = {
            "codex": {
                "model": "gpt-5.1-codex",
                "sandbox": "workspace-write",
                "approval_policy": "on-failure",
                "reasoning_effort": "high",
            }
        }
        res = self.client.put(
            f"/rooms/{self.room_id}/settings",
            params={"device_id": "dev-rooms"},
            headers={**self.headers, "Content-Type": "application/json"},
            json=payload,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["settings"], payload)

        # ensure GET returns saved value
        res_get = self.client.get(
            f"/rooms/{self.room_id}/settings",
            params={"device_id": "dev-rooms"},
            headers=self.headers,
        )
        self.assertEqual(res_get.status_code, 200)
        self.assertEqual(res_get.json()["settings"], payload)

    def test_put_settings_size_limit(self) -> None:
        big_value = "x" * 10_241
        res = self.client.put(
            f"/rooms/{self.room_id}/settings",
            params={"device_id": "dev-rooms"},
            headers={**self.headers, "Content-Type": "application/json"},
            data=f'{{"codex":{{"model":"{big_value}"}}}}',
        )
        self.assertEqual(res.status_code, 413)
        self.assertIn("exceeds 10KB", res.json()["detail"])

    def test_put_settings_null_reset(self) -> None:
        """Test null body resets settings to default (implementation plan v1.6:217-226)."""
        # First, set a custom setting
        payload = {"codex": {"model": "gpt-5.1-codex-max"}}
        res = self.client.put(
            f"/rooms/{self.room_id}/settings",
            params={"device_id": "dev-rooms"},
            headers={**self.headers, "Content-Type": "application/json"},
            json=payload,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["settings"], payload)

        # Now reset with null body
        res_reset = self.client.put(
            f"/rooms/{self.room_id}/settings",
            params={"device_id": "dev-rooms"},
            headers={**self.headers, "Content-Type": "application/json"},
            data=b"null",
        )
        self.assertEqual(res_reset.status_code, 200)
        self.assertIsNone(res_reset.json()["settings"])

        # Verify GET also returns null
        res_get = self.client.get(
            f"/rooms/{self.room_id}/settings",
            params={"device_id": "dev-rooms"},
            headers=self.headers,
        )
        self.assertEqual(res_get.status_code, 200)
        self.assertIsNone(res_get.json()["settings"])
