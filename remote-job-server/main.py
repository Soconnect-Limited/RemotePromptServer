"""FastAPI application exposing the Remote Job Server API."""
from __future__ import annotations

import uuid
import json
from typing import List, Optional

from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    HTTPException,
    Header,
    Query,
    Request,
    Response,
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
from utils.settings_validator import (
    ALLOWED_VALUES,
    RESERVED_FLAGS,
    DANGEROUS_FLAGS,
    SHELL_META_CHARS,
    ValidationError,
    validate_settings,
)
from auth_helpers import verify_room_ownership
from file_operations import list_files, read_file, write_file, WriteResult
from file_security import FileSizeExceeded, InvalidExtension, InvalidPath

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
MAX_SETTINGS_BYTES = 10_240  # 10KB


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


# ========== Room Settings APIs ==========


@app.get("/rooms/{room_id}/settings")
async def get_room_settings(
    room_id: str,
    device_id: str = Query(...),
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    room = await verify_room_ownership(room_id=room_id, device_id=device_id, db=db)
    try:
        parsed = json.loads(room.settings) if room.settings else None
    except json.JSONDecodeError:
        parsed = None
    return {"room_id": room_id, "settings": parsed}


@app.put("/rooms/{room_id}/settings")
async def update_room_settings(
    room_id: str,
    request: Request,
    device_id: str = Query(...),
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    room = await verify_room_ownership(room_id=room_id, device_id=device_id, db=db)

    body = await request.body()
    if len(body) > MAX_SETTINGS_BYTES:
        raise HTTPException(status_code=413, detail="Settings JSON exceeds 10KB limit")

    if not body:
        raise HTTPException(status_code=400, detail="Request body is empty")

    try:
        payload = json.loads(body.decode("utf-8"))
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=400, detail="Request body must be UTF-8") from exc
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {exc.msg}") from exc

    settings_obj = payload if payload is not None else None
    try:
        sanitized = validate_settings(settings_obj)
    except ValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    room.settings = json.dumps(sanitized) if sanitized is not None else None
    room.updated_at = utcnow()
    db.commit()
    return {"room_id": room_id, "settings": sanitized}


# ========== File Browser APIs ==========


@app.get("/rooms/{room_id}/files")
async def list_room_files(
    room_id: str,
    device_id: str = Query(...),
    path: str = Query(""),
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> List[dict]:
    room = await verify_room_ownership(room_id=room_id, device_id=device_id, db=db)
    try:
        return list_files(workspace_path=room.workspace_path, relative_path=path)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Directory not found")
    except (InvalidPath, InvalidExtension) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/rooms/{room_id}/files/{filepath:path}")
async def get_room_file(
    room_id: str,
    filepath: str,
    device_id: str = Query(...),
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> Response:
    room = await verify_room_ownership(room_id=room_id, device_id=device_id, db=db)
    try:
        content = read_file(workspace_path=room.workspace_path, file_path=filepath)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="File not found")
    except FileSizeExceeded as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    except (InvalidPath, InvalidExtension) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")

    return Response(content=content, media_type="text/plain; charset=utf-8")


@app.put("/rooms/{room_id}/files/{filepath:path}")
async def put_room_file(
    room_id: str,
    filepath: str,
    request: Request,
    device_id: str = Query(...),
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
) -> dict:
    room = await verify_room_ownership(room_id=room_id, device_id=device_id, db=db)

    try:
        body_bytes = await request.body()
        content = body_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=400, detail="Request body must be UTF-8") from exc

    try:
        result: WriteResult = write_file(
            workspace_path=room.workspace_path, file_path=filepath, content=content
        )
    except FileSizeExceeded as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    except (InvalidPath, InvalidExtension) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="File or directory not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")

    return {
        "message": "File saved",
        "path": filepath,
        "size": result.size,
        "backup_created": result.backup_created,
    }


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
        room_settings = json.loads(room.settings) if room.settings else None
    except json.JSONDecodeError:
        room_settings = None
    try:
        job = job_manager.create_job(
            runner=req.runner,
            input_text=req.input_text,
            device_id=req.device_id,
            room_id=req.room_id,
            workspace_path=room.workspace_path,
            settings=room_settings,
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
