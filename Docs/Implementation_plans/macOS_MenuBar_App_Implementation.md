# macOS メニューバー常駐アプリ実装計画書

## 概要

RemotePromptサーバーをmacOSメニューバー常駐アプリとしてバイナリ化し、GUIから設定・起動・停止を行えるようにする。

### 目的

1. **ユーザビリティ向上**: ターミナルを開かずにサーバー管理
2. **起動簡略化**: ログイン時自動起動オプション
3. **設定UI**: GUI経由でSSL_MODE、ポート、APIキー等を設定
4. **配布簡素化**: 単一の.appバンドルとして配布可能

### 技術スタック

| 項目 | 採用技術 | 理由 |
|------|----------|------|
| メニューバーUI | **rumps** | シンプル、PyObjC不要、デコレータベース |
| バイナリ化 | **py2app** | macOS専用で最適化、rumpsと相性良好 |
| 設定永続化 | **JSON + Application Support** | シンプル、外部依存なし |
| サーバー | **Uvicorn** (既存) | 現行アーキテクチャを維持 |

### 参考リソース

- [GitHub - jaredks/rumps](https://github.com/jaredks/rumps)
- [Create a macOS Menu Bar App with Python (Camillo Visini)](https://camillovisini.com/coding/create-macos-menu-bar-app-pomodoro)
- [rumps - PyPI](https://pypi.org/project/rumps/)

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                    RemotePrompt.app                         │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────────────────────┐ │
│  │   MenuBar UI     │  │       Background Server          │ │
│  │   (rumps)        │  │       (Uvicorn + FastAPI)        │ │
│  │                  │  │                                  │ │
│  │  ・起動/停止     │──│  ・既存 main.py                  │ │
│  │  ・ステータス表示│  │  ・SSL/TLS 証明書                │ │
│  │  ・設定画面     │  │  ・Bonjour                       │ │
│  │  ・ログ表示     │  │  ・APNs                          │ │
│  └──────────────────┘  └──────────────────────────────────┘ │
│                              │                              │
│  ┌───────────────────────────┴─────────────────────────────┐│
│  │                Configuration Manager                    ││
│  │  ~/Library/Application Support/RemotePrompt/config.json ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1: プロジェクト構造とメニューバー骨格

### 1.1 ディレクトリ構造作成

- [ ] `remote-job-server/menubar/` ディレクトリ作成
- [ ] `remote-job-server/menubar/__init__.py` 作成（空ファイル）
- [ ] `remote-job-server/menubar/app.py` 作成（メインアプリケーション）
- [ ] `remote-job-server/menubar/config_manager.py` 作成（設定管理）
- [ ] `remote-job-server/menubar/server_controller.py` 作成（サーバー起動/停止）
- [ ] `remote-job-server/menubar/resources/` ディレクトリ作成
- [ ] `remote-job-server/menubar/resources/icon.png` アイコン配置（16x16, 32x32）
- [ ] `remote-job-server/menubar/resources/icon_running.png` 実行中アイコン
- [ ] `remote-job-server/menubar/resources/icon_stopped.png` 停止中アイコン
- [ ] `remote-job-server/menubar/resources/icon_error.png` エラー時アイコン

### 1.2 依存ライブラリ追加

- [ ] `remote-job-server/requirements-menubar.txt` 作成
  ```
  rumps>=0.4.0
  py2app>=0.28.0
  ```
- [ ] `pip install -r requirements-menubar.txt` 実行確認
- [ ] インストール成功確認

### 1.3 rumps基本アプリケーション作成

- [ ] `menubar/app.py` にクラス骨格作成
  ```python
  import rumps

  class RemotePromptApp(rumps.App):
      def __init__(self):
          super().__init__(
              name="RemotePrompt",
              title="RP",  # メニューバーに表示するテキスト
              icon="resources/icon_stopped.png",
              quit_button="終了"
          )
          # メニュー項目設定
          self.menu = [
              rumps.MenuItem("サーバー起動", callback=self.start_server),
              rumps.MenuItem("サーバー停止", callback=self.stop_server),
              None,  # セパレータ
              rumps.MenuItem("設定...", callback=self.open_settings),
              rumps.MenuItem("ログを表示", callback=self.show_logs),
              None,
              # 終了ボタンは自動で追加される
          ]

      def start_server(self, sender):
          pass  # Phase 2で実装

      def stop_server(self, sender):
          pass  # Phase 2で実装

      def open_settings(self, sender):
          pass  # Phase 3で実装

      def show_logs(self, sender):
          pass  # Phase 4で実装

  if __name__ == "__main__":
      RemotePromptApp().run()
  ```
- [ ] `python menubar/app.py` で起動テスト
- [ ] メニューバーにアイコン表示確認
- [ ] 各メニュー項目のクリック反応確認
- [ ] 「終了」で正常終了確認

### 1.4 アイコン作成

- [ ] 16x16 PNG アイコン作成（停止時: グレー）
- [ ] 16x16 PNG アイコン作成（実行中: 緑）
- [ ] 16x16 PNG アイコン作成（エラー: 赤）
- [ ] @2x バージョン作成（32x32）
- [ ] アイコンファイルの配置確認

---

## Phase 2: サーバー制御機能

### 2.1 設定マネージャー作成

- [ ] `menubar/config_manager.py` 実装
  ```python
  import json
  import os
  from pathlib import Path
  from typing import Any, Dict, Optional

  class ConfigManager:
      DEFAULT_CONFIG = {
          "ssl_mode": "auto",
          "ssl_auto_fallback_enabled": False,
          "server_port": 8443,
          "server_hostname": "localhost",
          "server_san_ips": "127.0.0.1,192.168.11.110",
          "api_key": "",
          "bonjour_enabled": True,
          "bonjour_service_name": "RemotePrompt Server",
          "auto_start": False,
          "log_level": "INFO",
          # APNs設定
          "apns_key_id": "",
          "apns_team_id": "",
          "apns_key_path": "",
          "apns_bundle_id": "",
          "apns_environment": "sandbox",
      }

      def __init__(self):
          self.config_dir = self._get_config_dir()
          self.config_path = self.config_dir / "config.json"
          self._config: Dict[str, Any] = {}
          self._load()

      def _get_config_dir(self) -> Path:
          """Get Application Support directory."""
          home = Path.home()
          app_support = home / "Library" / "Application Support" / "RemotePrompt"
          app_support.mkdir(parents=True, exist_ok=True)
          return app_support

      def _load(self) -> None:
          """Load config from file or create default."""
          if self.config_path.exists():
              with open(self.config_path, "r") as f:
                  self._config = json.load(f)
              # マージ: 新規設定項目のデフォルト値を追加
              for key, default in self.DEFAULT_CONFIG.items():
                  if key not in self._config:
                      self._config[key] = default
          else:
              self._config = self.DEFAULT_CONFIG.copy()
              self._save()

      def _save(self) -> None:
          """Save config to file."""
          with open(self.config_path, "w") as f:
              json.dump(self._config, f, indent=2, ensure_ascii=False)

      def get(self, key: str, default: Any = None) -> Any:
          return self._config.get(key, default)

      def set(self, key: str, value: Any) -> None:
          self._config[key] = value
          self._save()

      def get_all(self) -> Dict[str, Any]:
          return self._config.copy()

      def to_env_dict(self) -> Dict[str, str]:
          """Convert config to environment variables format."""
          return {
              "SSL_MODE": self._config.get("ssl_mode", "auto"),
              "SSL_AUTO_FALLBACK_ENABLED": str(self._config.get("ssl_auto_fallback_enabled", False)).lower(),
              "SERVER_PORT": str(self._config.get("server_port", 8443)),
              "SERVER_HOSTNAME": self._config.get("server_hostname", "localhost"),
              "SERVER_SAN_IPS": self._config.get("server_san_ips", "127.0.0.1"),
              "API_KEY": self._config.get("api_key", ""),
              "BONJOUR_ENABLED": str(self._config.get("bonjour_enabled", True)).lower(),
              "BONJOUR_SERVICE_NAME": self._config.get("bonjour_service_name", "RemotePrompt Server"),
              "LOG_LEVEL": self._config.get("log_level", "INFO"),
              "APNS_KEY_ID": self._config.get("apns_key_id", ""),
              "APNS_TEAM_ID": self._config.get("apns_team_id", ""),
              "APNS_KEY_PATH": self._config.get("apns_key_path", ""),
              "APNS_BUNDLE_ID": self._config.get("apns_bundle_id", ""),
              "APNS_ENVIRONMENT": self._config.get("apns_environment", "sandbox"),
          }
  ```
- [ ] ConfigManager単体テスト作成
- [ ] デフォルト設定ファイル生成確認
- [ ] 設定読み込み/保存確認
- [ ] `~/Library/Application Support/RemotePrompt/config.json` 確認

### 2.2 サーバーコントローラー作成

- [ ] `menubar/server_controller.py` 実装
  ```python
  import asyncio
  import logging
  import os
  import signal
  import subprocess
  import sys
  import threading
  from pathlib import Path
  from typing import Callable, Optional

  class ServerController:
      def __init__(self, config_manager):
          self.config = config_manager
          self.process: Optional[subprocess.Popen] = None
          self._status_callback: Optional[Callable[[str], None]] = None
          self._log_callback: Optional[Callable[[str], None]] = None
          self._log_reader_thread: Optional[threading.Thread] = None
          self._stop_event = threading.Event()

      @property
      def is_running(self) -> bool:
          return self.process is not None and self.process.poll() is None

      def set_status_callback(self, callback: Callable[[str], None]) -> None:
          self._status_callback = callback

      def set_log_callback(self, callback: Callable[[str], None]) -> None:
          self._log_callback = callback

      def _get_server_path(self) -> Path:
          """Get path to server directory."""
          # .app内からの相対パス or 開発時のパス
          if getattr(sys, 'frozen', False):
              # py2appでバンドルされた場合
              base = Path(sys.executable).parent.parent / "Resources"
          else:
              # 開発時
              base = Path(__file__).parent.parent
          return base

      def start(self) -> bool:
          """Start the server process."""
          if self.is_running:
              return True

          server_path = self._get_server_path()
          env = os.environ.copy()
          env.update(self.config.to_env_dict())

          # SSL証明書パスの設定
          ssl_mode = self.config.get("ssl_mode", "auto")
          port = self.config.get("server_port", 8443)

          # Uvicornコマンド構築
          cmd = [
              sys.executable,
              "-m", "uvicorn",
              "main:app",
              "--host", "0.0.0.0",
              "--port", str(port),
          ]

          # SSL証明書の追加
          cert_path, key_path = self._get_ssl_paths()
          if cert_path and key_path:
              cmd.extend(["--ssl-certfile", cert_path])
              cmd.extend(["--ssl-keyfile", key_path])

          try:
              self._stop_event.clear()
              self.process = subprocess.Popen(
                  cmd,
                  cwd=str(server_path),
                  env=env,
                  stdout=subprocess.PIPE,
                  stderr=subprocess.STDOUT,
                  bufsize=1,
                  universal_newlines=True,
              )

              # ログ読み取りスレッド開始
              self._log_reader_thread = threading.Thread(
                  target=self._read_logs,
                  daemon=True
              )
              self._log_reader_thread.start()

              if self._status_callback:
                  self._status_callback("running")
              return True

          except Exception as e:
              if self._status_callback:
                  self._status_callback("error")
              if self._log_callback:
                  self._log_callback(f"Error starting server: {e}")
              return False

      def stop(self) -> bool:
          """Stop the server process."""
          if not self.is_running:
              return True

          try:
              self._stop_event.set()
              self.process.terminate()
              try:
                  self.process.wait(timeout=5)
              except subprocess.TimeoutExpired:
                  self.process.kill()
                  self.process.wait()

              self.process = None
              if self._status_callback:
                  self._status_callback("stopped")
              return True

          except Exception as e:
              if self._log_callback:
                  self._log_callback(f"Error stopping server: {e}")
              return False

      def _read_logs(self) -> None:
          """Read logs from server process."""
          if not self.process or not self.process.stdout:
              return

          try:
              for line in iter(self.process.stdout.readline, ''):
                  if self._stop_event.is_set():
                      break
                  if line and self._log_callback:
                      self._log_callback(line.rstrip())
          except Exception:
              pass

      def _get_ssl_paths(self) -> tuple:
          """Get SSL certificate paths based on config."""
          ssl_mode = self.config.get("ssl_mode", "auto")
          server_path = self._get_server_path()

          if ssl_mode == "commercial":
              cert = server_path / "certs/config/live/remoteprompt.soconnect.co.jp/fullchain.pem"
              key = server_path / "certs/config/live/remoteprompt.soconnect.co.jp/privkey.pem"
          else:
              cert = server_path / "certs/self_signed/server.crt"
              key = server_path / "certs/self_signed/server.key"

          if cert.exists() and key.exists():
              return str(cert), str(key)
          return None, None

      def get_health(self) -> Optional[dict]:
          """Check server health via API."""
          import urllib.request
          import json
          import ssl

          if not self.is_running:
              return None

          port = self.config.get("server_port", 8443)
          url = f"https://localhost:{port}/health"

          ctx = ssl.create_default_context()
          ctx.check_hostname = False
          ctx.verify_mode = ssl.CERT_NONE

          try:
              with urllib.request.urlopen(url, timeout=2, context=ctx) as resp:
                  return json.loads(resp.read().decode())
          except Exception:
              return None
  ```
- [ ] ServerController単体テスト作成
- [ ] 起動/停止動作確認
- [ ] ログ出力確認
- [ ] ヘルスチェック動作確認

### 2.3 メニューバーアプリにサーバー制御統合

- [ ] `app.py` の `start_server` 実装
  ```python
  def start_server(self, sender):
      if self.server.is_running:
          rumps.notification(
              title="RemotePrompt",
              subtitle="",
              message="サーバーは既に起動中です"
          )
          return

      if self.server.start():
          sender.title = "サーバー起動中..."
          self.icon = "resources/icon_running.png"
          rumps.notification(
              title="RemotePrompt",
              subtitle="サーバー起動",
              message="サーバーが起動しました"
          )
      else:
          self.icon = "resources/icon_error.png"
          rumps.notification(
              title="RemotePrompt",
              subtitle="エラー",
              message="サーバーの起動に失敗しました"
          )
  ```
- [ ] `stop_server` 実装
- [ ] サーバーステータス変更時のアイコン更新
- [ ] macOS通知表示確認
- [ ] 起動→停止→再起動のサイクルテスト

### 2.4 ステータスバー表示

- [ ] サーバー状態に応じたタイトル表示
  - 停止中: `RP`
  - 起動中: `RP ●` (緑)
  - エラー: `RP ⚠` (黄)
- [ ] ポート番号表示オプション（設定画面で切替）
- [ ] 接続中クライアント数表示（将来拡張）

---

## Phase 3: 設定画面UI

### 3.1 設定ウィンドウ基本構造

- [ ] `menubar/settings_window.py` 作成
  ```python
  import rumps
  from typing import Callable

  class SettingsWindow:
      def __init__(self, config_manager, on_save: Callable):
          self.config = config_manager
          self.on_save = on_save

      def show_ssl_settings(self) -> None:
          """SSL設定ダイアログ表示"""
          current_mode = self.config.get("ssl_mode", "auto")

          # SSL_MODEの選択
          response = rumps.alert(
              title="SSL設定",
              message=f"現在のモード: {current_mode}\n\n選択してください:",
              ok="commercial",
              cancel="auto",
              other="self_signed"
          )

          mode_map = {1: "commercial", 0: "auto", -1: "self_signed"}
          if response in mode_map:
              new_mode = mode_map[response]
              self.config.set("ssl_mode", new_mode)
              rumps.notification("RemotePrompt", "設定保存", f"SSLモードを{new_mode}に変更しました")

      def show_server_settings(self) -> None:
          """サーバー設定ダイアログ表示"""
          # ポート設定
          port_window = rumps.Window(
              title="サーバー設定",
              message="ポート番号:",
              default_text=str(self.config.get("server_port", 8443)),
              ok="保存",
              cancel="キャンセル",
              dimensions=(200, 24)
          )
          response = port_window.run()
          if response.clicked:
              try:
                  port = int(response.text)
                  if 1024 <= port <= 65535:
                      self.config.set("server_port", port)
                      rumps.notification("RemotePrompt", "設定保存", f"ポートを{port}に変更しました")
                  else:
                      rumps.alert("エラー", "ポート番号は1024〜65535の範囲で指定してください")
              except ValueError:
                  rumps.alert("エラー", "有効なポート番号を入力してください")

      def show_hostname_settings(self) -> None:
          """ホスト名設定ダイアログ表示"""
          hostname_window = rumps.Window(
              title="ホスト名設定",
              message="サーバーホスト名:",
              default_text=self.config.get("server_hostname", "localhost"),
              ok="保存",
              cancel="キャンセル",
              dimensions=(300, 24)
          )
          response = hostname_window.run()
          if response.clicked and response.text.strip():
              self.config.set("server_hostname", response.text.strip())

      def show_san_ips_settings(self) -> None:
          """SAN IPs設定ダイアログ表示"""
          san_window = rumps.Window(
              title="SAN IPs設定",
              message="証明書に含めるIPアドレス (カンマ区切り):",
              default_text=self.config.get("server_san_ips", "127.0.0.1"),
              ok="保存",
              cancel="キャンセル",
              dimensions=(300, 24)
          )
          response = san_window.run()
          if response.clicked:
              self.config.set("server_san_ips", response.text.strip())

      def show_api_key_settings(self) -> None:
          """APIキー設定ダイアログ表示"""
          api_key_window = rumps.Window(
              title="APIキー設定",
              message="APIキー (空欄でランダム生成):",
              default_text=self.config.get("api_key", ""),
              ok="保存",
              cancel="キャンセル",
              dimensions=(400, 24)
          )
          response = api_key_window.run()
          if response.clicked:
              api_key = response.text.strip()
              if not api_key:
                  import secrets
                  api_key = secrets.token_urlsafe(32)
              self.config.set("api_key", api_key)
              rumps.notification("RemotePrompt", "設定保存", "APIキーを更新しました")

      def show_bonjour_settings(self) -> None:
          """Bonjour設定ダイアログ表示"""
          enabled = self.config.get("bonjour_enabled", True)
          response = rumps.alert(
              title="Bonjour設定",
              message=f"現在: {'有効' if enabled else '無効'}\n\nBonjour検出を切り替えますか？",
              ok="有効にする",
              cancel="無効にする"
          )
          self.config.set("bonjour_enabled", response == 1)
  ```
- [ ] 設定ウィンドウ表示確認
- [ ] 各設定項目の編集確認
- [ ] 設定保存後の反映確認

### 3.2 設定サブメニュー構築

- [ ] `app.py` のメニュー構造を拡張
  ```python
  self.menu = [
      rumps.MenuItem("サーバー起動", callback=self.start_server),
      rumps.MenuItem("サーバー停止", callback=self.stop_server),
      None,
      ("設定", [
          rumps.MenuItem("SSL設定...", callback=self.show_ssl_settings),
          rumps.MenuItem("サーバー設定...", callback=self.show_server_settings),
          rumps.MenuItem("ホスト名設定...", callback=self.show_hostname_settings),
          rumps.MenuItem("SAN IPs設定...", callback=self.show_san_ips_settings),
          rumps.MenuItem("APIキー設定...", callback=self.show_api_key_settings),
          rumps.MenuItem("Bonjour設定...", callback=self.show_bonjour_settings),
          None,
          rumps.MenuItem("APNs設定...", callback=self.show_apns_settings),
          None,
          rumps.MenuItem("設定ファイルを開く", callback=self.open_config_file),
      ]),
      rumps.MenuItem("ログを表示", callback=self.show_logs),
      None,
      rumps.MenuItem("ログイン時に起動", callback=self.toggle_auto_start),
      None,
  ]
  ```
- [ ] サブメニュー表示確認
- [ ] 各設定画面への遷移確認

### 3.3 APNs設定画面

- [ ] APNs Key ID入力ダイアログ
- [ ] APNs Team ID入力ダイアログ
- [ ] APNs Key Path選択ダイアログ（ファイル選択）
- [ ] APNs Bundle ID入力ダイアログ
- [ ] APNs Environment選択（sandbox/production）
- [ ] 設定バリデーション（必須項目チェック）

### 3.4 SSL証明書管理画面

- [ ] 証明書ステータス表示
  - [ ] 有効期限表示
  - [ ] 残り日数表示（30日以下で警告色）
  - [ ] 発行者/ドメイン表示
- [ ] Cloudflare DNS設定
  - [ ] APIトークン入力ダイアログ
  - [ ] トークン保存先: `~/Library/Application Support/RemotePrompt/secrets/cloudflare.ini`
  - [ ] トークンバリデーション（Cloudflare API疎通確認）
- [ ] 証明書更新機能
  - [ ] 手動更新ボタン
  - [ ] 自動更新設定（有効/無効）
  - [ ] 自動更新閾値設定（残り○日で更新、デフォルト30日）
  - [ ] 更新時の通知設定
- [ ] 証明書メニュー構造
  ```python
  ("📜 SSL証明書", [
      rumps.MenuItem("有効期限: 2025-02-15 (残り73日)", callback=None),  # 表示のみ
      rumps.MenuItem("ステータス: ✅ 有効", callback=None),  # 表示のみ
      None,
      rumps.MenuItem("今すぐ更新", callback=self.renew_certificate),
      rumps.MenuItem("更新履歴を表示", callback=self.show_cert_history),
      None,
      rumps.MenuItem("☐ 自動更新を有効にする", callback=self.toggle_auto_renew),
      rumps.MenuItem("Cloudflare API設定...", callback=self.show_cloudflare_settings),
  ])
  ```

### 3.5 設定ファイル直接編集

- [ ] `open_config_file` 実装（Finderで開く）
  ```python
  def open_config_file(self, sender):
      import subprocess
      config_path = self.config.config_path
      subprocess.run(["open", "-R", str(config_path)])
  ```
- [ ] 設定ファイルパスのクリップボードコピー機能
- [ ] 設定再読み込み機能

---

## Phase 4: ログ表示機能

### 4.1 ログウィンドウ

- [ ] `menubar/log_viewer.py` 作成
  ```python
  import subprocess
  from pathlib import Path

  class LogViewer:
      def __init__(self, log_path: Path):
          self.log_path = log_path

      def show_in_console(self) -> None:
          """Console.appでログを表示"""
          subprocess.run(["open", "-a", "Console", str(self.log_path)])

      def show_in_terminal(self) -> None:
          """Terminalで tail -f を実行"""
          script = f'tell application "Terminal" to do script "tail -f {self.log_path}"'
          subprocess.run(["osascript", "-e", script])

      def open_log_folder(self) -> None:
          """ログフォルダをFinderで開く"""
          subprocess.run(["open", str(self.log_path.parent)])
  ```
- [ ] Console.appでログ表示確認
- [ ] Terminalでtail確認
- [ ] Finderでログフォルダ表示確認

### 4.2 ログメニュー拡張

- [ ] ログサブメニュー構築
  ```python
  ("ログ", [
      rumps.MenuItem("Console.appで表示", callback=self.show_logs_console),
      rumps.MenuItem("Terminalでtail", callback=self.show_logs_terminal),
      rumps.MenuItem("ログフォルダを開く", callback=self.open_log_folder),
      None,
      rumps.MenuItem("ログをクリア", callback=self.clear_logs),
  ])
  ```
- [ ] 各ログ表示オプション動作確認

---

## Phase 5: SSL証明書管理機能

### 5.1 証明書マネージャー作成

- [ ] `menubar/cert_manager.py` 作成
  ```python
  import subprocess
  import ssl
  import socket
  from datetime import datetime
  from pathlib import Path
  from typing import Optional, Dict, Any

  class CertificateManager:
      """Let's Encrypt証明書の管理クラス"""

      CERT_DIR = Path("/Users/macstudio/Projects/RemotePrompt/remote-job-server/certs")
      DOMAIN = "remoteprompt.soconnect.co.jp"

      def __init__(self, config_manager):
          self.config = config_manager
          self.cloudflare_ini_path = self._get_cloudflare_ini_path()

      def _get_cloudflare_ini_path(self) -> Path:
          """Cloudflare認証情報ファイルのパス"""
          return Path.home() / "Library" / "Application Support" / "RemotePrompt" / "secrets" / "cloudflare.ini"

      def get_cert_info(self) -> Optional[Dict[str, Any]]:
          """証明書の情報を取得"""
          cert_path = self.CERT_DIR / "config" / "live" / self.DOMAIN / "fullchain.pem"
          if not cert_path.exists():
              return None

          try:
              # openssl で証明書情報を取得
              result = subprocess.run(
                  ["openssl", "x509", "-in", str(cert_path), "-noout",
                   "-dates", "-subject", "-issuer"],
                  capture_output=True, text=True
              )

              info = {}
              for line in result.stdout.strip().split('\n'):
                  if line.startswith('notBefore='):
                      info['not_before'] = self._parse_openssl_date(line.split('=')[1])
                  elif line.startswith('notAfter='):
                      info['not_after'] = self._parse_openssl_date(line.split('=')[1])
                  elif line.startswith('subject='):
                      info['subject'] = line.split('=', 1)[1]
                  elif line.startswith('issuer='):
                      info['issuer'] = line.split('=', 1)[1]

              # 残り日数を計算
              if 'not_after' in info:
                  info['days_remaining'] = (info['not_after'] - datetime.now()).days
                  info['is_valid'] = info['days_remaining'] > 0

              return info
          except Exception as e:
              return {'error': str(e)}

      def _parse_openssl_date(self, date_str: str) -> datetime:
          """OpenSSLの日付文字列をパース"""
          # 例: "Nov 19 12:00:00 2025 GMT"
          return datetime.strptime(date_str.strip(), "%b %d %H:%M:%S %Y %Z")

      def is_cloudflare_configured(self) -> bool:
          """Cloudflare APIが設定されているか確認"""
          return self.cloudflare_ini_path.exists()

      def save_cloudflare_token(self, token: str) -> bool:
          """Cloudflare APIトークンを保存"""
          try:
              self.cloudflare_ini_path.parent.mkdir(parents=True, exist_ok=True)
              content = f"# Cloudflare API token\ndns_cloudflare_api_token = {token}\n"
              self.cloudflare_ini_path.write_text(content)
              self.cloudflare_ini_path.chmod(0o600)
              return True
          except Exception:
              return False

      def renew_certificate(self) -> tuple[bool, str]:
          """証明書を更新"""
          if not self.is_cloudflare_configured():
              return False, "Cloudflare APIトークンが設定されていません"

          cmd = [
              "certbot", "renew",
              "--dns-cloudflare",
              "--dns-cloudflare-credentials", str(self.cloudflare_ini_path),
              "--config-dir", str(self.CERT_DIR / "config"),
              "--work-dir", str(self.CERT_DIR / "work"),
              "--logs-dir", str(self.CERT_DIR / "logs"),
              "--non-interactive",
          ]

          try:
              result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
              if result.returncode == 0:
                  return True, "証明書を更新しました"
              else:
                  return False, f"更新失敗: {result.stderr}"
          except subprocess.TimeoutExpired:
              return False, "更新がタイムアウトしました"
          except Exception as e:
              return False, f"エラー: {str(e)}"

      def should_auto_renew(self, threshold_days: int = 30) -> bool:
          """自動更新が必要か確認"""
          info = self.get_cert_info()
          if not info or 'days_remaining' not in info:
              return False
          return info['days_remaining'] <= threshold_days
  ```
- [ ] CertificateManager単体テスト作成
- [ ] 証明書情報取得確認
- [ ] 残り日数計算確認

### 5.2 設定マネージャーに証明書設定を追加

- [ ] `config_manager.py` にSSL証明書関連設定を追加
  ```python
  DEFAULT_CONFIG = {
      # ... 既存の設定 ...
      # SSL証明書自動更新設定
      "cert_auto_renew_enabled": False,
      "cert_auto_renew_threshold_days": 30,
      "cert_cloudflare_configured": False,
      "cert_last_renewed": None,
      "cert_renew_notify_enabled": True,
  }
  ```

### 5.3 メニューバーに証明書管理を統合

- [ ] `app.py` に証明書メニュー追加
- [ ] 証明書ステータスの動的更新（起動時・定期チェック）
- [ ] 手動更新ボタン実装
- [ ] Cloudflare設定ダイアログ実装
- [ ] 自動更新トグル実装

### 5.4 自動更新スケジューラー

- [ ] サーバー起動時に証明書期限チェック
- [ ] 残り日数が閾値以下なら自動更新実行
- [ ] 更新結果をmacOS通知で表示
- [ ] 更新ログの記録

### 5.5 前提条件チェック

- [ ] certbotインストール確認機能
- [ ] certbot-dns-cloudflareインストール確認機能
- [ ] 未インストール時のインストールガイド表示

---

## Phase 6: 自動起動設定

### 6.1 LaunchAgent作成

- [ ] `menubar/auto_start.py` 作成
  ```python
  import plistlib
  import subprocess
  from pathlib import Path

  class AutoStartManager:
      PLIST_NAME = "com.remoteprompt.server.plist"

      def __init__(self, app_path: Path):
          self.app_path = app_path
          self.plist_path = Path.home() / "Library" / "LaunchAgents" / self.PLIST_NAME

      def is_enabled(self) -> bool:
          return self.plist_path.exists()

      def enable(self) -> bool:
          """ログイン時自動起動を有効化"""
          plist = {
              "Label": "com.remoteprompt.server",
              "ProgramArguments": [str(self.app_path / "Contents" / "MacOS" / "RemotePrompt")],
              "RunAtLoad": True,
              "KeepAlive": False,
              "StandardOutPath": str(Path.home() / "Library" / "Logs" / "RemotePrompt" / "stdout.log"),
              "StandardErrorPath": str(Path.home() / "Library" / "Logs" / "RemotePrompt" / "stderr.log"),
          }

          # ログディレクトリ作成
          log_dir = Path.home() / "Library" / "Logs" / "RemotePrompt"
          log_dir.mkdir(parents=True, exist_ok=True)

          # plist書き込み
          self.plist_path.parent.mkdir(parents=True, exist_ok=True)
          with open(self.plist_path, "wb") as f:
              plistlib.dump(plist, f)

          # launchctl load
          subprocess.run(["launchctl", "load", str(self.plist_path)])
          return True

      def disable(self) -> bool:
          """ログイン時自動起動を無効化"""
          if not self.plist_path.exists():
              return True

          # launchctl unload
          subprocess.run(["launchctl", "unload", str(self.plist_path)])

          # plist削除
          self.plist_path.unlink()
          return True
  ```
- [ ] LaunchAgent有効化確認
- [ ] ログアウト→ログインでの自動起動確認
- [ ] LaunchAgent無効化確認
- [ ] plistファイル内容確認

### 6.2 メニュー統合

- [ ] 「ログイン時に起動」メニュー項目のチェックマーク表示
- [ ] 自動起動ON/OFF切り替え確認
- [ ] 設定状態の永続化確認

---

## Phase 7: py2appによるバイナリ化

### 7.1 setup.py作成

- [ ] `remote-job-server/setup.py` 作成
  ```python
  from setuptools import setup

  APP = ['menubar/app.py']
  DATA_FILES = [
      ('resources', [
          'menubar/resources/icon.png',
          'menubar/resources/icon_running.png',
          'menubar/resources/icon_stopped.png',
          'menubar/resources/icon_error.png',
      ]),
      # サーバーコード
      ('', [
          'main.py',
          'config.py',
          'database.py',
          'models.py',
          # ... 他のサーバーファイル
      ]),
      ('certs/self_signed', []),  # 証明書ディレクトリ
      ('data', []),  # データベースディレクトリ
      ('logs', []),  # ログディレクトリ
  ]

  OPTIONS = {
      'argv_emulation': False,
      'plist': {
          'CFBundleName': 'RemotePrompt',
          'CFBundleDisplayName': 'RemotePrompt Server',
          'CFBundleIdentifier': 'com.remoteprompt.server',
          'CFBundleVersion': '1.0.0',
          'CFBundleShortVersionString': '1.0.0',
          'LSMinimumSystemVersion': '10.15.0',
          'LSUIElement': True,  # メニューバーアプリ（Dockに表示しない）
          'NSHighResolutionCapable': True,
          'NSRequiresAquaSystemAppearance': False,  # ダークモード対応
      },
      'packages': [
          'fastapi',
          'uvicorn',
          'sqlalchemy',
          'pydantic',
          'pydantic_settings',
          'rumps',
          'aioapns',
          'zeroconf',
          'cryptography',
      ],
      'includes': [
          'main',
          'config',
          'database',
          'models',
          'job_manager',
          'session_manager',
          'sse_manager',
          'cert_generator',
          'bonjour_publisher',
          'apns_manager',
          'auth_helpers',
          'file_operations',
          'file_security',
      ],
      'excludes': ['tkinter', 'matplotlib', 'numpy', 'pandas'],
      'iconfile': 'menubar/resources/AppIcon.icns',
  }

  setup(
      name='RemotePrompt',
      app=APP,
      data_files=DATA_FILES,
      options={'py2app': OPTIONS},
      setup_requires=['py2app'],
  )
  ```
- [ ] setup.pyの構文確認

### 7.2 ビルド実行

- [ ] `python setup.py py2app --alias` (開発モードビルド)
- [ ] エイリアスビルド起動確認
- [ ] `python setup.py py2app` (本番ビルド)
- [ ] 本番ビルド起動確認
- [ ] アプリバンドルサイズ確認
- [ ] `dist/RemotePrompt.app` 構造確認

### 7.3 動作検証

- [ ] Finderからの起動確認
- [ ] サーバー起動/停止確認
- [ ] 設定変更確認
- [ ] ログ表示確認
- [ ] アプリ終了確認
- [ ] エラー時の挙動確認

### 7.4 アイコン作成

- [ ] AppIcon.icns作成（1024x1024 → icns変換）
  ```bash
  mkdir AppIcon.iconset
  sips -z 16 16 icon_1024.png --out AppIcon.iconset/icon_16x16.png
  sips -z 32 32 icon_1024.png --out AppIcon.iconset/icon_16x16@2x.png
  sips -z 32 32 icon_1024.png --out AppIcon.iconset/icon_32x32.png
  sips -z 64 64 icon_1024.png --out AppIcon.iconset/icon_32x32@2x.png
  sips -z 128 128 icon_1024.png --out AppIcon.iconset/icon_128x128.png
  sips -z 256 256 icon_1024.png --out AppIcon.iconset/icon_128x128@2x.png
  sips -z 256 256 icon_1024.png --out AppIcon.iconset/icon_256x256.png
  sips -z 512 512 icon_1024.png --out AppIcon.iconset/icon_256x256@2x.png
  sips -z 512 512 icon_1024.png --out AppIcon.iconset/icon_512x512.png
  sips -z 1024 1024 icon_1024.png --out AppIcon.iconset/icon_512x512@2x.png
  iconutil -c icns AppIcon.iconset
  ```
- [ ] icnsファイル確認
- [ ] Finderでアイコン表示確認

---

## Phase 8: コード署名・公証（配布用）

### 8.1 開発者証明書設定

- [ ] Apple Developer Programへの参加確認
- [ ] Developer ID Application証明書取得
- [ ] Keychain Accessでの証明書確認
- [ ] `security find-identity -v -p codesigning` で証明書一覧確認

### 8.2 コード署名

- [ ] 署名スクリプト作成 `scripts/sign_app.sh`
  ```bash
  #!/bin/bash
  IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
  APP_PATH="dist/RemotePrompt.app"

  # 深い階層から署名
  codesign --force --options runtime --sign "$IDENTITY" \
    "$APP_PATH/Contents/Frameworks/"*.dylib
  codesign --force --options runtime --sign "$IDENTITY" \
    "$APP_PATH/Contents/Frameworks/"*.framework
  codesign --force --options runtime --sign "$IDENTITY" \
    "$APP_PATH/Contents/MacOS/"*
  codesign --force --options runtime --sign "$IDENTITY" \
    "$APP_PATH"

  # 署名確認
  codesign -dv --verbose=4 "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
  ```
- [ ] 署名実行
- [ ] 署名検証 `codesign --verify --deep --strict dist/RemotePrompt.app`
- [ ] Gatekeeper検証 `spctl --assess --type execute dist/RemotePrompt.app`

### 8.3 公証（Notarization）

- [ ] 公証スクリプト作成 `scripts/notarize_app.sh`
  ```bash
  #!/bin/bash
  APPLE_ID="your@email.com"
  TEAM_ID="XXXXXXXXXX"
  APP_PATH="dist/RemotePrompt.app"
  ZIP_PATH="dist/RemotePrompt.zip"

  # ZIP作成
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  # 公証送信
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --wait

  # Staple
  xcrun stapler staple "$APP_PATH"
  ```
- [ ] 公証送信
- [ ] 公証完了確認
- [ ] Staple実行
- [ ] Gatekeeper最終確認

### 8.4 DMG作成

- [ ] DMG作成スクリプト `scripts/create_dmg.sh`
  ```bash
  #!/bin/bash
  VERSION="1.0.0"
  DMG_NAME="RemotePrompt-${VERSION}.dmg"

  # DMG作成
  create-dmg \
    --volname "RemotePrompt" \
    --volicon "menubar/resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "RemotePrompt.app" 150 200 \
    --hide-extension "RemotePrompt.app" \
    --app-drop-link 450 200 \
    "$DMG_NAME" \
    "dist/RemotePrompt.app"

  # 署名
  codesign --force --sign "$IDENTITY" "$DMG_NAME"
  ```
- [ ] DMG作成確認
- [ ] DMGマウント確認
- [ ] インストール手順確認

---

## Phase 9: テスト

### 9.1 ユニットテスト

- [ ] `tests/test_config_manager.py` 作成
  - [ ] デフォルト設定読み込みテスト
  - [ ] 設定保存/読み込みテスト
  - [ ] 環境変数変換テスト
  - [ ] マージ動作テスト（新規設定項目追加時）
- [ ] `tests/test_server_controller.py` 作成
  - [ ] 起動テスト
  - [ ] 停止テスト
  - [ ] 状態取得テスト
  - [ ] ヘルスチェックテスト
- [ ] `tests/test_auto_start.py` 作成
  - [ ] plist生成テスト
  - [ ] 有効化/無効化テスト

### 9.2 統合テスト

- [ ] アプリ起動→サーバー起動→API呼び出し→停止のフロー確認
- [ ] 設定変更→再起動→設定反映確認
- [ ] 証明書生成→接続確認
- [ ] Bonjour検出確認（iOSクライアントから）
- [ ] APNs通知確認（要実機）

### 9.3 UIテスト（手動）

- [ ] 各メニュー項目のクリック
- [ ] 設定ダイアログの入力
- [ ] macOS通知表示
- [ ] アイコン切り替え
- [ ] ダークモード対応確認
- [ ] システムスリープからの復帰確認
- [ ] メモリリーク確認（長時間起動）

### 9.4 配布テスト

- [ ] DMGからのインストール確認
- [ ] 別ユーザーアカウントでの起動確認
- [ ] Gatekeeper警告なしで起動確認
- [ ] アンインストール確認

---

## Phase 10: ドキュメント

### 10.1 ユーザーマニュアル

- [ ] `Docs/User_Guide/MenuBar_App_Guide.md` 作成
  - [ ] インストール手順
  - [ ] 初回設定手順
  - [ ] 各設定項目の説明
  - [ ] トラブルシューティング
  - [ ] アンインストール手順
- [ ] スクリーンショット作成
- [ ] FAQ作成

### 10.2 開発者ドキュメント

- [ ] アーキテクチャ図更新
- [ ] ビルド手順ドキュメント
- [ ] 署名・公証手順ドキュメント

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2025-12-03 | v1.0 | 初版作成 |
| 2025-12-03 | v1.1 | Phase 5 SSL証明書管理機能を追加（Cloudflare DNS連携、自動更新） |

---

## リスク・考慮事項

### 技術的リスク

| リスク | 発生確度 | 影響 | 対策 |
|--------|----------|------|------|
| py2appでのバンドル失敗 | 中 | 高 | 依存ライブラリの明示的指定、段階的ビルド |
| Uvicornのマルチスレッド問題 | 中 | 中 | サブプロセスとして起動（現設計で対応済み） |
| rumpsのmacOSバージョン依存 | 低 | 中 | 最小サポートバージョン明示（10.15+） |
| コード署名の期限切れ | 低 | 高 | 証明書更新スケジュール管理 |
| Apple Silicon互換性 | 低 | 中 | Universal Binary対応検討 |

### セキュリティ考慮

| 項目 | 対策 |
|------|------|
| APIキーの保護 | Application Support内の設定ファイルに保存、適切なパーミッション |
| 証明書秘密鍵の保護 | アプリバンドル内に含めず、別途管理 |
| ログファイルの機密情報 | APIキー等のマスキング |

### 今後の拡張可能性

- [ ] SwiftUIによるネイティブ設定画面（将来検討）
- [ ] Windows/Linux対応（PyInstaller使用）
- [ ] 複数サーバーインスタンス管理
- [ ] リモートサーバー監視機能
