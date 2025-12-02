"""Utilities for managing Server-Sent Events connections per job."""
from __future__ import annotations

import asyncio
import json
import logging
from time import time
from typing import AsyncGenerator, Dict, Optional, Set

LOGGER = logging.getLogger(__name__)


class SSEManager:
    """Tracks active SSE subscriptions and broadcasts job status updates."""

    def __init__(self) -> None:
        self._connections: Dict[str, Set[asyncio.Queue]] = {}
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        # Global event subscribers (for certificate events, etc.)
        self._global_subscribers: Set[asyncio.Queue] = set()
        # Rate limiting for broadcast events (event_name -> last_broadcast_time)
        self._event_rate_limits: Dict[str, float] = {}

    @property
    def loop(self) -> Optional[asyncio.AbstractEventLoop]:
        return self._loop

    async def subscribe(self, job_id: str) -> AsyncGenerator[str, None]:
        """Register an SSE subscriber for the specified job."""
        current_loop = asyncio.get_running_loop()
        if self._loop is None or self._loop.is_closed():
            self._loop = current_loop
        queue: asyncio.Queue = asyncio.Queue()
        self._connections.setdefault(job_id, set()).add(queue)
        LOGGER.info("SSE connection opened for job %s (subscribers=%d)", job_id, len(self._connections[job_id]))

        HEARTBEAT_INTERVAL = 30.0

        try:
            while True:
                try:
                    payload = await asyncio.wait_for(queue.get(), timeout=HEARTBEAT_INTERVAL)
                    if payload is None:
                        LOGGER.info("[SSE-CLOSE] job_id=%s, received None, closing stream", job_id)
                        break
                    LOGGER.debug("[SSE-SEND] job_id=%s, payload_keys=%s", job_id, list(payload.keys()))
                    yield f"data: {json.dumps(payload)}\n\n"
                except asyncio.TimeoutError:
                    LOGGER.debug("[SSE-HEARTBEAT] job_id=%s", job_id)
                    yield ":heartbeat\n\n"
        finally:
            if job_id in self._connections:
                self._connections[job_id].discard(queue)
                if not self._connections[job_id]:
                    del self._connections[job_id]
            LOGGER.info(
                "SSE connection closed for job %s (remaining_subscribers=%d)",
                job_id,
                len(self._connections.get(job_id, [])),
            )

    async def broadcast(self, job_id: str, payload: dict) -> None:
        """Send a payload to all subscribers of the specified job."""
        connections = self._connections.get(job_id)
        if not connections:
            return
        LOGGER.debug("Broadcasting SSE event to %d subscribers for job %s", len(connections), job_id)
        for queue in list(connections):
            await queue.put(payload)

    async def close(self, job_id: str) -> None:
        """Gracefully close all SSE connections for a job."""
        connections = self._connections.pop(job_id, set())
        for queue in connections:
            await queue.put(None)

    async def broadcast_event(
        self,
        event_name: str,
        payload: dict,
        rate_limit_seconds: int = 300,
    ) -> int:
        """Broadcast an event to all active SSE connections.

        Used for certificate change notifications and other global events.

        Args:
            event_name: Name of the event (for rate limiting and SSE event field)
            payload: Event data payload to broadcast
            rate_limit_seconds: Minimum seconds between same events (default: 5 minutes)

        Returns:
            Number of connections that received the event

        Note: The payload is wrapped with an 'event' field for proper SSE formatting.
        Global subscribers (/events endpoint) format it as:
            event: {event_name}
            data: {json payload}
        """
        now = time()

        # Check rate limit
        last_broadcast = self._event_rate_limits.get(event_name, 0)
        if now - last_broadcast < rate_limit_seconds:
            LOGGER.warning(
                "[SSE-RATE-LIMIT] Event %s rate limited, last broadcast %d seconds ago",
                event_name,
                int(now - last_broadcast),
            )
            return 0

        self._event_rate_limits[event_name] = now

        # Wrap payload with event name for proper SSE handling
        wrapped_payload = {
            "event": event_name,
            "data": payload,
        }

        # Broadcast to all job subscribers (for backwards compatibility)
        sent_count = 0
        for job_id, connections in self._connections.items():
            for queue in list(connections):
                try:
                    await queue.put(wrapped_payload)
                    sent_count += 1
                except Exception as e:
                    LOGGER.warning("Failed to send event to queue: %s", e)

        # Broadcast to global subscribers (/events endpoint)
        for queue in list(self._global_subscribers):
            try:
                await queue.put(wrapped_payload)
                sent_count += 1
            except Exception as e:
                LOGGER.warning("Failed to send event to global subscriber: %s", e)

        LOGGER.info(
            "[SSE-BROADCAST] Event %s sent to %d connections",
            event_name,
            sent_count,
        )
        return sent_count


sse_manager = SSEManager()
