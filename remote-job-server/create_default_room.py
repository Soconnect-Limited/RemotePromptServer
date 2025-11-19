"""Create a default room for testing."""
import uuid
from datetime import datetime, timezone

from database import SessionLocal
from models import Room


def utcnow():
    """Return current UTC time with timezone information."""
    return datetime.now(timezone.utc)


def create_default_room(device_id: str, name: str, workspace_path: str, room_id: str = None) -> str:
    """Create a room if it does not already exist."""
    db = SessionLocal()
    try:
        # Check by room_id first if provided
        if room_id:
            existing = db.query(Room).filter_by(id=room_id).first()
            if existing:
                print(f"✅ Room '{name}' (ID: {room_id}) already exists")
                print(f"   Device: {existing.device_id}")
                print(f"   Workspace: {existing.workspace_path}")
                return existing.id
        else:
            # Check by device_id and name
            existing = db.query(Room).filter_by(device_id=device_id, name=name).first()
            if existing:
                print(f"✅ Room '{name}' already exists for device {device_id}")
                print(f"   Room ID: {existing.id}")
                print(f"   Workspace: {existing.workspace_path}")
                return existing.id

        room = Room(
            id=room_id or str(uuid.uuid4()),
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
        print(f"✅ Created default room '{name}' (ID: {room.id}) for device {device_id}")
        print(f"   Workspace: {room.workspace_path}")
        return room.id
    finally:
        db.close()


if __name__ == "__main__":
    # Create default room with fixed ID for iOS app compatibility
    DEFAULT_ROOM_ID = "default-room"
    DEFAULT_DEVICE_ID = "any-device"  # This room can be used by any device
    ROOM_NAME = "Default Room"
    WORKSPACE_PATH = "/Users/macstudio/Projects/RemotePrompt"

    print("Creating default room for iOS app...")
    room_id = create_default_room(
        device_id=DEFAULT_DEVICE_ID,
        name=ROOM_NAME,
        workspace_path=WORKSPACE_PATH,
        room_id=DEFAULT_ROOM_ID
    )
    print(f"\nℹ️  iOS app will use room_id: {room_id}")
