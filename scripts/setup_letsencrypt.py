#!/usr/bin/env python3
"""Let's Encrypt証明書発行・自動更新セットアップスクリプト（HTTPチャレンジ版）

使用方法:
    python3 scripts/setup_letsencrypt.py <subdomain>

例:
    python3 scripts/setup_letsencrypt.py abc12345

前提条件:
    - 管理者がDNS登録済み（<subdomain>.remoteprompt.net → あなたのIP）
    - ポート80が一時的に使用可能であること

このスクリプトは:
1. certbotをインストール
2. HTTPチャレンジでLet's Encrypt証明書を発行
3. 自動更新のlaunchdジョブを設定（macOS）
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


DOMAIN = "remoteprompt.net"
CERT_BASE_DIR = Path("./certs")


def run_command(cmd: list, check: bool = True) -> subprocess.CompletedProcess:
    """コマンドを実行"""
    print(f"実行: {' '.join(cmd)}")
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def check_certbot_installed() -> bool:
    """certbotがインストールされているか確認"""
    result = subprocess.run(["which", "certbot"], capture_output=True)
    return result.returncode == 0


def install_certbot():
    """certbotをインストール"""
    print("certbotをインストールしています...")

    # Homebrewでインストール
    try:
        run_command(["brew", "install", "certbot"])
    except subprocess.CalledProcessError:
        print("警告: brewでのインストールに失敗しました。pipでインストールを試みます。")
        run_command([sys.executable, "-m", "pip", "install", "certbot"])


def check_dns_resolution(full_domain: str) -> bool:
    """DNSが正しく解決されるか確認"""
    print(f"DNS解決を確認しています: {full_domain}")
    result = subprocess.run(["dig", "+short", full_domain], capture_output=True, text=True)

    if result.returncode != 0 or not result.stdout.strip():
        print(f"エラー: {full_domain} のDNS解決に失敗しました。")
        print("管理者にDNS登録を依頼してください。")
        return False

    resolved_ip = result.stdout.strip().split('\n')[0]
    print(f"  → {resolved_ip}")
    return True


def check_port_80_available() -> bool:
    """ポート80が使用可能か確認"""
    result = subprocess.run(["lsof", "-i", ":80"], capture_output=True, text=True)
    if result.stdout.strip():
        print("警告: ポート80が使用中です。")
        print(result.stdout)
        print("証明書発行中は一時的にポート80を使用します。")
        return False
    return True


def issue_certificate(subdomain: str) -> Path:
    """Let's Encrypt証明書を発行（HTTPチャレンジ）"""
    full_domain = f"{subdomain}.{DOMAIN}"
    cert_dir = CERT_BASE_DIR / DOMAIN / "config"
    cert_dir.mkdir(parents=True, exist_ok=True)

    # DNS解決確認
    if not check_dns_resolution(full_domain):
        sys.exit(1)

    # ポート80確認（警告のみ）
    check_port_80_available()

    print(f"証明書を発行しています: {full_domain}")
    print("（HTTPチャレンジのため、ポート80で一時的にサーバーが起動します）")

    cmd = [
        "sudo", "certbot", "certonly",
        "--standalone",
        "--preferred-challenges", "http",
        "-d", full_domain,
        "--config-dir", str(cert_dir.absolute()),
        "--work-dir", str((cert_dir / "work").absolute()),
        "--logs-dir", str((cert_dir / "logs").absolute()),
        "--non-interactive",
        "--agree-tos",
        "--email", "noreply@remoteprompt.net",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("エラー: 証明書の発行に失敗しました。")
        print(result.stderr)
        print()
        print("考えられる原因:")
        print("  1. ポート80が別のプロセスで使用中")
        print("  2. ファイアウォールでポート80がブロックされている")
        print("  3. DNSがまだ伝播していない（数分待ってから再試行）")
        sys.exit(1)

    cert_path = cert_dir / "live" / full_domain
    print(f"証明書が発行されました: {cert_path}")

    # 証明書ファイルの所有権を現在のユーザーに変更
    current_user = os.environ.get("USER", "")
    if current_user:
        subprocess.run(["sudo", "chown", "-R", current_user, str(cert_dir)], check=False)

    return cert_path


def setup_auto_renewal(subdomain: str):
    """自動更新のlaunchdジョブを設定（macOS）"""
    full_domain = f"{subdomain}.{DOMAIN}"
    cert_dir = CERT_BASE_DIR / DOMAIN / "config"

    # ログディレクトリを作成
    (cert_dir / "logs").mkdir(parents=True, exist_ok=True)

    # 更新スクリプトを作成
    script_path = Path(__file__).parent / "renew-letsencrypt.sh"
    script_content = f"""#!/bin/bash
# Let's Encrypt証明書自動更新スクリプト

CERT_DIR="{cert_dir.absolute()}"

# 証明書を更新（HTTPチャレンジ）
sudo certbot renew \\
    --standalone \\
    --preferred-challenges http \\
    --config-dir "$CERT_DIR" \\
    --work-dir "$CERT_DIR/work" \\
    --logs-dir "$CERT_DIR/logs" \\
    --quiet

# サーバーを再起動（証明書を反映）
pkill -HUP -f "uvicorn main:app" 2>/dev/null || true

echo "[$(date)] 証明書更新チェック完了" >> "$CERT_DIR/logs/renewal.log"
"""
    script_path.write_text(script_content)
    script_path.chmod(0o755)

    # launchdのplistを作成
    plist_path = Path.home() / "Library/LaunchAgents/com.remoteprompt.certbot-renew.plist"
    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.remoteprompt.certbot-renew</string>
    <key>ProgramArguments</key>
    <array>
        <string>{script_path.absolute()}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>{cert_dir.absolute()}/logs/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>{cert_dir.absolute()}/logs/launchd-stderr.log</string>
</dict>
</plist>
"""
    plist_path.parent.mkdir(parents=True, exist_ok=True)
    plist_path.write_text(plist_content)

    # launchdジョブを登録
    subprocess.run(["launchctl", "unload", str(plist_path)], capture_output=True)
    subprocess.run(["launchctl", "load", str(plist_path)], check=True)

    print(f"自動更新を設定しました（毎日3:00 AM）")
    print(f"  スクリプト: {script_path}")
    print(f"  plist: {plist_path}")


def update_env_file(subdomain: str, cert_path: Path):
    """`.env`ファイルを更新"""
    full_domain = f"{subdomain}.{DOMAIN}"
    env_path = Path(__file__).parent.parent / ".env"

    if not env_path.exists():
        print(f"警告: {env_path} が見つかりません。手動で設定してください。")
        return

    content = env_path.read_text()

    # SERVER_HOSTNAMEを更新
    if "SERVER_HOSTNAME=" in content:
        content = re.sub(r'SERVER_HOSTNAME=.*', f'SERVER_HOSTNAME={full_domain}', content)
    else:
        content += f"\nSERVER_HOSTNAME={full_domain}\n"

    # SSL_MODEを更新
    if "SSL_MODE=" in content:
        content = re.sub(r'SSL_MODE=.*', 'SSL_MODE=commercial', content)
    else:
        content += "SSL_MODE=commercial\n"

    # 証明書パスを更新
    cert_fullchain = cert_path / "fullchain.pem"
    cert_privkey = cert_path / "privkey.pem"

    if "COMMERCIAL_CERT_PATH=" in content:
        content = re.sub(r'COMMERCIAL_CERT_PATH=.*', f'COMMERCIAL_CERT_PATH={cert_fullchain}', content)
        content = re.sub(r'COMMERCIAL_KEY_PATH=.*', f'COMMERCIAL_KEY_PATH={cert_privkey}', content)
    else:
        content += f"COMMERCIAL_CERT_PATH={cert_fullchain}\n"
        content += f"COMMERCIAL_KEY_PATH={cert_privkey}\n"

    env_path.write_text(content)
    print(f".envファイルを更新しました: {env_path}")


def main():
    parser = argparse.ArgumentParser(description="Let's Encrypt証明書発行・自動更新セットアップ（HTTPチャレンジ）")
    parser.add_argument("subdomain", help="管理者から発行されたサブドメイン名（例: abc12345）")
    parser.add_argument("--skip-install", action="store_true", help="certbotのインストールをスキップ")
    args = parser.parse_args()

    subdomain = args.subdomain.strip()
    full_domain = f"{subdomain}.{DOMAIN}"

    print("=" * 60)
    print("  Let's Encrypt 証明書セットアップ（HTTPチャレンジ）")
    print("=" * 60)
    print()
    print(f"  ドメイン: {full_domain}")
    print()
    print("  前提条件:")
    print("    - 管理者がDNS登録済みであること")
    print("    - ポート80が一時的に使用可能であること")
    print()

    # certbotのインストール確認
    if not args.skip_install and not check_certbot_installed():
        install_certbot()

    # 証明書発行
    cert_path = issue_certificate(subdomain)

    # 自動更新設定
    setup_auto_renewal(subdomain)

    # .env更新
    update_env_file(subdomain, cert_path)

    print()
    print("=" * 60)
    print("  セットアップ完了!")
    print("=" * 60)
    print()
    print("サーバーを起動してください:")
    print("  python main.py")
    print()


if __name__ == "__main__":
    main()
