"""Direct APNs test using httpx and JWT authentication."""
import asyncio
import time
import jwt
from pathlib import Path
import httpx

# APNs configuration
KEY_PATH = "/Users/macstudio/Projects/RemotePrompt/secrets/AuthKey_ZS5AU7F877.p8"
KEY_ID = "ZS5AU7F877"
TEAM_ID = "577RWAHGXN"
BUNDLE_ID = "jp.co.soconnect.RemotePrompt"
DEVICE_TOKEN = "02aaecd45830ed1e1e5aada1bdcef2e8d71f7fa5027a0084a732543f82fdac50"
APNS_HOST = "api.sandbox.push.apple.com"


def generate_jwt_token():
    """Generate JWT token for APNs authentication."""
    with open(KEY_PATH, "r") as f:
        private_key = f.read()

    headers = {
        "alg": "ES256",
        "kid": KEY_ID,
    }

    payload = {
        "iss": TEAM_ID,
        "iat": int(time.time()),
    }

    token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    return token


async def send_notification():
    """Send APNs notification using httpx."""
    token = generate_jwt_token()

    url = f"https://{APNS_HOST}/3/device/{DEVICE_TOKEN}"

    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": BUNDLE_ID,
        "apns-push-type": "alert",
    }

    payload = {
        "aps": {
            "alert": {
                "title": "テスト通知",
                "body": "httpxから直接送信"
            },
            "sound": "default",
        }
    }

    print(f"Sending notification to {APNS_HOST}...")
    print(f"Device token: {DEVICE_TOKEN[:16]}...")
    print(f"JWT token: {token[:50]}...")

    async with httpx.AsyncClient(http2=True, timeout=30.0) as client:
        response = await client.post(url, json=payload, headers=headers)

        print(f"\nResponse status: {response.status_code}")
        print(f"Response headers: {dict(response.headers)}")
        print(f"Response body: {response.text}")

        if response.status_code == 200:
            print("\n✅ Notification sent successfully!")
            return True
        else:
            print(f"\n❌ Failed to send notification: {response.status_code}")
            return False


if __name__ == "__main__":
    asyncio.run(send_notification())
