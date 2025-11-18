"""FastAPI application exposing the Remote Job Server API."""
from __future__ import annotations

from typing import List, Optional

from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    HTTPException,
    Header,
    Query,
    Request,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from config import setup_logging, settings
from database import SessionLocal, init_db
from job_manager import JobManager
from models import Device, DeviceSession, utcnow
from session_manager import SessionManager
from sse_manager import sse_manager

app = FastAPI(title="Remote Job Server")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

session_manager = SessionManager()
job_manager = JobManager(session_manager=session_manager, sse_manager=sse_manager)
ALLOWED_RUNNERS = {"claude", "codex"}


def get_db() -> Session:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


class RegisterDeviceRequest(BaseModel):
    device_id: str
    device_token: str


class CreateJobRequest(BaseModel):
    runner: str
    input_text: str
    device_id: str
    notify_token: Optional[str] = None


class JobSummary(BaseModel):
    id: str
    runner: str
    status: str


@app.on_event("startup")
def startup_event() -> None:
    setup_logging()
    init_db()


def verify_api_key(x_api_key: str = Header(...)) -> None:
    if x_api_key != settings.api_key:
        raise HTTPException(status_code=401, detail="Invalid API Key")


@app.post("/register_device")
def register_device(
    req: RegisterDeviceRequest,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    device = db.query(Device).filter_by(device_id=req.device_id).first()
    if device:
        device.device_token = req.device_token
        device.updated_at = utcnow()
    else:
        device = Device(
            device_id=req.device_id,
            device_token=req.device_token,
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.add(device)
    db.commit()
    return {"status": "registered"}


@app.post("/jobs", response_model=JobSummary)
def create_job(
    req: CreateJobRequest,
    background_tasks: BackgroundTasks,
    _: None = Depends(verify_api_key),
) -> JobSummary:
    if req.runner not in ALLOWED_RUNNERS:
        raise HTTPException(status_code=400, detail="Unsupported runner")
    try:
        job = job_manager.create_job(
            runner=req.runner,
            input_text=req.input_text,
            device_id=req.device_id,
            notify_token=req.notify_token,
            background_tasks=background_tasks,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return JobSummary(id=job["id"], runner=job["runner"], status=job["status"])


@app.get("/jobs")
def list_jobs(
    limit: int = 20,
    status: Optional[str] = None,
    device_id: Optional[str] = None,
    _: None = Depends(verify_api_key),
) -> List[dict]:
    return job_manager.get_jobs(limit=limit, status=status, device_id=device_id)


@app.get("/jobs/{job_id}")
def get_job(job_id: str, _: None = Depends(verify_api_key)) -> dict:
    job = job_manager.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


@app.get("/jobs/{job_id}/stream", dependencies=[Depends(verify_api_key)])
async def stream_job_status(job_id: str, request: Request) -> StreamingResponse:
    """Stream job status updates via Server-Sent Events."""

    async def event_generator():
        async for message in sse_manager.subscribe(job_id):
            if await request.is_disconnected():
                break
            yield message

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.get("/sessions")
def get_sessions(
    device_id: str = Query(...),
    _: None = Depends(verify_api_key),
) -> dict:
    return {
        "claude": session_manager.get_session_status("claude", device_id),
        "codex": session_manager.get_session_status("codex", device_id),
    }


@app.delete("/sessions/{runner}")
def delete_session(
    runner: str,
    device_id: str = Query(...),
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    record = db.query(DeviceSession).filter_by(device_id=device_id, runner=runner).first()
    if not record:
        raise HTTPException(status_code=404, detail="Session not found")
    db.delete(record)
    db.commit()
    return {"status": "deleted", "runner": runner, "device_id": device_id}


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
