"""File path and size validation helpers for file APIs."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote

MAX_FILE_SIZE = 500_000  # 500KB


class FileSecurityError(Exception):
    """Base exception for file security errors."""


class InvalidPath(FileSecurityError):
    """Raised when the requested path is outside the workspace."""


class InvalidExtension(FileSecurityError):
    """Raised when the file extension is not allowed."""


@dataclass
class FileSizeExceeded(FileSecurityError):
    """Raised when a file exceeds the configured size limit."""

    size: int
    limit: int = MAX_FILE_SIZE

    def __str__(self) -> str:  # pragma: no cover - trivial
        return f"File exceeds {self.limit} bytes (got {self.size})"


def validate_file_path(workspace_path: str, relative_path: str) -> Path:
    """Validate and resolve a relative path within a workspace.

    - Double URL-decodes to mitigate double-encoded traversal sequences.
    - Normalises Windows separators to POSIX.
    - Resolves symlinks and ensures the target stays under the workspace root.
    """

    decoded = unquote(unquote(relative_path))
    normalized = decoded.replace("\\", "/")

    base = Path(workspace_path).resolve()
    target = (base / normalized).resolve()

    try:
        target.relative_to(base)
    except ValueError as exc:  # outside workspace
        raise InvalidPath(f"Path traversal detected: {relative_path}") from exc

    return target


def validate_markdown_extension(file_path: Path) -> None:
    """Ensure the path points to a .md file."""

    if file_path.suffix.lower() != ".md":
        raise InvalidExtension("Only .md files are allowed")


def validate_pdf_extension(file_path: Path) -> None:
    """Ensure the path points to a .pdf file."""

    if file_path.suffix.lower() != ".pdf":
        raise InvalidExtension("Only .pdf files are allowed")


# 許可する画像拡張子
ALLOWED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".heic"}


def validate_image_extension(file_path: Path) -> None:
    """Ensure the path points to an allowed image file."""

    if file_path.suffix.lower() not in ALLOWED_IMAGE_EXTENSIONS:
        raise InvalidExtension(
            f"Only image files are allowed: {', '.join(ALLOWED_IMAGE_EXTENSIONS)}"
        )


def validate_file_size(file_path: Path, max_size: int = MAX_FILE_SIZE) -> int:
    """Validate file size is within limit.

    Returns the size in bytes if valid, otherwise raises FileSizeExceeded.
    """

    size = file_path.stat().st_size
    if size > max_size:
        raise FileSizeExceeded(size=size, limit=max_size)
    return size
