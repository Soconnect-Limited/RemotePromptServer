#!/usr/bin/env python3
"""
PTY経由でClaude Codeと対話し、信頼確認を通過してプロンプト記号を確認
"""

import pty
import os
import select
import time
import re
import sys

def test_claude_with_trust(timeout=60):
    """
    Claude Codeを起動し、信頼確認に自動応答してプロンプトを確認
    """
    print(f"\n{'='*60}")
    print(f"Testing: Claude Code (with trust confirmation)")
    print(f"{'='*60}")

    master_fd, slave_fd = pty.openpty()
    pid = os.fork()

    if pid == 0:  # 子プロセス
        os.close(master_fd)

        os.dup2(slave_fd, 0)
        os.dup2(slave_fd, 1)
        os.dup2(slave_fd, 2)

        env = os.environ.copy()
        env['TERM'] = 'xterm-256color'  # dumbだとメニューが出ない可能性

        os.execvpe('claude', ['claude'], env)
    else:  # 親プロセス
        os.close(slave_fd)

        start_time = time.time()
        buffer = ""
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        trust_sent = False
        message_sent = False

        print("\n--- Interactive session: ---\n")

        while time.time() - start_time < timeout:
            ready, _, _ = select.select([master_fd], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(master_fd, 4096).decode('utf-8', errors='ignore')
                    buffer += chunk
                    print(chunk, end='', flush=True)

                    # 信頼確認ダイアログを検出
                    if "Do you trust the files" in buffer and not trust_sent:
                        print("\n\n[AUTO] Sending Enter to confirm trust...\n")
                        time.sleep(1)
                        os.write(master_fd, b'\r')  # Enter押下
                        trust_sent = True

                    # プロンプトが表示されたらメッセージを送信
                    if trust_sent and not message_sent:
                        # プロンプト記号を探す
                        lines = buffer.split('\n')
                        last_line = lines[-1] if lines else ""

                        # Claude Codeのプロンプト候補: ›, >, $, ➜, ❯
                        if any(char in last_line for char in ['›', '>', '$', '➜', '❯']):
                            # プロンプト検出
                            for char in ['›', '>', '$', '➜', '❯']:
                                if char in last_line:
                                    print(f"\n\n[DETECTED] Prompt character: '{char}'")
                                    print(f"Last line: {repr(last_line)}")

                                    # テストメッセージを送信
                                    print("\n[AUTO] Sending test message: 'hello'")
                                    time.sleep(1)
                                    os.write(master_fd, b'hello\r')
                                    message_sent = True

                                    # 応答を少し待つ
                                    time.sleep(3)

                                    # 結果を返す
                                    os.close(master_fd)
                                    os.kill(pid, 9)
                                    try:
                                        os.waitpid(pid, 0)
                                    except:
                                        pass

                                    return {
                                        'success': True,
                                        'prompt_char': char,
                                        'last_line': last_line,
                                        'full_output': buffer
                                    }

                except OSError:
                    break

        # タイムアウト
        print("\n\n[TIMEOUT] No prompt detected within timeout period")
        os.close(master_fd)
        os.kill(pid, 9)
        try:
            os.waitpid(pid, 0)
        except:
            pass

        return {
            'success': False,
            'prompt_char': None,
            'full_output': buffer
        }

if __name__ == "__main__":
    result = test_claude_with_trust(timeout=60)

    print("\n" + "="*60)
    print("RESULT")
    print("="*60)
    if result['success']:
        print(f"✅ Success!")
        print(f"Prompt character: '{result['prompt_char']}'")
    else:
        print(f"❌ Failed to detect prompt")
        print(f"Output length: {len(result['full_output'])} chars")
    print("="*60)
