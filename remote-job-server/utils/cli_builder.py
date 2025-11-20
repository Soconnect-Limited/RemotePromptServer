"""Build CLI command lists for Claude Code and Codex."""
from __future__ import annotations

from typing import Dict, List, Optional


def build_claude_command(settings: Optional[Dict] = None) -> List[str]:
    cmd: List[str] = ["claude", "--print", "--output-format", "text"]

    if settings and "claude" in settings:
        cfg = settings["claude"]
        if "model" in cfg:
            cmd.extend(["--model", cfg["model"]])
        if "permission_mode" in cfg:
            cmd.extend(["--permission-mode", cfg["permission_mode"]])
        if "tools" in cfg:
            tools = ",".join(cfg["tools"])
            cmd.extend(["--tools", tools])
        if "custom_flags" in cfg:
            cmd.extend(cfg["custom_flags"])

    return cmd


def build_codex_command(settings: Optional[Dict] = None) -> List[str]:
    cmd: List[str] = ["codex", "exec"]

    if settings and "codex" in settings:
        cfg = settings["codex"]
        if "model" in cfg:
            cmd.extend(["-m", cfg["model"]])
        if "sandbox" in cfg:
            cmd.extend(["-s", cfg["sandbox"]])
        if "approval_policy" in cfg:
            cmd.extend(["-a", cfg["approval_policy"]])
        if "reasoning_effort" in cfg:
            cmd.extend(["-r", cfg["reasoning_effort"]])
        if "custom_flags" in cfg:
            cmd.extend(cfg["custom_flags"])

    return cmd
