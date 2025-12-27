#!/usr/bin/env python3
"""Let's Encrypt証明書発行・自動更新セットアップスクリプト

使用方法:
    python scripts/setup_letsencrypt.py <subdomain>

例:
    python scripts/setup_letsencrypt.py abc12345

このスクリプトは:
1. certbotとcloudflareプラグインをインストール
2. DNS-01チャレンジでLet's Encrypt証明書を発行
3. 自動更新のlaunchdジョブを設定（macOS）
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path


DOMAIN = "remoteprompt.net"
CERT_BASE_DIR = Path("./certs")
SECRETS_DIR = Path(__file__).parent.parent.parent / "secrets"


def run_command(cmd: list, check: bool = True) -> subprocess.CompletedProcess:
    """コマンドを実行"""
    print(f"実行: {' '.join(cmd)}")
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def check_certbot_installed() -> bool:
    """certbotがインストールされているか確認"""
    result = subprocess.run(["which", "certbot"], capture_output=True)
    return result.returncode == 0


def install_certbot():
    """certbotとcloudflareプラグインをインストール"""
    print("certbotをインストールしています...")

    # Homebrewでインストール
    try:
        run_command(["brew", "install", "certbot"])
    except subprocess.CalledProcessError:
        print("警告: brewでのインストールに失敗しました。pipでインストールを試みます。")
        run_command([sys.executable, "-m", "pip", "install", "certbot", "certbot-dns-cloudflare"])
        return

    # cloudflareプラグインをpipでインストール
    run_command([sys.executable, "-m", "pip", "install", "certbot-dns-cloudflare"])


def get_cloudflare_credentials_path() -> Path:
    """Cloudflare認証情報ファイルのパスを取得"""
    # 既存のcloudflare.iniを探す
    possible_paths = [
        SECRETS_DIR / "cloudflare.ini",
        Path.home() / ".secrets" / "cloudflare.ini",
        Path("/etc/letsencrypt/cloudflare.ini"),
    ]

    for path in possible_paths:
        if path.exists():
            return path

    # 見つからない場合は作成を促す
    print("エラー: Cloudflare認証情報ファイルが見つかりません。")
    print(f"以下のいずれかの場所に作成してください:")
    for path in possible_paths:
        print(f"  - {path}")
    print()
    print("ファイル内容:")
    print("  dns_cloudflare_api_token = YOUR_API_TOKEN")
    sys.exit(1)


def issue_certificate(subdomain: str) -> Path:
    """Let's Encrypt証明書を発行"""
    full_domain = f"{subdomain}.{DOMAIN}"
    cert_dir = CERT_BASE_DIR / DOMAIN / "config"
    cert_dir.mkdir(parents=True, exist_ok=True)

    credentials_path = get_cloudflare_credentials_path()

    print(f"証明書を発行しています: {full_domain}")

    cmd = [
        "certbot", "certonly",
        "--dns-cloudflare",
        "--dns-cloudflare-credentials", str(credentials_path),
        "--dns-cloudflare-propagation-seconds", "30",
        "-d", full_domain,
        "--config-dir", str(cert_dir),
        "--work-dir", str(cert_dir / "work"),
        "--logs-dir", str(cert_dir / "logs"),
        "--non-interactive",
        "--agree-tos",
        "--email", "admin@remoteprompt.net",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("エラー: 証明書の発行に失敗しました。")
        print(result.stderr)
        sys.exit(1)

    cert_path = cert_dir / "live" / full_domain
    print(f"証明書が発行されました: {cert_path}")

    return cert_path


def setup_auto_renewal(subdomain: str):
    """自動更新のlaunchdジョブを設定（macOS）"""
    full_domain = f"{subdomain}.{DOMAIN}"
    cert_dir = CERT_BASE_DIR / DOMAIN / "config"

    # 更新スクリプトを作成
    script_path = Path(__file__).parent / "renew-letsencrypt.sh"
    script_content = f"""#!/bin/bash
# Let's Encrypt証明書自動更新スクリプト

CERT_DIR="{cert_dir.absolute()}"

# 証明書を更新
certbot renew \\
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
        import re
        content = re.sub(r'SERVER_HOSTNAME=.*', f'SERVER_HOSTNAME={full_domain}', content)
    else:
        content += f"\nSERVER_HOSTNAME={full_domain}\n"

    # 証明書パスを更新
    cert_fullchain = cert_path / "fullchain.pem"
    cert_privkey = cert_path / "privkey.pem"

    if "COMMERCIAL_CERT_PATH=" in content:
        import re
        content = re.sub(r'COMMERCIAL_CERT_PATH=.*', f'COMMERCIAL_CERT_PATH={cert_fullchain}', content)
        content = re.sub(r'COMMERCIAL_KEY_PATH=.*', f'COMMERCIAL_KEY_PATH={cert_privkey}', content)
    else:
        content += f"\nCOMMERCIAL_CERT_PATH={cert_fullchain}\n"
        content += f"COMMERCIAL_KEY_PATH={cert_privkey}\n"

    env_path.write_text(content)
    print(f".envファイルを更新しました: {env_path}")


def main():
    parser = argparse.ArgumentParser(description="Let's Encrypt証明書発行・自動更新セットアップ")
    parser.add_argument("subdomain", help="サブドメイン名（例: abc12345）")
    parser.add_argument("--skip-install", action="store_true", help="certbotのインストールをスキップ")
    args = parser.parse_args()

    subdomain = args.subdomain.strip()
    full_domain = f"{subdomain}.{DOMAIN}"

    print("=" * 60)
    print("  Let's Encrypt 証明書セットアップ")
    print("=" * 60)
    print()
    print(f"  ドメイン: {full_domain}")
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
    print("サーバーを再起動してください:")
    print("  pkill -f 'uvicorn main:app'")
    print("  python -m uvicorn main:app --host 0.0.0.0 --port 8443 \\")
    print(f"    --ssl-keyfile {cert_path}/privkey.pem \\")
    print(f"    --ssl-certfile {cert_path}/fullchain.pem")
    print()


if __name__ == "__main__":
    main()
