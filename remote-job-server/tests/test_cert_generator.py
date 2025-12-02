"""Tests for cert_generator module.

Tests certificate generation, fingerprint calculation, and certificate management functions.
"""
import os
import tempfile
from pathlib import Path

import pytest

from cert_generator import (
    generate_self_signed_cert,
    get_certificate_fingerprint,
    get_certificate_info,
    ensure_certificate_exists,
    regenerate_certificate,
    revoke_certificate,
)


class TestGenerateSelfSignedCert:
    """Tests for generate_self_signed_cert function."""

    def test_generates_valid_certificate_and_key(self):
        """Given valid parameters, should generate PEM-formatted certificate and key."""
        # Given
        common_name = "192.168.1.100"
        san_ips = ["192.168.1.100", "127.0.0.1"]

        # When
        cert_pem, key_pem = generate_self_signed_cert(common_name, san_ips)

        # Then
        assert cert_pem.startswith(b"-----BEGIN CERTIFICATE-----")
        assert cert_pem.endswith(b"-----END CERTIFICATE-----\n")
        assert key_pem.startswith(b"-----BEGIN RSA PRIVATE KEY-----")
        assert key_pem.endswith(b"-----END RSA PRIVATE KEY-----\n")

    def test_generates_certificate_with_correct_common_name(self):
        """Given a common name, should include it in the certificate subject."""
        # Given
        common_name = "test.example.com"
        san_ips = ["192.168.1.1"]

        # When
        cert_pem, _ = generate_self_signed_cert(common_name, san_ips)

        # Then
        from cryptography import x509
        cert = x509.load_pem_x509_certificate(cert_pem)
        cn_attrs = [attr.value for attr in cert.subject if attr.oid == x509.oid.NameOID.COMMON_NAME]
        assert common_name in cn_attrs

    def test_generates_certificate_with_san_ips(self):
        """Given SAN IPs, should include them in Subject Alternative Names."""
        # Given
        common_name = "localhost"
        san_ips = ["192.168.1.100", "10.0.0.1", "127.0.0.1"]

        # When
        cert_pem, _ = generate_self_signed_cert(common_name, san_ips)

        # Then
        from cryptography import x509
        from ipaddress import ip_address
        cert = x509.load_pem_x509_certificate(cert_pem)
        san_ext = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName)
        san_values = [str(name.value) for name in san_ext.value]
        for ip in san_ips:
            assert ip in san_values

    def test_generates_certificate_with_dns_names_in_san(self):
        """Given DNS names in SAN list, should include them as DNS names."""
        # Given
        common_name = "localhost"
        san_ips = ["192.168.1.1", "myserver.local"]

        # When
        cert_pem, _ = generate_self_signed_cert(common_name, san_ips)

        # Then
        from cryptography import x509
        cert = x509.load_pem_x509_certificate(cert_pem)
        san_ext = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName)
        dns_names = san_ext.value.get_values_for_type(x509.DNSName)
        assert "myserver.local" in dns_names

    def test_generates_certificate_with_custom_validity(self):
        """Given custom validity days, should set correct expiration."""
        # Given
        common_name = "localhost"
        san_ips = ["127.0.0.1"]
        valid_days = 365

        # When
        cert_pem, _ = generate_self_signed_cert(common_name, san_ips, valid_days=valid_days)

        # Then
        from cryptography import x509
        from datetime import datetime, timezone, timedelta
        cert = x509.load_pem_x509_certificate(cert_pem)
        expected_expiry = datetime.now(timezone.utc) + timedelta(days=valid_days)
        # Allow 1 minute tolerance
        assert abs((cert.not_valid_after_utc - expected_expiry).total_seconds()) < 60

    def test_generates_self_signed_certificate(self):
        """Generated certificate should be self-signed (issuer == subject)."""
        # Given
        common_name = "localhost"
        san_ips = ["127.0.0.1"]

        # When
        cert_pem, _ = generate_self_signed_cert(common_name, san_ips)

        # Then
        from cryptography import x509
        cert = x509.load_pem_x509_certificate(cert_pem)
        assert cert.subject == cert.issuer


class TestGetCertificateFingerprint:
    """Tests for get_certificate_fingerprint function."""

    def test_returns_sha256_fingerprint_format(self):
        """Should return fingerprint in 'SHA256:XX:XX:...' format."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_path = Path(tmpdir) / "test.crt"
            cert_pem, _ = generate_self_signed_cert("localhost", ["127.0.0.1"])
            cert_path.write_bytes(cert_pem)

            # When
            fingerprint = get_certificate_fingerprint(str(cert_path))

            # Then
            assert fingerprint.startswith("SHA256:")
            parts = fingerprint.replace("SHA256:", "").split(":")
            assert len(parts) == 32  # SHA256 = 32 bytes = 64 hex chars = 32 pairs
            for part in parts:
                assert len(part) == 2
                assert all(c in "0123456789ABCDEF" for c in part)

    def test_same_certificate_returns_same_fingerprint(self):
        """Same certificate should always return the same fingerprint."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_path = Path(tmpdir) / "test.crt"
            cert_pem, _ = generate_self_signed_cert("localhost", ["127.0.0.1"])
            cert_path.write_bytes(cert_pem)

            # When
            fp1 = get_certificate_fingerprint(str(cert_path))
            fp2 = get_certificate_fingerprint(str(cert_path))

            # Then
            assert fp1 == fp2

    def test_different_certificates_return_different_fingerprints(self):
        """Different certificates should return different fingerprints."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert1_path = Path(tmpdir) / "test1.crt"
            cert2_path = Path(tmpdir) / "test2.crt"

            cert1_pem, _ = generate_self_signed_cert("server1", ["192.168.1.1"])
            cert2_pem, _ = generate_self_signed_cert("server2", ["192.168.1.2"])

            cert1_path.write_bytes(cert1_pem)
            cert2_path.write_bytes(cert2_pem)

            # When
            fp1 = get_certificate_fingerprint(str(cert1_path))
            fp2 = get_certificate_fingerprint(str(cert2_path))

            # Then
            assert fp1 != fp2


class TestGetCertificateInfo:
    """Tests for get_certificate_info function."""

    def test_returns_certificate_details(self):
        """Should return dictionary with certificate information."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_path = Path(tmpdir) / "test.crt"
            cert_pem, _ = generate_self_signed_cert("192.168.1.100", ["192.168.1.100"])
            cert_path.write_bytes(cert_pem)

            # When
            info = get_certificate_info(str(cert_path))

            # Then
            assert "fingerprint" in info
            assert "common_name" in info
            assert "valid_from" in info
            assert "valid_until" in info
            assert "issuer" in info
            assert "serial_number" in info
            assert "is_self_signed" in info

    def test_returns_correct_common_name(self):
        """Should return the correct common name."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_path = Path(tmpdir) / "test.crt"
            cert_pem, _ = generate_self_signed_cert("myserver.local", ["192.168.1.1"])
            cert_path.write_bytes(cert_pem)

            # When
            info = get_certificate_info(str(cert_path))

            # Then
            assert info["common_name"] == "myserver.local"

    def test_identifies_self_signed_certificate(self):
        """Should correctly identify self-signed certificates."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_path = Path(tmpdir) / "test.crt"
            cert_pem, _ = generate_self_signed_cert("localhost", ["127.0.0.1"])
            cert_path.write_bytes(cert_pem)

            # When
            info = get_certificate_info(str(cert_path))

            # Then
            assert info["is_self_signed"] is True


class TestEnsureCertificateExists:
    """Tests for ensure_certificate_exists function."""

    def test_creates_certificate_if_not_exists(self):
        """Should create certificate and key files if they don't exist."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_dir = Path(tmpdir) / "certs"

            # When
            cert_path, key_path, fingerprint = ensure_certificate_exists(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # Then
            assert Path(cert_path).exists()
            assert Path(key_path).exists()
            assert fingerprint.startswith("SHA256:")

    def test_returns_existing_certificate(self):
        """Should return existing certificate without regenerating."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_dir = Path(tmpdir) / "certs"

            # Create first certificate
            _, _, fp1 = ensure_certificate_exists(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # When - call again
            _, _, fp2 = ensure_certificate_exists(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # Then
            assert fp1 == fp2  # Same fingerprint means same certificate

    def test_sets_correct_file_permissions(self):
        """Should set restrictive permissions on key file."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_dir = Path(tmpdir) / "certs"

            # When
            cert_path, key_path, _ = ensure_certificate_exists(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # Then
            key_mode = os.stat(key_path).st_mode & 0o777
            cert_mode = os.stat(cert_path).st_mode & 0o777
            assert key_mode == 0o600  # Private key: owner read/write only
            assert cert_mode == 0o644  # Certificate: owner rw, others read


class TestRegenerateCertificate:
    """Tests for regenerate_certificate function."""

    def test_regenerates_certificate_with_backup(self):
        """Should regenerate certificate and backup the old one."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_dir = Path(tmpdir) / "certs"

            # Create initial certificate
            _, _, old_fp = ensure_certificate_exists(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # When
            cert_path, key_path, returned_old_fp, new_fp = regenerate_certificate(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # Then
            assert returned_old_fp == old_fp
            assert new_fp != old_fp
            assert Path(cert_path).exists()
            assert Path(key_path).exists()

    def test_creates_backup_files(self):
        """Should create backup files in backup directory."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_dir = Path(tmpdir) / "certs"

            # Create initial certificate
            ensure_certificate_exists(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # When
            regenerate_certificate(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # Then
            backup_dir = cert_dir / "backup"
            assert backup_dir.exists()
            backup_certs = list(backup_dir.glob("server.crt.*"))
            backup_keys = list(backup_dir.glob("server.key.*"))
            assert len(backup_certs) == 1
            assert len(backup_keys) == 1


class TestRevokeCertificate:
    """Tests for revoke_certificate function."""

    def test_deletes_certificate_files(self):
        """Should delete certificate and key files."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_dir = Path(tmpdir) / "certs"

            # Create certificate
            cert_path, key_path, _ = ensure_certificate_exists(
                cert_dir=cert_dir,
                hostname="localhost",
                san_ips=["127.0.0.1"]
            )

            # When
            result = revoke_certificate(cert_dir=cert_dir)

            # Then
            assert result is True
            assert not Path(cert_path).exists()
            assert not Path(key_path).exists()

    def test_returns_false_if_no_certificate(self):
        """Should return False if no certificate exists."""
        # Given
        with tempfile.TemporaryDirectory() as tmpdir:
            cert_dir = Path(tmpdir) / "certs"
            cert_dir.mkdir(parents=True)

            # When
            result = revoke_certificate(cert_dir=cert_dir)

            # Then
            assert result is False


class TestBoundaryValues:
    """Boundary value tests."""

    def test_empty_san_list(self):
        """Should handle empty SAN list."""
        # Given
        common_name = "localhost"
        san_ips = []

        # When
        cert_pem, key_pem = generate_self_signed_cert(common_name, san_ips)

        # Then - should still generate valid certificate
        assert cert_pem.startswith(b"-----BEGIN CERTIFICATE-----")

    def test_minimum_validity_days(self):
        """Should handle minimum validity (1 day)."""
        # Given
        common_name = "localhost"
        san_ips = ["127.0.0.1"]
        valid_days = 1

        # When
        cert_pem, _ = generate_self_signed_cert(common_name, san_ips, valid_days=valid_days)

        # Then
        from cryptography import x509
        cert = x509.load_pem_x509_certificate(cert_pem)
        validity_duration = cert.not_valid_after_utc - cert.not_valid_before_utc
        assert validity_duration.days == 1

    def test_multiple_san_ips(self):
        """Should handle many SAN IPs."""
        # Given
        common_name = "localhost"
        san_ips = [f"192.168.1.{i}" for i in range(1, 11)]  # 10 IPs

        # When
        cert_pem, _ = generate_self_signed_cert(common_name, san_ips)

        # Then
        from cryptography import x509
        cert = x509.load_pem_x509_certificate(cert_pem)
        san_ext = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName)
        assert len(list(san_ext.value)) == 10
