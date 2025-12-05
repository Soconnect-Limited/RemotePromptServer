"""Utility script to initialize the Remote Job Server database."""
from database import SessionLocal, init_db
from models import Device, utcnow


def create_initial_device(device_id: str = "test-device-1", token: str = "dummy-token") -> None:
    db = SessionLocal()
    try:
        device = Device(
            device_id=device_id,
            device_token=token,
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.add(device)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    init_db()
    create_initial_device()
    print("Database initialized.")
