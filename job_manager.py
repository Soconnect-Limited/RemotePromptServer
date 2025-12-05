"""Job management logic coordinating DB operations and session execution."""
from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import datetime, timezone
from typing import List, Optional, TYPE_CHECKING

import httpx

from database import SessionLocal
from models import Job, Thread, Room
from session_manager import SessionManager
from config import settings

if TYPE_CHECKING:  # pragma: no cover
    from sse_manager import SSEManager

LOGGER = logging.getLogger(__name__)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class JobManager:
    """Provides CRUD operations for jobs and executes them via SessionManager."""

    def __init__(
        self,
        session_manager: Optional[SessionManager] = None,
        sse_manager: Optional["SSEManager"] = None,
    ) -> None:
        self.session_manager = session_manager or SessionManager()
        self.sse_manager = sse_manager
        self.notification_server_url = settings.notification_server_url

    def create_job(  # pylint: disable=too-many-arguments
        self,
        runner: str,
        input_text: str,
        device_id: str,
        room_id: str,
        workspace_path: str,
        settings: Optional[dict] = None,
        thread_id: Optional[str] = None,
        notify_token: Optional[str] = None,
        background_tasks: Optional[object] = None,
    ) -> dict:
        job = Job(
            id=str(uuid.uuid4()),
            runner=runner,
            input_text=input_text,
            device_id=device_id,
            room_id=room_id,
            thread_id=thread_id,
            status="queued",
            notify_token=notify_token,
            created_at=utcnow(),
        )
        db = SessionLocal()
        try:
            db.add(job)
            db.commit()
            db.refresh(job)
        finally:
            db.close()

        if background_tasks is not None:
            background_tasks.add_task(self._execute_job, job.id, workspace_path, settings)
        else:
            self._execute_job(job.id, workspace_path, settings)

        return job.to_dict()

    def _execute_job(self, job_id: str, workspace_path: str, settings: Optional[dict]) -> None:
        db = SessionLocal()
        try:
            job = db.query(Job).filter_by(id=job_id).first()
            if not job:
                LOGGER.warning("Job %s not found", job_id)
                return

            job.status = "running"
            job.started_at = utcnow()
            db.commit()
            self._broadcast_job_event(
                job_id,
                {
                    "status": job.status,
                    "started_at": job.started_at.isoformat(),
                },
            )

            LOGGER.info("Executing job %s (%s) in workspace %s", job_id, job.runner, workspace_path)
            result = self.session_manager.execute_job(
                runner=job.runner,
                prompt=job.input_text,
                device_id=job.device_id,
                room_id=job.room_id,
                thread_id=job.thread_id,
                workspace_path=workspace_path,
                continue_session=True,
                settings=settings,
            )

            if result.get("success"):
                job.status = "success"
                job.exit_code = 0
                job.stdout = result.get("output", "")
                job.stderr = ""
            else:
                job.status = "failed"
                job.exit_code = 1
                job.stdout = result.get("output", "")
                job.stderr = result.get("error", "")

            job.finished_at = utcnow()

            # v4.3.1: スレッドにrunner別未読フラグを設定
            if job.thread_id:
                thread = db.query(Thread).filter_by(id=job.thread_id).first()
                if thread:
                    import json
                    unread_list = []
                    if thread.unread_runners:
                        try:
                            unread_list = json.loads(thread.unread_runners)
                        except (json.JSONDecodeError, TypeError):
                            unread_list = []
                    if job.runner not in unread_list:
                        unread_list.append(job.runner)
                    thread.unread_runners = json.dumps(unread_list)
                    thread.has_unread = True
                    LOGGER.info("Set unread_runners=%s for thread %s", unread_list, job.thread_id)

            # v4.3.2: コミット前にbadge_countを取得（この時点で未読フラグは設定済み）
            # db.flush()で変更をDBに反映してからカウント
            db.flush()
            badge_count = db.query(Thread).join(Room).filter(
                Room.device_id == job.device_id,
                Thread.has_unread == True,  # noqa: E712
            ).count()
            LOGGER.info("🔔 Badge count for device %s: %d (before commit)", job.device_id, badge_count)

            db.commit()
            self._broadcast_job_event(
                job_id,
                {
                    "status": job.status,
                    "finished_at": job.finished_at.isoformat(),
                    "exit_code": job.exit_code,
                },
                close_stream=True,
            )

            # Send push notification via VPS
            if job.notify_token:
                LOGGER.info("🔔 Sending notification for token=%s with badge=%d", job.notify_token[:8], badge_count)
                try:
                    # Room名とスレッド名を取得
                    room = db.query(Room).filter_by(id=job.room_id).first()
                    thread = db.query(Thread).filter_by(id=job.thread_id).first()
                    room_name = room.name if room else "Unknown"
                    thread_name = thread.name if thread else "Default"

                    self._send_notification_via_vps(
                        device_token=job.notify_token,
                        title="推論完了",
                        body=f"{room_name}/{thread_name} - {job.runner}",
                        badge=badge_count,
                    )
                except Exception as e:
                    LOGGER.error("Failed to send notification: %s", e)
            else:
                LOGGER.debug("🔔 No notify_token, skipping notification")
        except Exception:  # pylint: disable=broad-except
            LOGGER.exception("Job %s execution failed", job_id)
            job = db.query(Job).filter_by(id=job_id).first()
            if job:
                job.status = "failed"
                job.exit_code = 1
                job.stderr = "Internal error"
                job.finished_at = utcnow()

                # v4.3.1: スレッドにrunner別未読フラグを設定（エラー時も通知）
                if job.thread_id:
                    thread = db.query(Thread).filter_by(id=job.thread_id).first()
                    if thread:
                        import json
                        unread_list = []
                        if thread.unread_runners:
                            try:
                                unread_list = json.loads(thread.unread_runners)
                            except (json.JSONDecodeError, TypeError):
                                unread_list = []
                        if job.runner not in unread_list:
                            unread_list.append(job.runner)
                        thread.unread_runners = json.dumps(unread_list)
                        thread.has_unread = True
                        LOGGER.info("Set unread_runners=%s for thread %s (error)", unread_list, job.thread_id)

                # v4.3.2: コミット前にbadge_countを取得
                db.flush()
                badge_count = db.query(Thread).join(Room).filter(
                    Room.device_id == job.device_id,
                    Thread.has_unread == True,  # noqa: E712
                ).count()
                LOGGER.info("🔔 Badge count for device %s: %d (error, before commit)", job.device_id, badge_count)

                db.commit()
                self._broadcast_job_event(
                    job_id,
                    {
                        "status": job.status,
                        "finished_at": job.finished_at.isoformat(),
                        "exit_code": job.exit_code,
                    },
                    close_stream=True,
                )

                # Send push notification via VPS
                if job.notify_token:
                    LOGGER.info("🔔 Sending notification (error) for token=%s with badge=%d", job.notify_token[:8], badge_count)
                    try:
                        # Room名とスレッド名を取得
                        room = db.query(Room).filter_by(id=job.room_id).first()
                        thread = db.query(Thread).filter_by(id=job.thread_id).first()
                        room_name = room.name if room else "Unknown"
                        thread_name = thread.name if thread else "Default"

                        self._send_notification_via_vps(
                            device_token=job.notify_token,
                            title="推論失敗",
                            body=f"{room_name}/{thread_name} - {job.runner}",
                            badge=badge_count,
                        )
                    except Exception as e:
                        LOGGER.error("Failed to send notification: %s", e)
        finally:
            db.close()

    def _send_notification_via_vps(
        self,
        device_token: str,
        title: str,
        body: str,
        badge: Optional[int] = None,
    ) -> bool:
        """Send push notification via VPS notification server.

        Args:
            device_token: APNs device token (hex string)
            title: Notification title
            body: Notification body
            badge: Badge count (optional)

        Returns:
            True if notification sent successfully, False otherwise
        """
        if not device_token:
            LOGGER.debug("No device token provided. Skipping notification.")
            return False

        try:
            payload = {
                "deviceToken": device_token,
                "title": title,
                "body": body,
            }
            if badge is not None:
                payload["badge"] = badge

            with httpx.Client(timeout=30.0) as client:
                response = client.post(
                    self.notification_server_url,
                    json=payload,
                    headers={"Content-Type": "application/json"},
                )

                if response.status_code == 200:
                    LOGGER.info("📱 Notification sent via VPS to %s: %s", device_token[:8], title)
                    return True
                else:
                    LOGGER.error(
                        "Failed to send notification via VPS to %s: HTTP %d - %s",
                        device_token[:8],
                        response.status_code,
                        response.text,
                    )
                    return False

        except Exception as exc:
            LOGGER.error("Failed to send notification via VPS to %s: %s", device_token[:8], exc)
            return False

    def get_jobs(
        self,
        limit: int = 20,
        status: Optional[str] = None,
        device_id: Optional[str] = None,
    ) -> List[dict]:
        db = SessionLocal()
        try:
            query = db.query(Job).order_by(Job.created_at.desc())
            if status:
                query = query.filter_by(status=status)
            if device_id:
                query = query.filter_by(device_id=device_id)
            return [job.to_dict() for job in query.limit(limit).all()]
        finally:
            db.close()

    def get_job(self, job_id: str) -> Optional[dict]:
        db = SessionLocal()
        try:
            job = db.query(Job).filter_by(id=job_id).first()
            return job.to_dict() if job else None
        finally:
            db.close()

    def _broadcast_job_event(
        self,
        job_id: str,
        payload: dict,
        *,
        close_stream: bool = False,
    ) -> None:
        if not self.sse_manager:
            LOGGER.warning("SSE manager not configured, skipping broadcast for job %s", job_id)
            return

        subscribers = len(getattr(self.sse_manager, "_connections", {}).get(job_id, []))
        LOGGER.info(
            "Broadcasting SSE event for job %s: %s (subscribers=%d, close_stream=%s)",
            job_id,
            payload,
            subscribers,
            close_stream,
        )

        async def _runner() -> None:
            await self.sse_manager.broadcast(job_id, payload)
            if close_stream:
                await self.sse_manager.close(job_id)

        self._run_async(_runner())

    def _run_async(self, coro) -> None:
        if not self.sse_manager:
            LOGGER.warning("_run_async called but sse_manager is None")
            return

        loop = getattr(self.sse_manager, "loop", None)

        if loop and not loop.is_closed():
            try:
                current_loop = asyncio.get_running_loop()
            except RuntimeError:
                current_loop = None

            try:
                if current_loop is loop:
                    loop.create_task(coro)
                else:
                    asyncio.run_coroutine_threadsafe(coro, loop)
                return
            except Exception as exc:  # pragma: no cover - scheduling errors
                LOGGER.warning("Failed to schedule SSE coroutine threadsafe: %s", exc, exc_info=True)

        try:
            asyncio.run(coro)
        except RuntimeError as exc:  # pragma: no cover - nested loop
            LOGGER.warning("Failed to run SSE coroutine: %s", exc, exc_info=True)
