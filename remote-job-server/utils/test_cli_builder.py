"""CLI builder tests for Claude and Codex commands."""
from __future__ import annotations

from utils.cli_builder import build_claude_command, build_codex_command


def test_codex_reasoning_effort():
    settings = {"codex": {"reasoning_effort": "high"}}
    cmd = build_codex_command(settings)
    assert cmd == ["codex", "exec", "-r", "high"]


def test_codex_combined():
    settings = {
        "codex": {
            "model": "gpt-5.1-codex-max",
            "sandbox": "workspace-write",
            "approval_policy": "on-failure",
            "reasoning_effort": "extra-high",
        }
    }
    cmd = build_codex_command(settings)
    assert cmd == [
        "codex",
        "exec",
        "-m",
        "gpt-5.1-codex-max",
        "-s",
        "workspace-write",
        "-a",
        "on-failure",
        "-r",
        "extra-high",
    ]


def test_claude_with_options():
    settings = {"claude": {"model": "opus", "permission_mode": "ask", "tools": ["Bash", "Edit"]}}
    cmd = build_claude_command(settings)
    assert cmd == [
        "claude",
        "--print",
        "--output-format",
        "text",
        "--model",
        "opus",
        "--permission-mode",
        "ask",
        "--tools",
        "Bash,Edit",
    ]
