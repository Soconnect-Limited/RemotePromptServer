"""Filesystem operations for listing, reading, and writing markdown files."""
from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

from file_security import (
    MAX_FILE_SIZE,
    FileSizeExceeded,
    InvalidExtension,
    InvalidPath,
    validate_file_path,
    validate_file_size,
    validate_markdown_extension,
)

FileItemDict = Dict[str, object]


@dataclass
class WriteResult:
    success: bool
    size: int
    backup_created: bool


def list_files(workspace_path: str, relative_path: str) -> List[FileItemDict]:
    target_dir = validate_file_path(workspace_path, relative_path)
    if not target_dir.exists():
        raise FileNotFoundError("Directory not found")
    if not target_dir.is_dir():
        raise FileNotFoundError("Path is not a directory")

    results: List[FileItemDict] = []
    base = Path(workspace_path).resolve()

    for entry in sorted(target_dir.iterdir(), key=lambda p: p.name.lower()):
        if entry.name.endswith(".bak"):
            continue
        if entry.is_dir():
            results.append(
                {
                    "name": entry.name,
                    "type": "directory",
                    "path": entry.relative_to(base).as_posix(),
                    "size": None,
                    "modified_at": datetime.fromtimestamp(
                        entry.stat().st_mtime, timezone.utc
                    ).isoformat(),
                }
            )
        elif entry.is_file() and entry.suffix.lower() == ".md":
            stat = entry.stat()
            results.append(
                {
                    "name": entry.name,
                    "type": "markdown_file",
                    "path": entry.relative_to(base).as_posix(),
                    "size": stat.st_size,
                    "modified_at": datetime.fromtimestamp(
                        stat.st_mtime, timezone.utc
                    ).isoformat(),
                }
            )
    return results


def read_file(workspace_path: str, file_path: str) -> str:
    target = validate_file_path(workspace_path, file_path)
    if not target.exists() or not target.is_file():
        raise FileNotFoundError("File not found")
    validate_markdown_extension(target)
    validate_file_size(target, max_size=MAX_FILE_SIZE)
    try:
        return target.read_text(encoding="utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise InvalidExtension("File is not valid UTF-8 text") from exc


def write_file(workspace_path: str, file_path: str, content: str) -> WriteResult:
    target = validate_file_path(workspace_path, file_path)
    validate_markdown_extension(target)

    encoded_size = len(content.encode("utf-8"))
    if encoded_size > MAX_FILE_SIZE:
        raise FileSizeExceeded(size=encoded_size, limit=MAX_FILE_SIZE)

    target.parent.mkdir(parents=True, exist_ok=True)

    backup_created = False
    orig_mode = None
    backup_path = target.with_suffix(target.suffix + ".bak")

    if target.exists():
        stat = target.stat()
        orig_mode = stat.st_mode
        if backup_path.exists():
            backup_path.unlink()
        target.rename(backup_path)
        backup_created = True

    with open(target, "w", encoding="utf-8", errors="strict") as f:
        f.write(content)

    if orig_mode is not None:
        os.chmod(target, orig_mode)

    return WriteResult(success=True, size=encoded_size, backup_created=backup_created)
