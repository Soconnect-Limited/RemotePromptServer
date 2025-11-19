"""FastAPI application exposing the Remote Job Server API."""
from __future__ import annotations

import uuid
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
from models import Device, DeviceSession, Job, Room, utcnow
from session_manager import SessionManager
from sse_manager import sse_manager
from utils.path_validator import validate_workspace_path

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
    room_id: str
    notify_token: Optional[str] = None


class CreateRoomRequest(BaseModel):
    device_id: str
    name: str
    workspace_path: str
    icon: str = "folder"


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


# ========== Room Management APIs ==========


@app.get("/rooms")
def get_rooms(
    device_id: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> List[dict]:
    rooms = db.query(Room).filter_by(device_id=device_id).order_by(Room.updated_at.desc()).all()
    return [room.to_dict() for room in rooms]


@app.post("/rooms")
def create_room(
    req: CreateRoomRequest,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    try:
        validated_path = validate_workspace_path(req.workspace_path)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    room = Room(
        id=str(uuid.uuid4()),
        name=req.name,
        workspace_path=validated_path,
        icon=req.icon,
        device_id=req.device_id,
        created_at=utcnow(),
        updated_at=utcnow(),
    )
    db.add(room)
    db.commit()
    db.refresh(room)
    return room.to_dict()


@app.delete("/rooms/{room_id}")
def delete_room(
    room_id: str,
    device_id: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    room = db.query(Room).filter_by(id=room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    if room.device_id != device_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    db.query(DeviceSession).filter_by(room_id=room_id).delete()
    db.query(Job).filter_by(room_id=room_id).delete()
    db.delete(room)
    db.commit()
    return {"status": "ok"}


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
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> JobSummary:
    if req.runner not in ALLOWED_RUNNERS:
        raise HTTPException(status_code=400, detail="Unsupported runner")
    room = db.query(Room).filter_by(id=req.room_id, device_id=req.device_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    try:
        job = job_manager.create_job(
            runner=req.runner,
            input_text=req.input_text,
            device_id=req.device_id,
            room_id=req.room_id,
            workspace_path=room.workspace_path,
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


@app.get("/messages")
def get_messages(
    device_id: str,
    room_id: str,
    runner: str,
    limit: int = 20,
    offset: int = 0,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> List[dict]:
    room = db.query(Room).filter_by(id=room_id, device_id=device_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")

    jobs = (
        db.query(Job)
        .filter_by(device_id=device_id, room_id=room_id, runner=runner)
        .order_by(Job.created_at.desc())
        .limit(limit)
        .offset(offset)
        .all()
    )
    return [job.to_dict() for job in reversed(jobs)]


@app.delete("/sessions")
def delete_session(
    device_id: str,
    room_id: str,
    runner: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    deleted = (
        db.query(DeviceSession)
        .filter_by(device_id=device_id, room_id=room_id, runner=runner)
        .delete()
    )
    db.commit()
    return {"status": "ok", "deleted": deleted}


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
