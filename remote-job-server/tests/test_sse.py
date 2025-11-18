"""Tests covering SSE streaming auth and manager behaviour."""
from __future__ import annotations

import asyncio
import json
from unittest import TestCase

from fastapi.testclient import TestClient

import main
from sse_manager import sse_manager


class SSEEndpointTests(TestCase):
    """Verify the HTTP endpoint enforces API key authentication."""

    def setUp(self) -> None:
        self.client = TestClient(main.app)

    def test_sse_requires_valid_api_key(self) -> None:
        response = self.client.get(
            "/jobs/test-sse-job/stream", headers={"x-api-key": "invalid"}
        )
        self.assertEqual(response.status_code, 401)


class SSEManagerBehaviourTests(TestCase):
    """Ensure the SSE manager broadcasts events to subscribers."""

    def test_broadcast_cycle(self) -> None:
        job_id = "unit-test-job"
        messages: list[str] = []

        async def runner() -> None:
            subscriber = asyncio.create_task(self._collect_first_message(job_id, messages))
            await asyncio.sleep(0)  # allow subscribe to register
            await sse_manager.broadcast(job_id, {"status": "running"})
            await sse_manager.close(job_id)
            await subscriber

        asyncio.run(runner())
        self.assertTrue(messages)
        payload = json.loads(messages[0].split("data: ")[-1])
        self.assertEqual(payload["status"], "running")

    def test_multiple_subscribers_receive_same_event(self) -> None:
        job_id = "multi-subscriber-job"
        messages_one: list[str] = []
        messages_two: list[str] = []

        async def runner() -> None:
            sub_one = asyncio.create_task(self._collect_first_message(job_id, messages_one))
            sub_two = asyncio.create_task(self._collect_first_message(job_id, messages_two))
            await asyncio.sleep(0)
            await sse_manager.broadcast(job_id, {"status": "running"})
            await sse_manager.close(job_id)
            await asyncio.gather(sub_one, sub_two)

        asyncio.run(runner())
        self.assertEqual(len(messages_one), 1)
        self.assertEqual(len(messages_two), 1)
        self.assertIn("running", messages_one[0])
        self.assertIn("running", messages_two[0])

    def test_reconnect_after_close_receives_new_event(self) -> None:
        job_id = "reconnect-job"
        first_batch: list[str] = []
        second_batch: list[str] = []

        async def runner() -> None:
            first = asyncio.create_task(self._collect_first_message(job_id, first_batch))
            await asyncio.sleep(0)
            await sse_manager.broadcast(job_id, {"status": "running"})
            await sse_manager.close(job_id)
            await first

            second = asyncio.create_task(self._collect_first_message(job_id, second_batch))
            await asyncio.sleep(0)
            await sse_manager.broadcast(job_id, {"status": "success"})
            await sse_manager.close(job_id)
            await second

        asyncio.run(runner())
        self.assertEqual(len(first_batch), 1)
        self.assertIn("running", first_batch[0])
        self.assertEqual(len(second_batch), 1)
        self.assertIn("success", second_batch[0])

    async def _collect_first_message(self, job_id: str, bucket: list[str]) -> None:
        async for message in sse_manager.subscribe(job_id):
            bucket.append(message.strip())
            break
