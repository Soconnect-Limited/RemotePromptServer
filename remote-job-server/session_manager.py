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

LOGGER = logging.getLogger(__name__)
CODEx_SESSION_PATTERN = re.compile(r"session id:\s+([a-f0-9\-]{36})", re.IGNORECASE)
DEFAULT_TRUSTED_DIR = Path(os.getenv("CLAUDE_TRUSTED_DIR", ".")).resolve()


class ClaudeSessionManager:
    """Manage claude --print sessions with DB-backed persistence."""

    def __init__(self, trusted_directory: Path | str = DEFAULT_TRUSTED_DIR) -> None:
        self.trusted_directory = Path(trusted_directory)

    # --- DB helpers -----------------------------------------------------
    def _get_session_id_from_db(self, device_id: str) -> Optional[str]:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, runner="claude")
                .first()
            )
            return record.session_id if record else None
        finally:
            db.close()

    def _save_session_id_to_db(self, device_id: str, session_id: str) -> None:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, runner="claude")
                .first()
            )
            if record:
                record.session_id = session_id
            else:
                record = DeviceSession(
                    device_id=device_id,
                    runner="claude",
                    session_id=session_id,
                )
                db.add(record)
            db.commit()
        finally:
            db.close()

    def get_session_id(self, device_id: str) -> Optional[str]:
        """Return the persisted session ID, if any."""
        return self._get_session_id_from_db(device_id)

    # --- Execution ------------------------------------------------------
    def execute_job(
        self,
        prompt: str,
        device_id: str,
        continue_session: bool = True,
    ) -> Dict[str, Optional[str]]:
        cmd = ["claude", "--print", "--output-format", "text"]
        session_id = None

        if continue_session:
            session_id = self._get_session_id_from_db(device_id)

        if session_id:
            cmd.extend(["--resume", session_id])
            LOGGER.info("Resuming Claude session %s for %s", session_id, device_id)
        else:
            session_id = str(uuid.uuid4())
            cmd.extend(["--session-id", session_id])
            LOGGER.info("Starting new Claude session %s for %s", session_id, device_id)

        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=300,
                cwd=self.trusted_directory,
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
            self._save_session_id_to_db(device_id, session_id)

        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "session_id": session_id,
            "error": result.stderr,
        }


class CodexSessionManager:
    """Manage codex exec sessions with DB-backed persistence."""

    def _get_session_id_from_db(self, device_id: str) -> Optional[str]:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, runner="codex")
                .first()
            )
            return record.session_id if record else None
        finally:
            db.close()

    def _save_session_id_to_db(self, device_id: str, session_id: str) -> None:
        db = SessionLocal()
        try:
            record = (
                db.query(DeviceSession)
                .filter_by(device_id=device_id, runner="codex")
                .first()
            )
            if record:
                record.session_id = session_id
            else:
                record = DeviceSession(
                    device_id=device_id,
                    runner="codex",
                    session_id=session_id,
                )
                db.add(record)
            db.commit()
        finally:
            db.close()

    def get_session_id(self, device_id: str) -> Optional[str]:
        return self._get_session_id_from_db(device_id)

    def execute_job(
        self,
        prompt: str,
        device_id: str,
        continue_session: bool = True,
    ) -> Dict[str, Optional[str]]:
        cmd = ["codex", "exec"]
        session_id = None

        if continue_session:
            session_id = self._get_session_id_from_db(device_id)
            if session_id:
                cmd.extend(["resume", session_id])
                LOGGER.info("Resuming Codex session %s for %s", session_id, device_id)

        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=300,
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
            self._save_session_id_to_db(device_id, extracted)

        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "session_id": extracted or session_id,
            "error": result.stderr,
        }


class SessionManager:
    """Facade that delegates to Claude or Codex session managers."""

    def __init__(self) -> None:
        self.claude_manager = ClaudeSessionManager()
        self.codex_manager = CodexSessionManager()

    def execute_job(
        self,
        runner: str,
        prompt: str,
        device_id: str,
        continue_session: bool = True,
    ) -> Dict[str, Optional[str]]:
        if runner == "claude":
            return self.claude_manager.execute_job(prompt, device_id, continue_session)
        if runner == "codex":
            return self.codex_manager.execute_job(prompt, device_id, continue_session)
        raise ValueError(f"Unknown runner: {runner}")

    def get_session_status(self, runner: str, device_id: str) -> Dict[str, Optional[str]]:
        if runner == "claude":
            session_id = self.claude_manager.get_session_id(device_id)
        elif runner == "codex":
            session_id = self.codex_manager.get_session_id(device_id)
        else:
            raise ValueError(f"Unknown runner: {runner}")

        return {"exists": session_id is not None, "session_id": session_id}
