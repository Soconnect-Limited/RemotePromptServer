"""Cloudflare DNS API integration for automatic subdomain registration."""
from __future__ import annotations

import logging
import os
import random
import string
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import httpx

LOGGER = logging.getLogger(__name__)

# Cloudflare API base URL
CLOUDFLARE_API_BASE = "https://api.cloudflare.com/client/v4"


@dataclass
class DNSRecord:
    """DNS record information."""
    id: str
    name: str
    type: str
    content: str
    ttl: int
    proxied: bool


class CloudflareError(Exception):
    """Cloudflare API error."""
    pass


class CloudflareDNS:
    """Cloudflare DNS API client."""

    def __init__(
        self,
        api_token: Optional[str] = None,
        zone_id: Optional[str] = None,
        domain: str = "remoteprompt.net",
    ):
        """Initialize Cloudflare DNS client.

        Args:
            api_token: Cloudflare API token with DNS edit permission
            zone_id: Cloudflare Zone ID for the domain
            domain: Base domain name
        """
        self.api_token = api_token or self._load_api_token()
        self.zone_id = zone_id or os.environ.get("CLOUDFLARE_ZONE_ID", "")
        self.domain = domain

        if not self.api_token:
            raise CloudflareError("Cloudflare API token not configured")

    def _load_api_token(self) -> str:
        """Load API token from environment or secrets file."""
        # Try environment variable first
        token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
        if token:
            return token

        # Try secrets file
        secrets_paths = [
            Path("/Users/macstudio/Projects/RemotePrompt/secrets/cloudflare_api_token.txt"),
            Path("./secrets/cloudflare_api_token.txt"),
            Path("../secrets/cloudflare_api_token.txt"),
        ]

        for path in secrets_paths:
            if path.exists():
                token = path.read_text().strip()
                if token:
                    return token

        # Try cloudflare.ini format
        ini_paths = [
            Path("/Users/macstudio/Projects/RemotePrompt/secrets/cloudflare.ini"),
            Path("./secrets/cloudflare.ini"),
            Path("../secrets/cloudflare.ini"),
        ]

        for path in ini_paths:
            if path.exists():
                content = path.read_text()
                for line in content.splitlines():
                    if line.startswith("dns_cloudflare_api_token"):
                        parts = line.split("=", 1)
                        if len(parts) == 2:
                            return parts[1].strip()

        return ""

    def _headers(self) -> dict:
        """Get API request headers."""
        return {
            "Authorization": f"Bearer {self.api_token}",
            "Content-Type": "application/json",
        }

    async def get_zone_id(self) -> str:
        """Get Zone ID for the domain if not already set."""
        if self.zone_id:
            return self.zone_id

        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{CLOUDFLARE_API_BASE}/zones",
                headers=self._headers(),
                params={"name": self.domain},
            )

            data = response.json()
            if not data.get("success"):
                errors = data.get("errors", [])
                raise CloudflareError(f"Failed to get zone ID: {errors}")

            zones = data.get("result", [])
            if not zones:
                raise CloudflareError(f"Zone not found for domain: {self.domain}")

            self.zone_id = zones[0]["id"]
            return self.zone_id

    async def create_subdomain(
        self,
        subdomain: str,
        ip_address: str,
        ttl: int = 300,
        proxied: bool = False,
    ) -> DNSRecord:
        """Create a new A record for a subdomain.

        Args:
            subdomain: Subdomain name (without the base domain)
            ip_address: IPv4 address to point to
            ttl: Time to live in seconds (default: 300 = 5 minutes)
            proxied: Whether to proxy through Cloudflare (default: False for direct connection)

        Returns:
            DNSRecord with the created record info
        """
        zone_id = await self.get_zone_id()
        full_name = f"{subdomain}.{self.domain}"

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records",
                headers=self._headers(),
                json={
                    "type": "A",
                    "name": full_name,
                    "content": ip_address,
                    "ttl": ttl,
                    "proxied": proxied,
                },
            )

            data = response.json()
            if not data.get("success"):
                errors = data.get("errors", [])
                # Check for duplicate record error
                for error in errors:
                    if error.get("code") == 81057:  # Record already exists
                        raise CloudflareError(f"Subdomain '{subdomain}' already exists")
                raise CloudflareError(f"Failed to create DNS record: {errors}")

            result = data["result"]
            LOGGER.info(
                "[CLOUDFLARE] Created subdomain: %s -> %s",
                full_name, ip_address
            )

            return DNSRecord(
                id=result["id"],
                name=result["name"],
                type=result["type"],
                content=result["content"],
                ttl=result["ttl"],
                proxied=result["proxied"],
            )

    async def get_subdomain(self, subdomain: str) -> Optional[DNSRecord]:
        """Get existing subdomain record if it exists."""
        zone_id = await self.get_zone_id()
        full_name = f"{subdomain}.{self.domain}"

        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records",
                headers=self._headers(),
                params={"type": "A", "name": full_name},
            )

            data = response.json()
            if not data.get("success"):
                return None

            records = data.get("result", [])
            if not records:
                return None

            result = records[0]
            return DNSRecord(
                id=result["id"],
                name=result["name"],
                type=result["type"],
                content=result["content"],
                ttl=result["ttl"],
                proxied=result["proxied"],
            )

    async def update_subdomain(
        self,
        subdomain: str,
        ip_address: str,
        ttl: int = 300,
        proxied: bool = False,
    ) -> DNSRecord:
        """Update an existing subdomain's IP address.

        Args:
            subdomain: Subdomain name
            ip_address: New IPv4 address
            ttl: Time to live
            proxied: Whether to proxy through Cloudflare

        Returns:
            Updated DNSRecord
        """
        zone_id = await self.get_zone_id()

        # First get the existing record
        existing = await self.get_subdomain(subdomain)
        if not existing:
            raise CloudflareError(f"Subdomain '{subdomain}' not found")

        async with httpx.AsyncClient() as client:
            response = await client.put(
                f"{CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records/{existing.id}",
                headers=self._headers(),
                json={
                    "type": "A",
                    "name": existing.name,
                    "content": ip_address,
                    "ttl": ttl,
                    "proxied": proxied,
                },
            )

            data = response.json()
            if not data.get("success"):
                errors = data.get("errors", [])
                raise CloudflareError(f"Failed to update DNS record: {errors}")

            result = data["result"]
            LOGGER.info(
                "[CLOUDFLARE] Updated subdomain: %s -> %s",
                existing.name, ip_address
            )

            return DNSRecord(
                id=result["id"],
                name=result["name"],
                type=result["type"],
                content=result["content"],
                ttl=result["ttl"],
                proxied=result["proxied"],
            )

    async def delete_subdomain(self, subdomain: str) -> bool:
        """Delete a subdomain record.

        Args:
            subdomain: Subdomain name

        Returns:
            True if deleted successfully
        """
        zone_id = await self.get_zone_id()

        existing = await self.get_subdomain(subdomain)
        if not existing:
            return False

        async with httpx.AsyncClient() as client:
            response = await client.delete(
                f"{CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records/{existing.id}",
                headers=self._headers(),
            )

            data = response.json()
            if not data.get("success"):
                errors = data.get("errors", [])
                raise CloudflareError(f"Failed to delete DNS record: {errors}")

            LOGGER.info("[CLOUDFLARE] Deleted subdomain: %s", existing.name)
            return True


def generate_random_subdomain(length: int = 8) -> str:
    """Generate a random subdomain name.

    Args:
        length: Length of random string (default: 8)

    Returns:
        Random lowercase alphanumeric string
    """
    chars = string.ascii_lowercase + string.digits
    return ''.join(random.choice(chars) for _ in range(length))


# Global instance (initialized lazily)
_cloudflare_dns: Optional[CloudflareDNS] = None


def get_cloudflare_dns() -> CloudflareDNS:
    """Get or create the global CloudflareDNS instance."""
    global _cloudflare_dns
    if _cloudflare_dns is None:
        _cloudflare_dns = CloudflareDNS()
    return _cloudflare_dns
