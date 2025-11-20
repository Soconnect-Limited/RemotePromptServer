"""Authorization helpers for room-based access control."""
from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy.orm import Session

from models import Room


async def verify_room_ownership(room_id: str, device_id: str, db: Session) -> Room:
    """Return the room if it exists and belongs to the device.

    Raises:
        HTTPException 404: room not found
        HTTPException 403: room owned by another device
    """

    room = db.query(Room).filter_by(id=room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    if room.device_id != device_id:
        raise HTTPException(status_code=403, detail="Room not owned by device")
    return room
