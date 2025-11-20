from __future__ import annotations

import os
import sys
import tempfile
import shutil
from pathlib import Path

# Ensure project root is importable
sys.path.append(str(Path(__file__).resolve().parents[1]))

import pytest

from file_security import (
    MAX_FILE_SIZE,
    FileSizeExceeded,
    InvalidExtension,
    InvalidPath,
    validate_file_path,
    validate_file_size,
    validate_markdown_extension,
)


ALLOWED_BASE = "/Users/macstudio/Projects"


def make_workspace() -> str:
    return tempfile.mkdtemp(prefix="filesec-", dir=ALLOWED_BASE)


def cleanup(path: str) -> None:
    shutil.rmtree(path, ignore_errors=True)


def test_validate_file_path_rejects_traversal() -> None:
    workspace = make_workspace()
    try:
        with pytest.raises(InvalidPath):
            validate_file_path(workspace, "../etc/passwd")
        with pytest.raises(InvalidPath):
            validate_file_path(workspace, "%2e%2e/%2e%2e/secret")
    finally:
        cleanup(workspace)


def test_validate_markdown_extension() -> None:
    workspace = make_workspace()
    path = os.path.join(workspace, "note.txt")
    try:
        with pytest.raises(InvalidExtension):
            validate_markdown_extension(Path(path))
    finally:
        cleanup(workspace)


def test_validate_file_size_exceeded() -> None:
    workspace = make_workspace()
    file_path = os.path.join(workspace, "big.md")
    try:
        with open(file_path, "wb") as f:
            f.write(b"a" * (MAX_FILE_SIZE + 1))
        with pytest.raises(FileSizeExceeded):
            validate_file_size(Path(file_path))
    finally:
        cleanup(workspace)
