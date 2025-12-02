"""Self-signed certificate generator for RemotePrompt server.

Provides SSH-style trust model where users verify certificate fingerprint on first connection.
"""
from __future__ import annotations

import logging
import os
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import List, Optional, Tuple

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

LOGGER = logging.getLogger(__name__)

# Default paths for self-signed certificates
DEFAULT_CERT_DIR = Path("certs/self_signed")
DEFAULT_CERT_PATH = DEFAULT_CERT_DIR / "server.crt"
DEFAULT_KEY_PATH = DEFAULT_CERT_DIR / "server.key"
BACKUP_DIR = DEFAULT_CERT_DIR / "backup"


def generate_self_signed_cert(
    common_name: str,
    san_ips: List[str],
    valid_days: int = 3650,
    key_size: int = 4096,
) -> Tuple[bytes, bytes]:
    """Generate a self-signed certificate with the given parameters.

    Args:
        common_name: Common Name for the certificate (e.g., IP address or hostname)
        san_ips: List of IP addresses for Subject Alternative Names
        valid_days: Certificate validity period in days (default: 10 years)
        key_size: RSA key size in bits (default: 4096)

    Returns:
        Tuple of (certificate_pem, private_key_pem) as bytes
    """
    # Generate RSA private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=key_size,
    )

    # Build subject and issuer
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "RemotePrompt Self-Signed"),
        x509.NameAttribute(NameOID.COMMON_NAME, common_name),
    ])

    # Build Subject Alternative Names
    san_list: List[x509.GeneralName] = []
    for ip_str in san_ips:
        try:
            from ipaddress import ip_address
            san_list.append(x509.IPAddress(ip_address(ip_str)))
        except ValueError:
            # If not a valid IP, treat as DNS name
            san_list.append(x509.DNSName(ip_str))

    # Certificate validity period
    now = datetime.now(timezone.utc)
    not_valid_before = now
    not_valid_after = now + timedelta(days=valid_days)

    # Build certificate
    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(not_valid_before)
        .not_valid_after(not_valid_after)
        .add_extension(
            x509.BasicConstraints(ca=False, path_length=None),
            critical=True,
        )
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                key_encipherment=True,
                content_commitment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]),
            critical=False,
        )
    )

    if san_list:
        builder = builder.add_extension(
            x509.SubjectAlternativeName(san_list),
            critical=False,
        )

    # Sign the certificate
    certificate = builder.sign(private_key, hashes.SHA256())

    # Serialize to PEM format
    cert_pem = certificate.public_bytes(serialization.Encoding.PEM)
    key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption(),
    )

    return cert_pem, key_pem


def get_certificate_fingerprint(cert_path: str) -> str:
    """Calculate SHA256 fingerprint of a certificate file.

    Args:
        cert_path: Path to the certificate file (PEM format)

    Returns:
        Fingerprint in colon-separated format (e.g., "SHA256:A1:B2:C3:...")
    """
    with open(cert_path, "rb") as f:
        cert_data = f.read()

    cert = x509.load_pem_x509_certificate(cert_data)
    fingerprint = cert.fingerprint(hashes.SHA256())
    hex_str = fingerprint.hex().upper()
    formatted = ":".join(hex_str[i:i+2] for i in range(0, len(hex_str), 2))
    return f"SHA256:{formatted}"


def get_certificate_info(cert_path: str) -> dict:
    """Get detailed information about a certificate.

    Args:
        cert_path: Path to the certificate file (PEM format)

    Returns:
        Dictionary with certificate information
    """
    with open(cert_path, "rb") as f:
        cert_data = f.read()

    cert = x509.load_pem_x509_certificate(cert_data)
    fingerprint = get_certificate_fingerprint(cert_path)

    # Extract Common Name
    common_name = ""
    for attr in cert.subject:
        if attr.oid == NameOID.COMMON_NAME:
            common_name = attr.value
            break

    # Extract issuer organization
    issuer = ""
    for attr in cert.issuer:
        if attr.oid == NameOID.ORGANIZATION_NAME:
            issuer = attr.value
            break

    # Check if self-signed
    is_self_signed = cert.subject == cert.issuer

    return {
        "fingerprint": fingerprint,
        "common_name": common_name,
        "valid_from": cert.not_valid_before_utc.isoformat(),
        "valid_until": cert.not_valid_after_utc.isoformat(),
        "issuer": issuer,
        "serial_number": str(cert.serial_number),
        "is_self_signed": is_self_signed,
    }


def ensure_certificate_exists(
    cert_dir: Optional[Path] = None,
    hostname: str = "localhost",
    san_ips: Optional[List[str]] = None,
) -> Tuple[str, str, str]:
    """Ensure a self-signed certificate exists, create if not.

    Args:
        cert_dir: Directory to store certificates (default: certs/self_signed)
        hostname: Hostname for Common Name
        san_ips: List of IP addresses for SAN (default: ["127.0.0.1"])

    Returns:
        Tuple of (cert_path, key_path, fingerprint)
    """
    cert_dir = cert_dir or DEFAULT_CERT_DIR
    cert_path = cert_dir / "server.crt"
    key_path = cert_dir / "server.key"

    if san_ips is None:
        san_ips = ["127.0.0.1"]

    if cert_path.exists() and key_path.exists():
        LOGGER.info("Certificate already exists at %s", cert_path)
        fingerprint = get_certificate_fingerprint(str(cert_path))
        return str(cert_path), str(key_path), fingerprint

    LOGGER.info("Generating new self-signed certificate...")

    # Create directory
    cert_dir.mkdir(parents=True, exist_ok=True)

    # Generate certificate
    cert_pem, key_pem = generate_self_signed_cert(
        common_name=hostname,
        san_ips=san_ips,
    )

    # Write files
    with open(cert_path, "wb") as f:
        f.write(cert_pem)
    with open(key_path, "wb") as f:
        f.write(key_pem)

    # Set permissions
    os.chmod(key_path, 0o600)
    os.chmod(cert_path, 0o644)
    os.chmod(cert_dir, 0o700)

    fingerprint = get_certificate_fingerprint(str(cert_path))
    LOGGER.info("Certificate generated: %s", fingerprint)

    return str(cert_path), str(key_path), fingerprint


def regenerate_certificate(
    cert_dir: Optional[Path] = None,
    hostname: str = "localhost",
    san_ips: Optional[List[str]] = None,
) -> Tuple[str, str, str, str]:
    """Regenerate certificate, backing up the old one.

    Args:
        cert_dir: Directory containing certificates
        hostname: Hostname for Common Name
        san_ips: List of IP addresses for SAN

    Returns:
        Tuple of (cert_path, key_path, old_fingerprint, new_fingerprint)
    """
    cert_dir = cert_dir or DEFAULT_CERT_DIR
    cert_path = cert_dir / "server.crt"
    key_path = cert_dir / "server.key"
    backup_dir = cert_dir / "backup"

    if san_ips is None:
        san_ips = ["127.0.0.1"]

    old_fingerprint = ""
    if cert_path.exists():
        old_fingerprint = get_certificate_fingerprint(str(cert_path))

        # Create backup
        backup_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_cert = backup_dir / f"server.crt.{timestamp}"
        backup_key = backup_dir / f"server.key.{timestamp}"

        shutil.copy2(cert_path, backup_cert)
        shutil.copy2(key_path, backup_key)
        LOGGER.info("Backed up old certificate to %s", backup_cert)

        # Clean old backups (keep only 5 most recent)
        _cleanup_old_backups(backup_dir, keep=5)

    # Generate new certificate
    cert_pem, key_pem = generate_self_signed_cert(
        common_name=hostname,
        san_ips=san_ips,
    )

    with open(cert_path, "wb") as f:
        f.write(cert_pem)
    with open(key_path, "wb") as f:
        f.write(key_pem)

    os.chmod(key_path, 0o600)
    os.chmod(cert_path, 0o644)

    new_fingerprint = get_certificate_fingerprint(str(cert_path))

    LOGGER.info(
        "Certificate regenerated: old=%s, new=%s",
        old_fingerprint or "(none)",
        new_fingerprint,
    )

    return str(cert_path), str(key_path), old_fingerprint, new_fingerprint


def revoke_certificate(cert_dir: Optional[Path] = None) -> bool:
    """Revoke (delete) the current certificate.

    Args:
        cert_dir: Directory containing certificates

    Returns:
        True if certificate was deleted, False if it didn't exist
    """
    cert_dir = cert_dir or DEFAULT_CERT_DIR
    cert_path = cert_dir / "server.crt"
    key_path = cert_dir / "server.key"

    deleted = False
    if cert_path.exists():
        fingerprint = get_certificate_fingerprint(str(cert_path))
        cert_path.unlink()
        LOGGER.warning("[REVOKED] Certificate deleted: %s", fingerprint)
        deleted = True

    if key_path.exists():
        key_path.unlink()
        deleted = True

    return deleted


def _cleanup_old_backups(backup_dir: Path, keep: int = 5) -> None:
    """Remove old backup files, keeping only the most recent ones.

    Args:
        backup_dir: Directory containing backup files
        keep: Number of backup sets to keep
    """
    # Get all backup cert files
    backup_files = sorted(backup_dir.glob("server.crt.*"), reverse=True)

    # Remove old backups
    for old_cert in backup_files[keep:]:
        old_key = backup_dir / old_cert.name.replace("server.crt.", "server.key.")
        try:
            old_cert.unlink()
            if old_key.exists():
                old_key.unlink()
            LOGGER.info("Removed old backup: %s", old_cert.name)
        except OSError as e:
            LOGGER.warning("Failed to remove old backup %s: %s", old_cert.name, e)


def print_certificate_banner(
    cert_path: str,
    server_url: str,
    version: str = "1.0.0",
) -> None:
    """Print a banner with certificate information for server startup.

    Args:
        cert_path: Path to the certificate file
        server_url: Server URL (e.g., https://192.168.11.110:8443)
        version: Server version string
    """
    try:
        fingerprint = get_certificate_fingerprint(cert_path)
    except Exception as e:
        LOGGER.error("Failed to get certificate fingerprint: %s", e)
        return

    banner = f"""
════════════════════════════════════════════════════════════════
 RemotePrompt Server v{version}

 Server URL: {server_url}

 Certificate Fingerprint (SHA256):
 {fingerprint}

 ※ クライアント接続時にこの値と一致することを確認してください
════════════════════════════════════════════════════════════════
"""
    print(banner)
    LOGGER.info("Server started with certificate: %s", fingerprint)
