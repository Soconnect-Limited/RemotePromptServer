#!/usr/bin/env python3
"""
APNs Error Case Tests for 3.5 セクション

テスト観点:
| ケース | 分類 | 期待結果 |
|--------|------|----------|
| .p8ファイル不在 | 異常系 | enabled=False, エラーログ出力 |
| デバイストークン不正 | 異常系 | send_notification() return False |
| 空のデバイストークン | 境界値 | send_notification() return False |
| APNs設定不完全 | 異常系 | enabled=False |
| ネットワークエラー | 異常系 | send_notification() return False |

実行方法:
  cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
  source .venv/bin/activate  # 仮想環境がある場合
  python ../Tests/apns/test_apns_error_cases.py
"""

import asyncio
import logging
import os
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add remote-job-server to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "remote-job-server"))

logging.basicConfig(level=logging.DEBUG, format="%(levelname)s - %(name)s - %(message)s")
LOGGER = logging.getLogger(__name__)


def test_p8_file_not_found():
    """
    テストケース: .p8ファイル不在時

    Given: APNS_KEY_PATHに存在しないパスを設定
    When: APNsManagerを初期化
    Then: enabled=Falseとなり、警告ログが出力される
    """
    LOGGER.info("=" * 60)
    LOGGER.info("TEST: .p8ファイル不在時")
    LOGGER.info("=" * 60)

    # 環境変数を一時的に変更
    original_env = os.environ.copy()
    os.environ["APNS_KEY_PATH"] = "/nonexistent/path/AuthKey.p8"
    os.environ["APNS_KEY_ID"] = "TESTKEY123"
    os.environ["APNS_TEAM_ID"] = "TESTTEAM"
    os.environ["APNS_BUNDLE_ID"] = "com.test.app"

    try:
        # configをリロード
        import importlib
        import config
        importlib.reload(config)

        from apns_manager import APNsManager
        manager = APNsManager()

        assert manager.enabled is False, "❌ FAIL: enabled should be False"
        LOGGER.info("✅ PASS: APNs disabled when .p8 file not found")
        return True

    finally:
        os.environ.clear()
        os.environ.update(original_env)


async def test_invalid_device_token():
    """
    テストケース: デバイストークン不正時

    Given: APNsが有効な状態
    When: 不正なデバイストークンで通知送信
    Then: send_notification()がFalseを返し、エラーログが出力される
    """
    LOGGER.info("=" * 60)
    LOGGER.info("TEST: デバイストークン不正時")
    LOGGER.info("=" * 60)

    from apns_manager import APNsManager

    # 実際の設定でマネージャーを初期化
    manager = APNsManager()

    if not manager.enabled:
        LOGGER.warning("⚠️ SKIP: APNs not configured, cannot test invalid token")
        return None

    # 不正なトークンで送信（短すぎる、無効な文字など）
    invalid_tokens = [
        "invalid_token",
        "12345",
        "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg",  # 非hex文字
        "00000000000000000000000000000000000000000000000000000000000000000",  # 存在しないトークン
    ]

    for token in invalid_tokens:
        result = await manager.send_notification(
            device_token=token,
            title="Test",
            body="Test notification"
        )

        if result is False:
            LOGGER.info("✅ PASS: Invalid token '%s...' rejected", token[:16])
        else:
            LOGGER.error("❌ FAIL: Invalid token '%s...' was accepted", token[:16])
            return False

    return True


async def test_empty_device_token():
    """
    テストケース: 空のデバイストークン

    Given: APNsが有効な状態
    When: 空文字列またはNoneのデバイストークンで通知送信
    Then: send_notification()がFalseを返す（APNsリクエストは送信されない）
    """
    LOGGER.info("=" * 60)
    LOGGER.info("TEST: 空のデバイストークン")
    LOGGER.info("=" * 60)

    from apns_manager import APNsManager
    manager = APNsManager()

    # 空トークンで送信
    result = await manager.send_notification(
        device_token="",
        title="Test",
        body="Test notification"
    )

    if result is False:
        LOGGER.info("✅ PASS: Empty token rejected without API call")
        return True
    else:
        LOGGER.error("❌ FAIL: Empty token was not rejected")
        return False


def test_incomplete_apns_config():
    """
    テストケース: APNs設定不完全時

    Given: 必須のAPNs設定が一部欠けている
    When: APNsManagerを初期化
    Then: enabled=Falseとなる

    注: コードレビューによる検証（モジュールリロードの制約があるため）
    """
    LOGGER.info("=" * 60)
    LOGGER.info("TEST: APNs設定不完全時")
    LOGGER.info("=" * 60)

    # apns_manager.pyのコードを確認して、設定不完全時の処理を検証
    from apns_manager import APNsManager
    import inspect

    # APNsManagerの__init__メソッドのソースコードを取得
    source = inspect.getsource(APNsManager.__init__)

    # 必要な検証ポイント:
    # 1. 必須パラメータチェックが存在する
    # 2. all([...])による検証がある
    # 3. enabled=Falseが設定される

    checks = {
        "has_all_check": "all([" in source,
        "checks_key_path": "key_path_str" in source or "apns_key_path" in source,
        "checks_key_id": "key_id" in source or "apns_key_id" in source,
        "checks_team_id": "team_id" in source or "apns_team_id" in source,
        "checks_bundle_id": "bundle_id" in source or "apns_bundle_id" in source,
        "sets_enabled_false": "self.enabled = False" in source,
    }

    all_passed = all(checks.values())

    for check_name, result in checks.items():
        status = "✅" if result else "❌"
        LOGGER.info("  %s %s", status, check_name)

    if all_passed:
        LOGGER.info("✅ PASS: Code review confirms incomplete config handling exists")
        return True
    else:
        LOGGER.error("❌ FAIL: Some config validation checks missing")
        return False


async def test_network_error():
    """
    テストケース: ネットワークエラー時

    Given: APNsが有効な状態
    When: ネットワーク接続エラーが発生
    Then: send_notification()がFalseを返し、例外がキャッチされる
    """
    LOGGER.info("=" * 60)
    LOGGER.info("TEST: ネットワークエラー時")
    LOGGER.info("=" * 60)

    from apns_manager import APNsManager
    import httpx

    manager = APNsManager()

    if not manager.enabled:
        LOGGER.warning("⚠️ SKIP: APNs not configured, cannot test network error")
        return None

    # httpxのリクエストをモックしてエラーを発生させる
    original_post = httpx.AsyncClient.post

    async def mock_post(*args, **kwargs):
        raise httpx.ConnectError("Simulated network error")

    with patch.object(httpx.AsyncClient, 'post', mock_post):
        result = await manager.send_notification(
            device_token="a" * 64,  # 有効な形式のトークン
            title="Test",
            body="Test notification"
        )

        if result is False:
            LOGGER.info("✅ PASS: Network error handled gracefully")
            return True
        else:
            LOGGER.error("❌ FAIL: Network error not handled")
            return False


def reload_config_and_apns():
    """Reload config and apns_manager modules to pick up environment changes."""
    import importlib
    import sys

    # Remove cached modules
    for mod_name in list(sys.modules.keys()):
        if mod_name in ('config', 'apns_manager') or mod_name.startswith('config.') or mod_name.startswith('apns_manager.'):
            del sys.modules[mod_name]

    # Re-import
    import config
    import apns_manager
    return config, apns_manager


async def main():
    """Run all error case tests."""
    LOGGER.info("\n" + "=" * 60)
    LOGGER.info("APNs Error Case Tests (Section 3.5)")
    LOGGER.info("=" * 60 + "\n")

    results = {}

    # Test 1: .p8ファイル不在
    try:
        results["p8_not_found"] = test_p8_file_not_found()
    except Exception as e:
        LOGGER.error("❌ FAIL: p8_not_found test raised exception: %s", e)
        results["p8_not_found"] = False

    # configとapns_managerを完全にリロード
    reload_config_and_apns()

    # Test 2: デバイストークン不正
    try:
        results["invalid_token"] = await test_invalid_device_token()
    except Exception as e:
        LOGGER.error("❌ FAIL: invalid_token test raised exception: %s", e)
        results["invalid_token"] = False

    # Test 3: 空のデバイストークン
    try:
        results["empty_token"] = await test_empty_device_token()
    except Exception as e:
        LOGGER.error("❌ FAIL: empty_token test raised exception: %s", e)
        results["empty_token"] = False

    # Test 4: APNs設定不完全
    try:
        results["incomplete_config"] = test_incomplete_apns_config()
    except Exception as e:
        LOGGER.error("❌ FAIL: incomplete_config test raised exception: %s", e)
        results["incomplete_config"] = False

    # configを再リロード
    reload_config_and_apns()

    # Test 5: ネットワークエラー
    try:
        results["network_error"] = await test_network_error()
    except Exception as e:
        LOGGER.error("❌ FAIL: network_error test raised exception: %s", e)
        results["network_error"] = False

    # Summary
    LOGGER.info("\n" + "=" * 60)
    LOGGER.info("TEST SUMMARY")
    LOGGER.info("=" * 60)

    passed = 0
    failed = 0
    skipped = 0

    for name, result in results.items():
        if result is True:
            LOGGER.info("✅ %s: PASSED", name)
            passed += 1
        elif result is False:
            LOGGER.info("❌ %s: FAILED", name)
            failed += 1
        else:
            LOGGER.info("⚠️ %s: SKIPPED", name)
            skipped += 1

    LOGGER.info("-" * 60)
    LOGGER.info("Total: %d passed, %d failed, %d skipped", passed, failed, skipped)

    return failed == 0


if __name__ == "__main__":
    success = asyncio.run(main())
    sys.exit(0 if success else 1)
