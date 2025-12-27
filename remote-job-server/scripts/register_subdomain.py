#!/usr/bin/env python3
"""サブドメイン発行CLIツール

使用方法:
    python scripts/register_subdomain.py

Tailscale IPアドレスを入力すると、ランダムなサブドメインを発行し、
CloudflareにDNSレコードを登録します。
"""
import asyncio
import re
import sys
from pathlib import Path

# プロジェクトルートをパスに追加
sys.path.insert(0, str(Path(__file__).parent.parent))

from cloudflare_dns import CloudflareDNS, CloudflareError, generate_random_subdomain


def validate_tailscale_ip(ip: str) -> bool:
    """Tailscale IP (100.x.x.x) かどうか検証"""
    pattern = r'^100\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
    if not re.match(pattern, ip):
        return False

    # 各オクテットが0-255の範囲内か確認
    parts = ip.split('.')
    for part in parts:
        if int(part) > 255:
            return False
    return True


async def register_subdomain(tailscale_ip: str) -> dict:
    """サブドメインを登録"""
    cloudflare = CloudflareDNS()

    # ランダムなサブドメインを生成
    subdomain = generate_random_subdomain(8)

    # DNSレコードを作成
    record = await cloudflare.create_subdomain(
        subdomain=subdomain,
        ip_address=tailscale_ip,
        ttl=300,
        proxied=False,
    )

    return {
        "subdomain": subdomain,
        "full_domain": f"{subdomain}.remoteprompt.net",
        "ip": tailscale_ip,
        "record_id": record.id,
    }


async def main():
    print("=" * 60)
    print("  RemotePrompt サブドメイン発行ツール")
    print("=" * 60)
    print()

    # IPアドレスを入力
    while True:
        ip = input("Tailscale IPアドレスを入力 (100.x.x.x): ").strip()

        if not ip:
            print("キャンセルしました。")
            return

        if validate_tailscale_ip(ip):
            break
        else:
            print("エラー: Tailscale IPアドレス (100.x.x.x) を入力してください。")
            print()

    print()
    print(f"IPアドレス: {ip}")
    print("サブドメインを発行しています...")
    print()

    try:
        result = await register_subdomain(ip)

        print("=" * 60)
        print("  発行完了!")
        print("=" * 60)
        print()
        print(f"  サブドメイン: {result['subdomain']}")
        print(f"  フルドメイン: {result['full_domain']}")
        print(f"  IPアドレス:   {result['ip']}")
        print()
        print(f"  サーバーURL:  https://{result['full_domain']}:8443")
        print()
        print("=" * 60)
        print()
        print("次のステップ:")
        print("  1. ユーザーに上記URLを共有")
        print("  2. ユーザーのサーバーでLet's Encrypt証明書を発行")
        print()

        return result

    except CloudflareError as e:
        print(f"エラー: Cloudflare APIエラー - {e}")
        return None
    except Exception as e:
        print(f"エラー: {e}")
        return None


if __name__ == "__main__":
    asyncio.run(main())
