"""Session management layer for Claude Code and Codex CLIs."""
from __future__ import annotations

import logging
import os
import re
import subprocess
import uuid
from pathlib import Path
from typing import Dict, Optional

from database import SessionLocal
from models import DeviceSession
from utils.cli_builder import build_claude_command, build_codex_command, build_gemini_command

LOGGER = logging.getLogger(__name__)
CODEx_SESSION_PATTERN = re.compile(r"session id:\s+([a-f0-9\-]{36})", re.IGNORECASE)
# Default to project root (parent of remote-job-server directory)
DEFAULT_TRUSTED_DIR = Path(os.getenv("CLAUDE_TRUSTED_DIR", Path(__file__).parent.parent)).resolve()


class ClaudeSessionManager:
    """Manage claude --print sessions with DB-backed persistence."""

    def __init__(self, trusted_directory: Path | str = DEFAULT_TRUSTED_DIR) -> None:
        self.trusted_directory = Path(trusted_directory)

    # --- DB helpers -----------------------------------------------------
    def _get_session_id_from_db(self, device_id: str, room_id: str, thread_id: str) -> Optional[str]:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, room_id=room_id, runner="claude", thread_id=thread_id)
                .first()
            )
            return record.session_id if record else None
        finally:
            db.close()

    def _save_session_id_to_db(self, device_id: str, room_id: str, thread_id: str, session_id: str) -> None:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, room_id=room_id, runner="claude", thread_id=thread_id)
                .first()
            )
            if record:
                record.session_id = session_id
            else:
                record = DeviceSession(
                    device_id=device_id,
                    room_id=room_id,
                    runner="claude",
                    thread_id=thread_id,
                    session_id=session_id,
                )
                db.add(record)
            db.commit()
        finally:
            db.close()

    def get_session_id(self, device_id: str, room_id: str, thread_id: str) -> Optional[str]:
        """Return the persisted session ID, if any."""
        return self._get_session_id_from_db(device_id, room_id, thread_id)

    # --- Execution ------------------------------------------------------
    def execute_job(
        self,
        prompt: str,
        device_id: str,
        room_id: str,
        workspace_path: Optional[str] = None,
        continue_session: bool = True,
        settings: Optional[dict] = None,
        thread_id: Optional[str] = None,
    ) -> Dict[str, Optional[str]]:
        if not thread_id:
            raise ValueError("thread_id is required for session management")
        cmd = build_claude_command(settings)
        session_id = None

        if continue_session:
            session_id = self._get_session_id_from_db(device_id, room_id, thread_id)

        if session_id:
            cmd.extend(["--resume", session_id])
            LOGGER.info(
                "Resuming Claude session %s for %s in room %s thread %s",
                session_id,
                device_id,
                room_id,
                thread_id,
            )
        else:
            session_id = str(uuid.uuid4())
            cmd.extend(["--session-id", session_id])
            LOGGER.info(
                "Starting new Claude session %s for %s in room %s thread %s",
                session_id,
                device_id,
                room_id,
                thread_id,
            )

        # Use workspace_path if provided, otherwise use default trusted_directory
        work_dir = Path(workspace_path) if workspace_path else self.trusted_directory

        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=1800,  # 30 minutes (extended from 5 min for long Codex jobs)
                cwd=work_dir,
            )
        except subprocess.TimeoutExpired:
            LOGGER.error("Claude session timed out for %s", device_id)
            return {"success": False, "output": "", "session_id": None, "error": "Timeout"}
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.exception("Claude execution failed: %s", exc)
            return {
                "success": False,
                "output": "",
                "session_id": None,
                "error": str(exc),
            }

        if result.returncode == 0:
            self._save_session_id_to_db(device_id, room_id, thread_id, session_id)

        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "session_id": session_id,
            "error": result.stderr,
        }


class CodexSessionManager:
    """Manage codex exec sessions with DB-backed persistence."""

    def _get_session_id_from_db(self, device_id: str, room_id: str, thread_id: str) -> Optional[str]:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, room_id=room_id, runner="codex", thread_id=thread_id)
                .first()
            )
            return record.session_id if record else None
        finally:
            db.close()

    def _save_session_id_to_db(self, device_id: str, room_id: str, thread_id: str, session_id: str) -> None:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, room_id=room_id, runner="codex", thread_id=thread_id)
                .first()
            )
            if record:
                record.session_id = session_id
            else:
                record = DeviceSession(
                    device_id=device_id,
                    room_id=room_id,
                    runner="codex",
                    thread_id=thread_id,
                    session_id=session_id,
                )
                db.add(record)
            db.commit()
        finally:
            db.close()

    def get_session_id(self, device_id: str, room_id: str, thread_id: str) -> Optional[str]:
        return self._get_session_id_from_db(device_id, room_id, thread_id)

    def execute_job(
        self,
        prompt: str,
        device_id: str,
        room_id: str,
        workspace_path: Optional[str] = None,
        continue_session: bool = True,
        settings: Optional[dict] = None,
        thread_id: Optional[str] = None,
    ) -> Dict[str, Optional[str]]:
        if not thread_id:
            raise ValueError("thread_id is required for session management")
        cmd = build_codex_command(settings)
        LOGGER.info("Codex command: %s (settings: %s)", cmd, settings)
        session_id = None

        if continue_session:
            session_id = self._get_session_id_from_db(device_id, room_id, thread_id)
            if session_id:
                cmd.extend(["resume", session_id])
                LOGGER.info(
                    "Resuming Codex session %s for %s in room %s thread %s",
                    session_id,
                    device_id,
                    room_id,
                    thread_id,
                )

        # Use workspace_path if provided (Codex doesn't use cwd in subprocess.run)
        # But we'll keep the parameter for consistency with ClaudeSessionManager
        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=1800,  # 30 minutes (extended from 5 min for long Codex jobs)
                cwd=Path(workspace_path) if workspace_path else None,
            )
        except subprocess.TimeoutExpired:
            LOGGER.error("Codex session timed out for %s", device_id)
            return {"success": False, "output": "", "session_id": None, "error": "Timeout"}
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.exception("Codex execution failed: %s", exc)
            return {"success": False, "output": "", "session_id": None, "error": str(exc)}

        extracted = None
        combined_output = f"{result.stdout}\n{result.stderr}" if result.stderr else result.stdout
        match = CODEx_SESSION_PATTERN.search(combined_output)
        if result.returncode == 0 and match:
            extracted = match.group(1)
            self._save_session_id_to_db(device_id, room_id, thread_id, extracted)

        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "session_id": extracted or session_id,
            "error": result.stderr,
        }


class GeminiSessionManager:
    """Manage Gemini CLI sessions with DB-backed persistence."""

    def _get_session_id_from_db(self, device_id: str, room_id: str, thread_id: str) -> Optional[str]:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, room_id=room_id, runner="gemini", thread_id=thread_id)
                .first()
            )
            return record.session_id if record else None
        finally:
            db.close()

    def _save_session_id_to_db(self, device_id: str, room_id: str, thread_id: str, session_id: str) -> None:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, room_id=room_id, runner="gemini", thread_id=thread_id)
                .first()
            )
            if record:
                record.session_id = session_id
            else:
                record = DeviceSession(
                    device_id=device_id,
                    room_id=room_id,
                    runner="gemini",
                    thread_id=thread_id,
                    session_id=session_id,
                )
                db.add(record)
            db.commit()
        finally:
            db.close()

    def get_session_id(self, device_id: str, room_id: str, thread_id: str) -> Optional[str]:
        return self._get_session_id_from_db(device_id, room_id, thread_id)

    def execute_job(
        self,
        prompt: str,
        device_id: str,
        room_id: str,
        workspace_path: Optional[str] = None,
        continue_session: bool = True,
        settings: Optional[dict] = None,
        thread_id: Optional[str] = None,
    ) -> Dict[str, Optional[str]]:
        if not thread_id:
            raise ValueError("thread_id is required for session management")

        cmd = build_gemini_command(settings)
        session_id = None

        if continue_session:
            session_id = self._get_session_id_from_db(device_id, room_id, thread_id)
            if session_id:
                cmd.extend(["--resume", session_id])
                LOGGER.info(
                    "Resuming Gemini session %s for %s in room %s thread %s",
                    session_id,
                    device_id,
                    room_id,
                    thread_id,
                )
            else:
                LOGGER.info(
                    "Starting new Gemini session for %s in room %s thread %s",
                    device_id,
                    room_id,
                    thread_id,
                )

        # Append the prompt as positional argument
        cmd.append(prompt)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=1800,  # 30 minutes
                cwd=Path(workspace_path) if workspace_path else None,
            )
        except subprocess.TimeoutExpired:
            LOGGER.error("Gemini session timed out for %s", device_id)
            return {"success": False, "output": "", "session_id": None, "error": "Timeout"}
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.exception("Gemini execution failed: %s", exc)
            return {"success": False, "output": "", "session_id": None, "error": str(exc)}

        # Gemini doesn't return session ID in output like Codex
        # For now, generate a UUID if successful and no existing session
        if result.returncode == 0 and not session_id:
            session_id = str(uuid.uuid4())
            self._save_session_id_to_db(device_id, room_id, thread_id, session_id)

        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "session_id": session_id,
            "error": result.stderr,
        }


class SessionManager:
    """Facade that delegates to Claude, Codex, or Gemini session managers."""

    def __init__(self) -> None:
        self.claude_manager = ClaudeSessionManager()
        self.codex_manager = CodexSessionManager()
        self.gemini_manager = GeminiSessionManager()

    def execute_job(
        self,
        runner: str,
        prompt: str,
        device_id: str,
        room_id: str,
        workspace_path: Optional[str] = None,
        continue_session: bool = True,
        settings: Optional[dict] = None,
        thread_id: Optional[str] = None,
    ) -> Dict[str, Optional[str]]:
        if runner == "claude":
            return self.claude_manager.execute_job(
                prompt, device_id, room_id, workspace_path, continue_session, settings, thread_id
            )
        if runner == "codex":
            return self.codex_manager.execute_job(
                prompt, device_id, room_id, workspace_path, continue_session, settings, thread_id
            )
        if runner == "gemini":
            return self.gemini_manager.execute_job(
                prompt, device_id, room_id, workspace_path, continue_session, settings, thread_id
            )
        raise ValueError(f"Unknown runner: {runner}")

    def get_session_status(self, runner: str, device_id: str, room_id: str, thread_id: str) -> Dict[str, Optional[str]]:
        if runner == "claude":
            session_id = self.claude_manager.get_session_id(device_id, room_id, thread_id)
        elif runner == "codex":
            session_id = self.codex_manager.get_session_id(device_id, room_id, thread_id)
        elif runner == "gemini":
            session_id = self.gemini_manager.get_session_id(device_id, room_id, thread_id)
        else:
            raise ValueError(f"Unknown runner: {runner}")

        return {"exists": session_id is not None, "session_id": session_id}
