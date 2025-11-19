"""Create a default room for testing."""
import uuid
from datetime import datetime, timezone

from database import SessionLocal
from models import Room


def utcnow():
    """Return current UTC time with timezone information."""
    return datetime.now(timezone.utc)


def create_default_room(device_id: str, name: str, workspace_path: str) -> str:
    """Create a room if it does not already exist."""
    db = SessionLocal()
    try:
        existing = db.query(Room).filter_by(device_id=device_id, name=name).first()
        if existing:
            print(f"✅ Room '{name}' already exists for device {device_id}")
            print(f"   Room ID: {existing.id}")
            print(f"   Workspace: {existing.workspace_path}")
            return existing.id

        room = Room(
            id=str(uuid.uuid4()),
            name=name,
            workspace_path=workspace_path,
            icon="folder",
            device_id=device_id,
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.add(room)
        db.commit()
        db.refresh(room)
        print(f"✅ Created default room '{name}' for device {device_id}")
        print(f"   Room ID: {room.id}")
        print(f"   Workspace: {room.workspace_path}")
        return room.id
    finally:
        db.close()


if __name__ == "__main__":
    DEVICE_ID = "iphone-test-1"
    ROOM_NAME = "RemotePrompt"
    WORKSPACE_PATH = "/Users/macstudio/Projects/RemotePrompt"

    room_id = create_default_room(DEVICE_ID, ROOM_NAME, WORKSPACE_PATH)
    print(f"\nℹ️  Use this room_id in API requests: {room_id}")
