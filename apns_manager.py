"""APNs Push Notification Manager for RemotePrompt."""
from __future__ import annotations

from pathlib import Path
from typing import Optional
import logging
import time
import jwt

try:
    import httpx
    APNS_AVAILABLE = True
except ImportError:
    APNS_AVAILABLE = False

from config import settings

LOGGER = logging.getLogger(__name__)


class APNsManager:
    """Apple Push Notification service manager."""

    def __init__(self) -> None:
        """Initialize APNs client."""
        if not APNS_AVAILABLE:
            LOGGER.warning("httpx not installed. Push notifications disabled.")
            self.enabled = False
            return

        # APNs設定をconfigから取得
        self.key_path_str = settings.apns_key_path
        self.key_id = settings.apns_key_id
        self.team_id = settings.apns_team_id
        self.bundle_id = settings.apns_bundle_id
        self.environment = settings.apns_environment

        # 必須パラメータチェック
        if not all([self.key_path_str, self.key_id, self.team_id, self.bundle_id]):
            LOGGER.warning(
                "APNs configuration incomplete. Push notifications disabled. "
                "Required: APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID"
            )
            self.enabled = False
            return

        key_path = Path(self.key_path_str)
        if not key_path.exists():
            LOGGER.warning("APNs key not found: %s. Push notifications disabled.", key_path)
            self.enabled = False
            return

        try:
            # Load private key
            with open(key_path, "r") as f:
                self.private_key = f.read()

            self.apns_host = "api.sandbox.push.apple.com" if self.environment == "sandbox" else "api.push.apple.com"
            self.enabled = True

            LOGGER.debug("APNs initializing with: key_id=%s, team_id=%s, bundle_id=%s, sandbox=%s",
                        self.key_id, self.team_id, self.bundle_id, self.environment == "sandbox")
            LOGGER.info("APNs initialized successfully (environment=%s, host=%s)", self.environment, self.apns_host)
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.exception("Failed to initialize APNs: %s", exc)
            self.enabled = False

    def _generate_jwt_token(self) -> str:
        """Generate JWT token for APNs authentication."""
        headers = {
            "alg": "ES256",
            "kid": self.key_id,
        }

        payload = {
            "iss": self.team_id,
            "iat": int(time.time()),
        }

        token = jwt.encode(payload, self.private_key, algorithm="ES256", headers=headers)
        return token

    async def send_notification(
        self,
        device_token: str,
        title: str,
        body: str,
        badge: Optional[int] = None,
    ) -> bool:
        """
        Send push notification to device.

        Args:
            device_token: APNs device token (hex string)
            title: Notification title
            body: Notification body
            badge: Badge count (optional)

        Returns:
            True if notification sent successfully, False otherwise
        """
        if not self.enabled:
            LOGGER.debug("APNs not enabled. Skipping notification.")
            return False

        if not device_token:
            LOGGER.debug("No device token provided. Skipping notification.")
            return False

        try:
            # Generate JWT token
            token = self._generate_jwt_token()

            # Construct APNs URL
            url = f"https://{self.apns_host}/3/device/{device_token}"

            # Prepare headers
            headers = {
                "authorization": f"bearer {token}",
                "apns-topic": self.bundle_id,
                "apns-push-type": "alert",
            }

            # Prepare payload
            payload = {
                "aps": {
                    "alert": {
                        "title": title,
                        "body": body
                    },
                    "sound": "default",
                }
            }

            if badge is not None:
                payload["aps"]["badge"] = badge

            # Send notification using httpx with HTTP/2
            async with httpx.AsyncClient(http2=True, timeout=30.0) as client:
                response = await client.post(url, json=payload, headers=headers)

                if response.status_code == 200:
                    LOGGER.info("📱 Notification sent to %s: %s", device_token[:8], title)
                    return True
                else:
                    LOGGER.error(
                        "Failed to send notification to %s: HTTP %d - %s",
                        device_token[:8],
                        response.status_code,
                        response.text
                    )
                    return False

        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.error("Failed to send notification to %s: %s", device_token[:8], exc)
            return False
