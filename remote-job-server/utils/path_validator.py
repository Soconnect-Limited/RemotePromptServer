"""Workspace path validation for security."""
from pathlib import Path
from typing import List

ALLOWED_BASE_PATHS: List[str] = [
    "/Users/macstudio/Projects",
    "/Users/macstudio/Documents",
    "/Users/macstudio/Library/Mobile Documents",  # iCloud Drive
]

FORBIDDEN_PATHS: List[str] = [
    "/System",
    "/Library",
    "/private",
    "/etc",
    "/usr",
    "/bin",
    "/sbin",
    "/var",
]


def is_safe_workspace_path(path: str) -> bool:
    """
    Check if a workspace path is safe (within allowed directories and not in forbidden ones).

    Args:
        path: The path to validate

    Returns:
        True if the path is safe, False otherwise
    """
    try:
        abs_path = Path(path).resolve()
        abs_path_str = str(abs_path)

        # Check forbidden paths first
        for forbidden in FORBIDDEN_PATHS:
            if abs_path_str.startswith(forbidden):
                return False

        # Check if path is within allowed base paths
        for allowed in ALLOWED_BASE_PATHS:
            if abs_path_str.startswith(allowed):
                return True

        return False
    except (ValueError, OSError):
        return False


def validate_workspace_path(path: str) -> str:
    """
    Validate and resolve a workspace path.

    Args:
        path: The path to validate

    Returns:
        The resolved absolute path

    Raises:
        ValueError: If the path is not allowed
    """
    if not is_safe_workspace_path(path):
        raise ValueError(f"Workspace path is not allowed: {path}")
    return str(Path(path).resolve())
