"""Job management logic coordinating DB operations and session execution."""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from database import SessionLocal
from models import Job
from session_manager import SessionManager

LOGGER = logging.getLogger(__name__)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class JobManager:
    """Provides CRUD operations for jobs and executes them via SessionManager."""

    def __init__(self, session_manager: Optional[SessionManager] = None):
        self.session_manager = session_manager or SessionManager()

    def create_job(
        self,
        runner: str,
        input_text: str,
        device_id: str,
        notify_token: Optional[str] = None,
        background_tasks: Optional[object] = None,
    ) -> dict:
        job = Job(
            id=str(uuid.uuid4()),
            runner=runner,
            input_text=input_text,
            device_id=device_id,
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
            background_tasks.add_task(self._execute_job, job.id)
        else:
            self._execute_job(job.id)

        return job.to_dict()

    def _execute_job(self, job_id: str) -> None:
        db = SessionLocal()
        try:
            job = db.query(Job).filter_by(id=job_id).first()
            if not job:
                LOGGER.warning("Job %s not found", job_id)
                return

            job.status = "running"
            job.started_at = utcnow()
            db.commit()

            LOGGER.info("Executing job %s (%s)", job_id, job.runner)
            result = self.session_manager.execute_job(
                runner=job.runner,
                prompt=job.input_text,
                device_id=job.device_id,
                continue_session=True,
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
            db.commit()
        except Exception:  # pylint: disable=broad-except
            LOGGER.exception("Job %s execution failed", job_id)
            job = db.query(Job).filter_by(id=job_id).first()
            if job:
                job.status = "failed"
                job.exit_code = 1
                job.stderr = "Internal error"
                job.finished_at = utcnow()
                db.commit()
        finally:
            db.close()

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
