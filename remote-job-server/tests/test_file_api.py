from __future__ import annotations

import os
import sys
import shutil
import tempfile
from pathlib import Path

# Ensure project root is importable
sys.path.append(str(Path(__file__).resolve().parents[1]))

import pytest
from fastapi.testclient import TestClient

# Use isolated test database
os.environ["DATABASE_URL"] = "sqlite:///./data/test_files_api.db"

import main  # pylint: disable=wrong-import-position
from database import Base, engine, init_db  # pylint: disable=wrong-import-position

ALLOWED_BASE = "/Users/macstudio/Projects"


@pytest.fixture(autouse=True)
def _reset_db():
    Base.metadata.drop_all(bind=engine)
    init_db()
    yield
    Base.metadata.drop_all(bind=engine)


def make_workspace() -> Path:
    return Path(tempfile.mkdtemp(prefix="fileapi-", dir=ALLOWED_BASE))


def cleanup(path: Path) -> None:
    shutil.rmtree(path, ignore_errors=True)


def create_room(client: TestClient, workspace: Path, device_id: str = "dev-1") -> str:
    res = client.post(
        "/rooms",
        json={"device_id": device_id, "name": "test", "workspace_path": str(workspace)},
        headers={"x-api-key": main.settings.api_key},
    )
    assert res.status_code == 200, res.text
    return res.json()["id"]


def test_file_endpoints_basic_flow():
    client = TestClient(main.app)
    workspace = make_workspace()
    try:
        room_id = create_room(client, workspace)

        # PUT create
        res = client.put(
            f"/rooms/{room_id}/files/note.md",
            params={"device_id": "dev-1"},
            headers={"x-api-key": main.settings.api_key},
            content="hello",
        )
        assert res.status_code == 200, res.text
        assert res.json()["backup_created"] is False

        # GET list
        res = client.get(
            f"/rooms/{room_id}/files",
            params={"device_id": "dev-1", "path": ""},
            headers={"x-api-key": main.settings.api_key},
        )
        assert res.status_code == 200, res.text
        assert any(item["name"] == "note.md" for item in res.json())

        # GET file
        res = client.get(
            f"/rooms/{room_id}/files/note.md",
            params={"device_id": "dev-1"},
            headers={"x-api-key": main.settings.api_key},
        )
        assert res.status_code == 200, res.text
        assert res.text == "hello"

        # 500KB limit
        big_content = "a" * 600_000
        res = client.put(
            f"/rooms/{room_id}/files/note.md",
            params={"device_id": "dev-1"},
            headers={"x-api-key": main.settings.api_key},
            content=big_content,
        )
        assert res.status_code == 413

        # traversal blocked
        res = client.get(
            f"/rooms/{room_id}/files/%2e%2e/%2e%2e/etc/passwd",
            params={"device_id": "dev-1"},
            headers={"x-api-key": main.settings.api_key},
        )
        assert res.status_code in (400, 404)
    finally:
        cleanup(workspace)


def test_forbidden_other_room_returns_403():
    client = TestClient(main.app)
    workspace = make_workspace()
    try:
        room_id = create_room(client, workspace, device_id="owner")
        res = client.get(
            f"/rooms/{room_id}/files",
            params={"device_id": "other"},
            headers={"x-api-key": main.settings.api_key},
        )
        assert res.status_code == 403
    finally:
        cleanup(workspace)


def test_nested_path_encoding():
    client = TestClient(main.app)
    workspace = make_workspace()
    try:
        room_id = create_room(client, workspace)
        nested = workspace / "Docs" / "Specs"
        nested.mkdir(parents=True)
        (nested / "README.md").write_text("nested", encoding="utf-8")

        encoded = "Docs%2FSpecs%2FREADME.md"
        res = client.get(
            f"/rooms/{room_id}/files/{encoded}",
            params={"device_id": "dev-1"},
            headers={"x-api-key": main.settings.api_key},
        )
        assert res.status_code == 200
        assert res.text == "nested"
    finally:
        cleanup(workspace)


def test_invalid_api_key_returns_401():
    client = TestClient(main.app)
    workspace = make_workspace()
    try:
        room_id = create_room(client, workspace)
        res = client.get(
            f"/rooms/{room_id}/files",
            params={"device_id": "dev-1"},
            headers={"x-api-key": "bad-key"},
        )
        assert res.status_code == 401
    finally:
        cleanup(workspace)
