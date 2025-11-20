from __future__ import annotations

import os
import sys
import shutil
import tempfile
from pathlib import Path

# Ensure project root is importable
sys.path.append(str(Path(__file__).resolve().parents[1]))

import pytest

from file_operations import list_files, read_file, write_file
from file_security import FileSizeExceeded, InvalidExtension

ALLOWED_BASE = "/Users/macstudio/Projects"


def make_workspace() -> Path:
    return Path(tempfile.mkdtemp(prefix="fileops-", dir=ALLOWED_BASE))


def cleanup(path: Path) -> None:
    shutil.rmtree(path, ignore_errors=True)


def test_list_files_filters_bak_and_non_md() -> None:
    workspace = make_workspace()
    try:
        (workspace / "Docs").mkdir()
        (workspace / "Docs" / "keep.md").write_text("ok")
        (workspace / "Docs" / "skip.txt").write_text("ng")
        (workspace / "Docs" / "keep.md.bak").write_text("bak")

        items = list_files(str(workspace), "Docs")
        assert len(items) == 1
        assert items[0]["name"] == "keep.md"
    finally:
        cleanup(workspace)


def test_list_files_empty_directory() -> None:
    workspace = make_workspace()
    try:
        (workspace / "Empty").mkdir()
        items = list_files(str(workspace), "Empty")
        assert items == []
    finally:
        cleanup(workspace)


def test_list_files_nested_structure() -> None:
    workspace = make_workspace()
    try:
        nested = workspace / "Docs" / "Specs"
        nested.mkdir(parents=True)
        (nested / "README.md").write_text("specs")
        items = list_files(str(workspace), "Docs")
        names = {item["name"] for item in items}
        assert "Specs" in names
    finally:
        cleanup(workspace)


def test_read_file_and_size_limit() -> None:
    workspace = make_workspace()
    file_path = workspace / "note.md"
    try:
        file_path.write_text("hello", encoding="utf-8")
        content = read_file(str(workspace), "note.md")
        assert content == "hello"

        # exceed limit
        file_path.write_bytes(b"a" * 500_001)
        with pytest.raises(FileSizeExceeded):
            read_file(str(workspace), "note.md")

        # invalid utf-8
        file_path.write_bytes(b"\xff\xfe\xfa")
        with pytest.raises(InvalidExtension):
            read_file(str(workspace), "note.md")
    finally:
        cleanup(workspace)


def test_write_file_creates_backup_and_respects_limit() -> None:
    workspace = make_workspace()
    file_path = workspace / "note.md"
    try:
        result = write_file(str(workspace), "note.md", "first")
        assert result.backup_created is False
        assert file_path.read_text() == "first"

        result2 = write_file(str(workspace), "note.md", "second")
        assert result2.backup_created is True
        assert file_path.read_text() == "second"
        assert (workspace / "note.md.bak").read_text() == "first"

        with pytest.raises(FileSizeExceeded):
            write_file(str(workspace), "note.md", "a" * 600_000)

        # permission inheritance
        mode = (workspace / "note.md").stat().st_mode
        result3 = write_file(str(workspace), "note.md", "third")
        assert (workspace / "note.md").stat().st_mode == mode
    finally:
        cleanup(workspace)
