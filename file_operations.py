"""Filesystem operations for listing, reading, and writing markdown files."""
from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

from file_security import (
    ALLOWED_IMAGE_EXTENSIONS,
    MAX_FILE_SIZE,
    FileSizeExceeded,
    InvalidExtension,
    InvalidPath,
    validate_file_path,
    validate_file_size,
    validate_image_extension,
    validate_markdown_extension,
    validate_pdf_extension,
)

# PDFファイルのサイズ上限（10MB）
MAX_PDF_SIZE = 10_000_000

# 画像ファイルのサイズ上限（100MB）
MAX_IMAGE_SIZE = 100_000_000

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
            path = entry.relative_to(base).as_posix()
            results.append(
                {
                    "id": path,
                    "name": entry.name,
                    "type": "directory",
                    "path": path,
                    "size": None,
                    "modified_at": datetime.fromtimestamp(
                        entry.stat().st_mtime, timezone.utc
                    ).isoformat(),
                }
            )
        elif entry.is_file():
            suffix = entry.suffix.lower()
            if suffix == ".md":
                file_type = "markdown_file"
            elif suffix == ".pdf":
                file_type = "pdf_file"
            elif suffix in ALLOWED_IMAGE_EXTENSIONS:
                file_type = "image_file"
            else:
                continue  # 未対応の拡張子はスキップ

            stat = entry.stat()
            path = entry.relative_to(base).as_posix()
            results.append(
                {
                    "id": path,
                    "name": entry.name,
                    "type": file_type,
                    "path": path,
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


def read_pdf_file(workspace_path: str, file_path: str) -> bytes:
    """Read a PDF file as binary data."""
    target = validate_file_path(workspace_path, file_path)
    if not target.exists() or not target.is_file():
        raise FileNotFoundError("File not found")
    validate_pdf_extension(target)
    validate_file_size(target, max_size=MAX_PDF_SIZE)
    return target.read_bytes()


def read_image_file(workspace_path: str, file_path: str) -> bytes:
    """Read an image file as binary data."""
    target = validate_file_path(workspace_path, file_path)
    if not target.exists() or not target.is_file():
        raise FileNotFoundError("File not found")
    validate_image_extension(target)
    validate_file_size(target, max_size=MAX_IMAGE_SIZE)
    return target.read_bytes()


def _generate_unique_filename(target: Path) -> Path:
    """Generate a unique filename by appending _1, _2, etc. if file exists."""
    if not target.exists():
        return target

    stem = target.stem
    suffix = target.suffix
    parent = target.parent
    counter = 1

    while True:
        new_name = f"{stem}_{counter}{suffix}"
        new_path = parent / new_name
        if not new_path.exists():
            return new_path
        counter += 1


@dataclass
class ImageWriteResult:
    success: bool
    size: int
    saved_path: str  # 実際に保存されたパス（重複時は変更される）


def write_image_file(
    workspace_path: str, directory_path: str, filename: str, data: bytes
) -> ImageWriteResult:
    """Write an image file to the specified directory.

    If a file with the same name exists, appends _1, _2, etc. to the filename.
    """
    # ディレクトリパスを検証
    target_dir = validate_file_path(workspace_path, directory_path)
    if not target_dir.exists():
        target_dir.mkdir(parents=True, exist_ok=True)
    if not target_dir.is_dir():
        raise FileNotFoundError("Target path is not a directory")

    # ファイルパスを構築
    target = target_dir / filename
    validate_image_extension(target)

    # サイズチェック
    if len(data) > MAX_IMAGE_SIZE:
        raise FileSizeExceeded(size=len(data), limit=MAX_IMAGE_SIZE)

    # 重複ファイル名の処理
    target = _generate_unique_filename(target)

    # 書き込み
    target.write_bytes(data)

    # 保存されたパスを相対パスで返す
    base = Path(workspace_path).resolve()
    saved_relative_path = target.relative_to(base).as_posix()

    return ImageWriteResult(success=True, size=len(data), saved_path=saved_relative_path)
