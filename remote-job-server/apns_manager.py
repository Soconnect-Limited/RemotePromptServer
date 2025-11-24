"""APNs Push Notification Manager for RemotePrompt."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional
import logging

try:
    from aioapns import APNs, NotificationRequest
    APNS_AVAILABLE = True
except ImportError:
    APNS_AVAILABLE = False

from dotenv import load_dotenv

load_dotenv()

LOGGER = logging.getLogger(__name__)


class APNsManager:
    """Apple Push Notification service manager."""

    def __init__(self) -> None:
        """Initialize APNs client."""
        if not APNS_AVAILABLE:
            LOGGER.warning("aioapns not installed. Push notifications disabled.")
            self.client = None
            return

        # APNs設定を環境変数から取得
        key_path_str = os.getenv("APNS_KEY_PATH", "")
        key_id = os.getenv("APNS_KEY_ID", "")
        team_id = os.getenv("APNS_TEAM_ID", "")
        bundle_id = os.getenv("APNS_BUNDLE_ID", "")
        environment = os.getenv("APNS_ENVIRONMENT", "sandbox")

        # 必須パラメータチェック
        if not all([key_path_str, key_id, team_id, bundle_id]):
            LOGGER.warning(
                "APNs configuration incomplete. Push notifications disabled. "
                "Required: APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID"
            )
            self.client = None
            return

        key_path = Path(key_path_str)
        if not key_path.exists():
            LOGGER.warning("APNs key not found: %s. Push notifications disabled.", key_path)
            self.client = None
            return

        try:
            self.client = APNs(
                key=str(key_path),
                key_id=key_id,
                team_id=team_id,
                topic=bundle_id,
                use_sandbox=environment == "sandbox",
            )
            LOGGER.info("APNs initialized successfully (environment=%s)", environment)
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.exception("Failed to initialize APNs: %s", exc)
            self.client = None

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
        if not self.client:
            LOGGER.debug("APNs client not initialized. Skipping notification.")
            return False

        if not device_token:
            LOGGER.debug("No device token provided. Skipping notification.")
            return False

        try:
            request = NotificationRequest(
                device_token=device_token,
                message={
                    "aps": {
                        "alert": {"title": title, "body": body},
                        "badge": badge,
                        "sound": "default",
                    }
                },
            )
            await self.client.send_notification(request)
            LOGGER.info("📱 Notification sent to %s: %s", device_token[:8], title)
            return True
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.error("Failed to send notification to %s: %s", device_token[:8], exc)
            return False
