"""
Bonjour (mDNS/DNS-SD) サービス公開モジュール

ローカルネットワーク上でRemotePromptサーバーを自動検出可能にする。
iOSクライアントはNetServiceBrowserを使用してサーバーを発見できる。

サービスタイプ: _remoteprompt._tcp
"""

import asyncio
import socket
import logging
import threading
from typing import Optional
from zeroconf import ServiceInfo, IPVersion
from zeroconf.asyncio import AsyncZeroconf

logger = logging.getLogger(__name__)


class BonjourPublisher:
    """Bonjourサービス公開クラス（AsyncZeroconf使用）"""

    SERVICE_TYPE = "_remoteprompt._tcp.local."
    SERVICE_NAME_PREFIX = "RemotePrompt Server"

    def __init__(
        self,
        port: int,
        hostname: Optional[str] = None,
        server_name: Optional[str] = None,
        fingerprint: Optional[str] = None,
        ssl_mode: str = "unknown",
    ):
        """
        Args:
            port: サーバーのポート番号
            hostname: ホスト名（Noneの場合は自動取得）
            server_name: サーバー名（mDNS名に使用）
            fingerprint: 証明書フィンガープリント（TXTレコードに含める）
            ssl_mode: SSLモード（commercial/self_signed/auto）
        """
        self.port = port
        self.hostname = hostname or socket.gethostname()
        self.server_name = server_name or self.SERVICE_NAME_PREFIX
        self.fingerprint = fingerprint
        self.ssl_mode = ssl_mode

        self._async_zeroconf: Optional[AsyncZeroconf] = None
        self._service_info: Optional[ServiceInfo] = None
        self._is_registered = False
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def _get_local_ip(self) -> str:
        """ローカルIPアドレスを取得"""
        try:
            # UDPソケットを使用して外部への接続を試み、ローカルIPを取得
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
            return local_ip
        except Exception:
            # フォールバック: localhost
            return "127.0.0.1"

    def _build_service_info(self) -> ServiceInfo:
        """ServiceInfoを構築"""
        local_ip = self._get_local_ip()

        # TXTレコード: クライアントが追加情報を取得できる
        properties = {
            "version": "1.0",
            "ssl_mode": self.ssl_mode,
            "path": "/",
        }

        # フィンガープリントがある場合は追加
        # SHA256フィンガープリントは95文字（32バイト×2 + コロン31個）
        # TXTレコードの各キー/値ペアは255バイト制限だが、fingerprintは収まる
        if self.fingerprint:
            properties["fingerprint"] = self.fingerprint

        # サービス名にホスト名を追加して一意にする
        service_name = f"{self.server_name} on {self.hostname}.{self.SERVICE_TYPE}"

        return ServiceInfo(
            type_=self.SERVICE_TYPE,
            name=service_name,
            addresses=[socket.inet_aton(local_ip)],
            port=self.port,
            properties=properties,
            server=f"{self.hostname}.local.",
        )

    async def start_async(self) -> bool:
        """Bonjourサービスの公開を開始（非同期版）"""
        if self._is_registered:
            logger.warning("Bonjour service is already registered")
            return True

        try:
            self._async_zeroconf = AsyncZeroconf(ip_version=IPVersion.V4Only)
            self._service_info = self._build_service_info()

            logger.info(f"Registering Bonjour service: {self._service_info.name}")
            logger.info(f"  Type: {self.SERVICE_TYPE}")
            logger.info(f"  Port: {self.port}")
            logger.info(f"  IP: {self._get_local_ip()}")

            await self._async_zeroconf.async_register_service(self._service_info)
            self._is_registered = True

            logger.info("Bonjour service registered successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to register Bonjour service: {e}")
            await self._cleanup_async()
            return False

    def start(self) -> bool:
        """Bonjourサービスの公開を開始（同期ラッパー）"""
        if self._is_registered:
            logger.warning("Bonjour service is already registered")
            return True

        try:
            # 既存のイベントループを取得、なければ新規作成
            try:
                loop = asyncio.get_running_loop()
                # イベントループ内から呼ばれている場合は、タスクとしてスケジュール
                asyncio.create_task(self.start_async())
                self._loop = loop
                return True  # 非同期で登録されるため、ここでは True を返す
            except RuntimeError:
                # イベントループがない場合は新規作成して実行
                return asyncio.run(self.start_async())

        except Exception as e:
            logger.error(f"Failed to start Bonjour service: {e}")
            return False

    async def stop_async(self):
        """Bonjourサービスの公開を停止（非同期版）"""
        if not self._is_registered:
            return

        try:
            if self._async_zeroconf and self._service_info:
                logger.info("Unregistering Bonjour service...")
                await self._async_zeroconf.async_unregister_service(self._service_info)
                logger.info("Bonjour service unregistered")
        except Exception as e:
            logger.error(f"Error unregistering Bonjour service: {e}")
        finally:
            await self._cleanup_async()

    def stop(self):
        """Bonjourサービスの公開を停止（同期ラッパー）"""
        if not self._is_registered:
            return

        try:
            try:
                loop = asyncio.get_running_loop()
                # イベントループ内から呼ばれている場合
                asyncio.create_task(self.stop_async())
            except RuntimeError:
                # イベントループがない場合
                asyncio.run(self.stop_async())
        except Exception as e:
            logger.error(f"Error stopping Bonjour service: {e}")

    async def _cleanup_async(self):
        """リソースのクリーンアップ（非同期版）"""
        if self._async_zeroconf:
            try:
                await self._async_zeroconf.async_close()
            except Exception:
                pass
            self._async_zeroconf = None
        self._service_info = None
        self._is_registered = False

    def update_fingerprint(self, fingerprint: str):
        """証明書フィンガープリントを更新（サービス再登録）"""
        if not self._is_registered:
            self.fingerprint = fingerprint
            return

        # 一度停止して再登録
        self.stop()
        self.fingerprint = fingerprint
        self.start()

    @property
    def is_running(self) -> bool:
        """サービスが稼働中かどうか"""
        return self._is_registered


# グローバルインスタンス（main.pyから使用）
_publisher: Optional[BonjourPublisher] = None


def get_publisher() -> Optional[BonjourPublisher]:
    """現在のBonjourPublisherインスタンスを取得"""
    return _publisher


async def start_bonjour_service_async(
    port: int,
    hostname: Optional[str] = None,
    server_name: Optional[str] = None,
    fingerprint: Optional[str] = None,
    ssl_mode: str = "unknown",
) -> bool:
    """Bonjourサービスを開始（非同期版、グローバル管理）"""
    global _publisher

    if _publisher and _publisher.is_running:
        logger.warning("Bonjour service is already running")
        return True

    _publisher = BonjourPublisher(
        port=port,
        hostname=hostname,
        server_name=server_name,
        fingerprint=fingerprint,
        ssl_mode=ssl_mode,
    )
    return await _publisher.start_async()


def start_bonjour_service(
    port: int,
    hostname: Optional[str] = None,
    server_name: Optional[str] = None,
    fingerprint: Optional[str] = None,
    ssl_mode: str = "unknown",
) -> bool:
    """Bonjourサービスを開始（同期版、グローバル管理）"""
    global _publisher

    if _publisher and _publisher.is_running:
        logger.warning("Bonjour service is already running")
        return True

    _publisher = BonjourPublisher(
        port=port,
        hostname=hostname,
        server_name=server_name,
        fingerprint=fingerprint,
        ssl_mode=ssl_mode,
    )
    return _publisher.start()


async def stop_bonjour_service_async():
    """Bonjourサービスを停止（非同期版、グローバル管理）"""
    global _publisher

    if _publisher:
        await _publisher.stop_async()
        _publisher = None


def stop_bonjour_service():
    """Bonjourサービスを停止（同期版、グローバル管理）"""
    global _publisher

    if _publisher:
        _publisher.stop()
        _publisher = None


def update_bonjour_fingerprint(fingerprint: str):
    """Bonjourサービスのフィンガープリントを更新"""
    if _publisher:
        _publisher.update_fingerprint(fingerprint)
