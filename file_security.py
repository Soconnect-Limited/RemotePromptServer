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

# ソースコード拡張子 (Phase 1: 優先実装)
PHASE1_SOURCE_EXTENSIONS = {
    ".swift", ".py", ".js", ".jsx", ".ts", ".tsx",
    ".json", ".yaml", ".yml", ".sh", ".bash", ".zsh",
    ".html", ".htm", ".css", ".scss", ".less"
}

# ソースコード拡張子 (Phase 2: 追加対応)
PHASE2_SOURCE_EXTENSIONS = {
    ".go", ".rs", ".rb", ".java", ".kt", ".kts",
    ".c", ".cpp", ".h", ".hpp", ".cc", ".cxx",
    ".cs", ".sql", ".csv", ".tsv", ".toml", ".xml", ".plist", ".mk"
}

# 拡張子なしファイル名パターン (Phase 2)
PHASE2_SOURCE_FILENAMES = {
    "dockerfile", "makefile", "gnumakefile"
}

# 全対応ソースコード拡張子
ALLOWED_SOURCE_EXTENSIONS = PHASE1_SOURCE_EXTENSIONS | PHASE2_SOURCE_EXTENSIONS

# ソースファイルのサイズ上限（1MB）
MAX_SOURCE_SIZE = 1_000_000


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


def validate_source_extension(file_path: Path) -> None:
    """Ensure the path points to an allowed source code file.
    
    Checks both extension-based and filename-based patterns.
    """
    suffix = file_path.suffix.lower()
    filename = file_path.name.lower()
    
    # 拡張子ベースのチェック
    if suffix in ALLOWED_SOURCE_EXTENSIONS:
        return
    
    # ファイル名ベースのチェック（Dockerfile, Makefile等）
    if filename in PHASE2_SOURCE_FILENAMES:
        return
    
    # Dockerfile.* パターン
    if filename.startswith("dockerfile"):
        return
    
    raise InvalidExtension(
        f"Unsupported source file type: {file_path.name}"
    )


def is_source_file(file_path: Path) -> bool:
    """Check if the path is a source code file."""
    suffix = file_path.suffix.lower()
    filename = file_path.name.lower()
    
    if suffix in ALLOWED_SOURCE_EXTENSIONS:
        return True
    if filename in PHASE2_SOURCE_FILENAMES:
        return True
    if filename.startswith("dockerfile"):
        return True
    
    return False


def get_source_language(file_path: Path) -> str | None:
    """Get the programming language for a source file.
    
    Returns the language identifier or None if not a source file.
    """
    suffix = file_path.suffix.lower()
    filename = file_path.name.lower()
    
    # 拡張子から言語を推定
    extension_to_language = {
        ".swift": "swift",
        ".py": "python",
        ".js": "javascript",
        ".jsx": "javascript",
        ".ts": "typescript",
        ".tsx": "typescript",
        ".json": "json",
        ".yaml": "yaml",
        ".yml": "yaml",
        ".sh": "shell",
        ".bash": "shell",
        ".zsh": "shell",
        ".html": "html",
        ".htm": "html",
        ".css": "css",
        ".scss": "scss",
        ".less": "less",
        ".go": "go",
        ".rs": "rust",
        ".rb": "ruby",
        ".java": "java",
        ".kt": "kotlin",
        ".kts": "kotlin",
        ".c": "c",
        ".h": "c",
        ".cpp": "cpp",
        ".hpp": "cpp",
        ".cc": "cpp",
        ".cxx": "cpp",
        ".cs": "csharp",
        ".sql": "sql",
        ".csv": "csv",
        ".tsv": "tsv",
        ".toml": "toml",
        ".xml": "xml",
        ".plist": "xml",
        ".mk": "makefile",
    }
    
    if suffix in extension_to_language:
        return extension_to_language[suffix]
    
    # ファイル名ベースのチェック
    if filename in PHASE2_SOURCE_FILENAMES or filename.startswith("dockerfile"):
        if "dockerfile" in filename:
            return "dockerfile"
        if "makefile" in filename or filename == "gnumakefile":
            return "makefile"
    
    return None
