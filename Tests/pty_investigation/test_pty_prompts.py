#!/usr/bin/env python3
"""
PTY経由でClaude CodeとCodexのプロンプト記号を確認するテストスクリプト
"""

import pty
import os
import select
import time
import re
import sys

def test_cli_prompt(cli_command, timeout=30):
    """
    CLIをPTY経由で起動し、プロンプト記号を検出する

    Args:
        cli_command: ["claude"] or ["codex"]
        timeout: タイムアウト秒数

    Returns:
        dict: {
            'success': bool,
            'prompt_char': str,
            'output': str
        }
    """
    print(f"\n{'='*60}")
    print(f"Testing: {cli_command[0]}")
    print(f"{'='*60}")

    master_fd, slave_fd = pty.openpty()
    pid = os.fork()

    if pid == 0:  # 子プロセス
        os.close(master_fd)

        # stdin, stdout, stderr を slave に接続
        os.dup2(slave_fd, 0)
        os.dup2(slave_fd, 1)
        os.dup2(slave_fd, 2)

        # 環境変数を設定
        env = os.environ.copy()
        env['TERM'] = 'dumb'
        env['NO_COLOR'] = '1'

        # CLIを実行
        os.execvpe(cli_command[0], cli_command, env)
    else:  # 親プロセス
        os.close(slave_fd)

        start_time = time.time()
        buffer = ""
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

        print("\n--- Raw output: ---")

        while time.time() - start_time < timeout:
            ready, _, _ = select.select([master_fd], [], [], 0.5)
            if ready:
                try:
                    chunk = os.read(master_fd, 4096).decode('utf-8', errors='ignore')
                    buffer += chunk

                    # リアルタイム表示
                    print(chunk, end='', flush=True)

                    # プロンプト記号を検出
                    # Claude Code: "› " (U+203A)
                    # Codex: "> "
                    # 他の可能性: "$ ", "➜ ", "❯ "

                    # 最後の行を取得
                    lines = buffer.split('\n')
                    last_line = lines[-1] if lines else ""

                    # プロンプト記号の候補
                    prompt_chars = ['›', '>', '$', '➜', '❯', '%']

                    for char in prompt_chars:
                        if char in last_line:
                            # プロンプト検出成功
                            os.close(master_fd)
                            os.kill(pid, 9)
                            os.waitpid(pid, 0)

                            cleaned = ansi_escape.sub('', buffer)

                            print("\n\n--- Analysis: ---")
                            print(f"✅ Prompt character detected: '{char}'")
                            print(f"Last line: {repr(last_line)}")
                            print(f"Buffer length: {len(buffer)} chars")

                            return {
                                'success': True,
                                'prompt_char': char,
                                'last_line': last_line,
                                'output': cleaned
                            }

                except OSError:
                    break

        # タイムアウト
        os.close(master_fd)
        os.kill(pid, 9)
        os.waitpid(pid, 0)

        print("\n\n--- Analysis: ---")
        print("❌ Timeout: No prompt character detected")

        return {
            'success': False,
            'prompt_char': None,
            'output': buffer
        }

if __name__ == "__main__":
    # Claude Codeをテスト
    claude_result = test_cli_prompt(['claude'])

    print("\n" + "="*60)
    time.sleep(2)

    # Codexをテスト
    codex_result = test_cli_prompt(['codex'])

    # 結果サマリー
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    print(f"Claude Code: {'✅ ' + claude_result['prompt_char'] if claude_result['success'] else '❌ Failed'}")
    print(f"Codex:       {'✅ ' + codex_result['prompt_char'] if codex_result['success'] else '❌ Failed'}")
    print("="*60)
