# ローカルネットワークHTTPS対応 実装計画

**作成日**: 2025-12-01
**対象**: RemotePrompt サーバー / iOS・iPadOS・macOS クライアント
**要件**: ローカルネットワーク上での自己署名証明書HTTPS通信 + App Store審査対応

---

## 概要

### 背景

RemotePromptをApp Store公開アプリとして設計するにあたり、以下の要件を満たす必要がある：

1. **ローカルネットワーク通信**: ユーザーが自宅LAN内で自己ホストサーバーに接続
2. **App Store審査対応**: HTTPは不可、HTTPSが必須
3. **ユーザー負担軽減**: ドメイン取得・Let's Encrypt設定は求めない
4. **セキュリティ確保**: 自己署名証明書でも安全な通信を実現

### 解決策

**SSH初回接続モデル**を採用：
- サーバーが自己署名証明書を自動生成
- クライアント初回接続時に証明書フィンガープリントを表示
- ユーザーが目視確認後「信頼」→ 以降は証明書ピンニングで通信

### 先例

以下のApp Storeアプリが同様の方式で審査通過済み：
- Termius（SSH/SFTPクライアント）
- Prompt（SSH クライアント）
- ServerCat（サーバー管理）

---

## アーキテクチャ

### 通信フロー

```
┌─────────────────────────────────────────────────────────────────┐
│                         初回接続フロー                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [iPhone]                              [Mac/PC サーバー]        │
│                                                                 │
│  1. サーバーURL入力                                              │
│     https://192.168.11.110:8443                                │
│           │                                                     │
│           ▼                                                     │
│  2. 接続テスト実行 ─────────────────────► 3. 証明書を返却       │
│           │                                  (自己署名)         │
│           ▼                                                     │
│  4. 証明書検証失敗                                               │
│     (正規CAではない)                                             │
│           │                                                     │
│           ▼                                                     │
│  5. フィンガープリント表示                                       │
│     "SHA256: A1:B2:C3:..."                                     │
│           │                                                     │
│           │                            6. サーバー画面でも      │
│           │                               同じ値を表示          │
│           ▼                                                     │
│  7. ユーザーが目視で一致確認                                     │
│     [信頼して接続] をタップ                                      │
│           │                                                     │
│           ▼                                                     │
│  8. 証明書をKeychainに保存                                       │
│     (ピンニング)                                                │
│           │                                                     │
│           ▼                                                     │
│  9. 以降の通信: 保存済み証明書と照合して通信                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### データモデル

```
┌───────────────────────────────────────┐
│         ServerConfiguration           │
├───────────────────────────────────────┤
│ id: UUID                              │
│ name: String (表示名)                  │
│ url: String (https://xxx:port)        │
│ apiKey: String (暗号化保存)            │
│ certificateData: Data? (DER形式)       │
│ certificateFingerprint: String?        │
│ isTrusted: Bool                        │
│ lastConnected: Date?                   │
│ createdAt: Date                        │
└───────────────────────────────────────┘
```

---

## 実装フェーズ

---

## Phase 1: サーバー側 - 自己署名証明書の自動生成

### 1.1 証明書生成スクリプト作成

- [x] `remote-job-server/cert_generator.py` 新規作成
  - [x] 関数: `generate_self_signed_cert(common_name, san_ips, valid_days=3650)`
    - [x] RSA 4096bit 秘密鍵生成
    - [x] X.509 証明書生成（CN=IPアドレス or ホスト名）
    - [x] SAN (Subject Alternative Name) に**複数IPアドレス対応**
      - [x] ローカルIP（例: 192.168.11.110）
      - [x] Tailscale IP（例: 100.100.30.35）※設定可能
      - [x] ホスト名（オプション）
    - [x] 有効期限: 10年（3650日）
  - [x] 関数: `get_certificate_fingerprint(cert_path) -> str`
    - [x] SHA256フィンガープリントを計算
    - [x] コロン区切り形式で返却 (例: `A1:B2:C3:...`)
  - [x] 関数: `ensure_certificate_exists(cert_dir, hostname, san_ips)`
    - [x] 証明書が存在しなければ自動生成
    - [x] 既存なら読み込み
  - [x] 関数: `regenerate_certificate(cert_dir, hostname, san_ips)` ← **証明書ローテーション用**
    - [x] 既存証明書をバックアップ（`server.crt.bak.YYYYMMDD`）
    - [x] 新規証明書を生成
    - [x] 新旧フィンガープリントをログ出力
  - [x] 関数: `revoke_certificate(cert_dir)` ← **強制失効用**
    - [x] 証明書ファイル削除
    - [x] 失効ログ記録

### 1.1.1 環境要件

- [x] 必要なシステム要件をドキュメント化
  - [x] Python 3.9以上
  - [x] cryptographyライブラリ（Rustビルド環境不要のwheel推奨）
  - [x] OpenSSL 1.1以上（システム標準で可）
- [x] ファイルパーミッション設定
  - [x] 秘密鍵: `chmod 600 server.key`
  - [x] 証明書: `chmod 644 server.crt`
  - [x] certsディレクトリ: `chmod 700 certs/`

### 1.2 証明書生成の依存ライブラリ

- [x] `requirements.txt` に追加（既存）
  ```
  cryptography>=41.0.0
  ```

### 1.3 サーバー起動時の証明書チェック

- [x] `remote-job-server/main.py` 修正
  - [x] `lifespan()` 内で `ensure_certificate_exists()` 呼び出し
  - [x] 証明書パスを設定から読み込み
  - [x] 起動ログにフィンガープリント出力

### 1.4 証明書情報取得API

- [x] `GET /server/certificate` エンドポイント追加
  - [x] レスポンス:
    ```json
    {
      "fingerprint": "SHA256:A1:B2:C3:...",
      "common_name": "192.168.11.110",
      "valid_from": "2025-12-01T00:00:00Z",
      "valid_until": "2035-12-01T00:00:00Z",
      "issuer": "RemotePrompt Self-Signed",
      "serial_number": "1234567890",
      "is_self_signed": true
    }
    ```
  - [x] 認証不要（初回接続時に呼び出すため）
  - [x] セキュリティ対策:
    - [x] レート制限: 10回/分/IP（DoS防止）
    - [x] 監査ログ: アクセス元IP・タイムスタンプを記録

### 1.4.1 証明書ローテーションAPI

- [x] `POST /server/certificate/regenerate` エンドポイント追加（管理者用）
  - [x] 認証: API Key必須
  - [x] セキュリティ制約:
    - [ ] IP制限: Tailscale/ローカルネットワークからのみ許可（オプション）
    - [x] レート制限: 1回/時間（証明書再生成の乱用防止）
    - [x] 監査ログ: 実行者IP、タイムスタンプ、理由を記録
      ```
      [AUDIT] Certificate regenerated: reason=scheduled_rotation, ip=192.168.11.50, timestamp=2025-12-01T12:00:00Z
      ```
  - [x] リクエスト:
    ```json
    {
      "reason": "scheduled_rotation"  // または "compromised"
    }
    ```
  - [x] レスポンス:
    ```json
    {
      "old_fingerprint": "SHA256:A1:B2:...",
      "new_fingerprint": "SHA256:X9:Y8:...",
      "regenerated_at": "2025-12-01T12:00:00Z",
      "restart_required": true
    }
    ```
  - [x] 処理フロー:
    - [x] 旧証明書をバックアップ
    - [x] 新証明書を生成
    - [x] クライアントへの通知イベント発火（SSE経由）
    - [x] サーバー再起動が必要な旨を返却

### 1.4.1.1 SSE証明書変更通知仕様

- [x] SSE接続要件
  - [x] エンドポイント: `GET /events` 新規追加（グローバルイベント用）
  - [x] 認証方式: API Key（`x-api-key` ヘッダー）
  - [x] 再接続バックオフ: 初回1秒、最大30秒まで指数増加
  - [x] ハートビート: 30秒間隔で `:ping` を送信
  - [x] SSE標準フォーマット: `event: {name}\ndata: {json}\n\n`
- [x] SSEイベント定義
  - [x] イベント名: `certificate_changed`
  - [x] Payload:
    ```json
    {
      "event": "certificate_changed",
      "data": {
        "old_fingerprint": "SHA256:A1:B2:...",
        "new_fingerprint": "SHA256:X9:Y8:...",
        "reason": "scheduled_rotation",
        "effective_after_restart": true,
        "timestamp": "2025-12-01T12:00:00Z"
      }
    }
    ```
  - [x] 送信タイミング: `POST /server/certificate/regenerate` 成功直後
  - [x] 送信対象: 全アクティブSSE接続（ブロードキャスト）
  - [x] 送信頻度制限: 同一イベントは5分間に1回まで（連続再生成防止）
- [ ] クライアント側再接続ポリシー
  - [ ] `effective_after_restart: true` の場合:
    - [ ] 即座に再接続不要、サーバー再起動を待機
    - [ ] ユーザーに「サーバー再起動後に再接続してください」通知
  - [ ] `effective_after_restart: false`（将来のホットリロード対応時）:
    - [ ] 即座に再接続試行
    - [ ] 新証明書確認ダイアログ表示
- [ ] `Services/SSEManager.swift` 実装要件
  - [ ] `certificate_changed` イベントハンドラ追加
  - [ ] 受信時に `ServerConfigurationStore` の `isTrusted` を `false` に設定
  - [ ] 受信時に `CertificateChangedAlertView` 表示トリガー
  - [ ] `certificate_revoked` イベントハンドラ追加
    - [ ] 受信時に即座に接続切断
    - [ ] `isTrusted = false` に設定
    - [ ] 保存済み証明書をKeychain削除
    - [ ] 「証明書が失効しました。サーバー再起動後に再接続してください」ダイアログ表示
  - [ ] `certificate_mode_changed` イベントハンドラ追加
    - [ ] 受信時に `isTrusted = false` に設定
    - [ ] 「証明書モードが変更されました」ダイアログ表示

### 1.4.1.2 証明書再生成後の運用手順

- [ ] 再起動手順
  - [ ] `systemctl restart remoteprompt` または `launchctl` 再起動
  - [ ] ダウンタイム: 約5-10秒
  - [ ] 事前通知推奨（SSE `server_maintenance` イベント送信）
- [x] バックアップファイル管理
  - [x] 保管場所: `certs/self_signed/backup/`
  - [x] ファイル名: `server.crt.YYYYMMDD-HHMMSS`
  - [x] 世代管理: 最新5世代を保持、古いものは自動削除
- [ ] `revoke_certificate` 実行後の処理
  - [ ] 全クライアントへSSE `certificate_revoked` イベント送信
  - [ ] 既存接続を強制切断（サーバー側でセッション無効化）
  - [x] 次回起動時に新証明書自動生成
- [x] SSEイベント `certificate_revoked` Payload定義
  ```json
  {
    "event": "certificate_revoked",
    "data": {
      "revoked_fingerprint": "SHA256:A1:B2:...",
      "reason": "compromised",
      "revoked_at": "2025-12-01T12:00:00Z",
      "action_required": "reconnect_after_restart"
    }
  }
  ```

### 1.4.2 既存商用証明書との共存

- [x] 証明書モード切替設定
  - [x] `.env` に `SSL_MODE` 追加
    ```
    SSL_MODE=self_signed  # または "commercial" または "auto"
    ```
  - [x] `auto`: 商用証明書パスが存在すれば使用、なければ自己署名
  - [x] 商用証明書パス: `certs/config/live/*/fullchain.pem`（既存Let's Encrypt）
  - [x] 自己署名証明書パス: `certs/self_signed/server.crt`
- [x] 優先順位:
  1. 環境変数で明示指定されたモード
  2. `auto`の場合: 商用証明書 > 自己署名

### 1.4.2.1 証明書モード選択ロジック実装

- [x] `config.py` に `get_ssl_paths()` 関数追加
  ```python
  def get_ssl_paths() -> Tuple[str, str, str]:
      """
      Returns: (cert_path, key_path, mode_used)
      """
      mode = settings.ssl_mode.lower()

      if mode == "commercial":
          # 商用証明書を強制使用
          return (COMMERCIAL_CERT_PATH, COMMERCIAL_KEY_PATH, "commercial")

      if mode == "self_signed":
          # 自己署名を強制使用
          return (SELF_SIGNED_CERT_PATH, SELF_SIGNED_KEY_PATH, "self_signed")

      # auto mode
      if Path(COMMERCIAL_CERT_PATH).exists():
          return (COMMERCIAL_CERT_PATH, COMMERCIAL_KEY_PATH, "commercial")
      else:
          return (SELF_SIGNED_CERT_PATH, SELF_SIGNED_KEY_PATH, "self_signed")
  ```
- [x] 起動時ログ出力
  ```
  [INFO] SSL Mode: auto
  [INFO] Using certificate: commercial (certs/config/live/remoteprompt.soconnect.co.jp/fullchain.pem)
  ```
  または
  ```
  [INFO] SSL Mode: auto
  [INFO] Commercial certificate not found, falling back to self-signed
  [INFO] Using certificate: self_signed (certs/self_signed/server.crt)
  ```
- [ ] `Docs/Specifications/Master_Specification.md` との整合
  - [ ] 既存の商用証明書設定記述を残す
  - [ ] 「自己署名証明書モード」セクションを追加
  - [ ] `SSL_MODE` 環境変数の説明を追加

### 1.4.2.2 autoモードのセキュリティ対策

**リスク**: `SSL_MODE=auto`で商用証明書が消失した際、既存クライアントがピン未設定のまま自己署名に接続し続けるリスク

- [x] フォールバック時の安全対策（以下のいずれかを実装）
  - [x] **オプションA: 明示オプトイン方式（推奨）**
    - [x] `.env` に `SSL_AUTO_FALLBACK_ENABLED=false`（デフォルト無効）
    - [x] 商用証明書消失時、フォールバック無効ならサーバー起動失敗
    - [x] 起動失敗ログ: `[ERROR] Commercial certificate not found. Set SSL_AUTO_FALLBACK_ENABLED=true or SSL_MODE=self_signed to use self-signed certificate.`
  - [x] **オプションB: 警告付き自動フォールバック**
    - [x] フォールバック発生時にサーバー起動は成功
    - [x] ただし、起動時に `[WARN] SECURITY: Falling back to self-signed certificate. Existing clients may need to re-verify.` を出力
    - [x] `/health` エンドポイントに `certificate_fallback_warning: true` を追加
    - [ ] SSE経由で全クライアントに `certificate_mode_changed` イベント送信
- [ ] フォールバック時のクライアント側対応
  - [ ] サーバーから `certificate_mode_changed` イベント受信時
  - [ ] 「証明書モードが変更されました。再確認が必要です」ダイアログ表示
  - [ ] `isTrusted = false` に設定し、次回接続時にピン確認を強制
- [x] SSEイベント `certificate_mode_changed` Payload定義（クライアント側モデル: `CertificateModeChangedEvent` in ServerConfiguration.swift）
  ```json
  {
    "event": "certificate_mode_changed",
    "data": {
      "mode_before": "commercial",
      "mode_after": "self_signed",
      "reason": "fallback_commercial_not_found",
      "triggered_at": "2025-12-01T12:00:00Z"
    }
  }
  ```
  - [x] `mode_before`: 変更前のモード（commercial/self_signed）
  - [x] `mode_after`: 変更後のモード
  - [x] `reason`: 変更理由（`fallback_commercial_not_found`, `manual_switch`, `config_change`）
  - [x] `triggered_at`: イベント発生日時（ISO 8601）

### 1.4.3 `/health` エンドポイント拡張

- [x] `GET /health` レスポンスに証明書関連フィールド追加
  - [x] 既存フィールドを維持しつつ以下を追加:
    ```json
    {
      "status": "ok",
      "ssl_mode": "self_signed",
      "certificate_fallback_warning": false,
      "certificate_fingerprint": "SHA256:A1:B2:..."
    }
    ```
  - [x] `ssl_mode`: 現在使用中のSSLモード
  - [x] `certificate_fallback_warning`: autoモードでフォールバック発生時 `true`
  - [x] `certificate_fingerprint`: 現在の証明書フィンガープリント
- [ ] クライアント側で `/health` を定期確認（オプション）
  - [ ] `certificate_fallback_warning: true` 検出時に警告表示

### 1.5 サーバー設定ファイル拡張

- [x] `.env` に追加
  ```
  SSL_CERT_PATH=./certs/server.crt
  SSL_KEY_PATH=./certs/server.key
  SSL_AUTO_GENERATE=true
  SERVER_HOSTNAME=192.168.11.110
  SERVER_SAN_IPS=192.168.11.110,100.100.30.35
  ```

- [x] `config.py` に設定追加
  - [x] `ssl_cert_path: str`
  - [x] `ssl_key_path: str`
  - [x] `ssl_auto_generate: bool`
  - [x] `server_hostname: str`
  - [x] `server_san_ips: List[str]` - カンマ区切りで複数IP指定可能

### 1.6 uvicorn HTTPS起動対応

- [ ] 起動スクリプト修正
  ```python
  uvicorn.run(
      app,
      host="0.0.0.0",
      port=8443,
      ssl_keyfile=settings.ssl_key_path,
      ssl_certfile=settings.ssl_cert_path
  )
  ```

### 1.7 フィンガープリント表示UI（サーバー側）

- [x] サーバー起動時にコンソールに表示
  ```
  ════════════════════════════════════════════════════════
   RemotePrompt Server v1.0.0

   Server URL: https://192.168.11.110:8443

   Certificate Fingerprint (SHA256):
   A1:B2:C3:D4:E5:F6:G7:H8:I9:J0:K1:L2:M3:N4:O5:P6

   ※ クライアント接続時にこの値と一致することを確認してください
  ════════════════════════════════════════════════════════
  ```

- [ ] （オプション）Webダッシュボードにも表示

---

## Phase 2: iOS側 - サーバー設定画面

### 2.1 データモデル定義

- [x] `Models/ServerConfiguration.swift` 新規作成
  - [x] `struct ServerConfiguration: Codable, Identifiable`
    - [x] `id: UUID`
    - [x] `name: String`
    - [x] `url: String` - メインURL（ローカル or Tailscale）
    - [x] `alternativeURLs: [String]` - 代替URL（フォールバック用）
    - [x] `apiKey: String`
    - [x] `certificateFingerprint: String?`
    - [x] `isTrusted: Bool`
    - [x] `autoFallback: Bool` - 接続失敗時に代替URLを自動試行
    - [x] `lastConnected: Date?`
    - [x] `createdAt: Date`

### 2.2 サーバー設定永続化

- [x] `Services/ServerConfigurationStore.swift` 新規作成
  - [x] Keychain保存（APIキー、証明書データ）
  - [x] UserDefaults保存（URL、名前等の非機密情報）
  - [x] 関数: `save(_ config: ServerConfiguration)`
  - [x] 関数: `load() -> ServerConfiguration?`
  - [x] 関数: `delete()`
  - [x] 関数: `saveCertificate(_ data: Data, fingerprint: String)`
  - [x] 関数: `loadCertificate() -> (Data, String)?`

### 2.3 サーバー設定画面UI

- [x] `Views/Settings/ServerSettingsView.swift` 新規作成
  - [x] サーバーURL入力フィールド
    - [x] プレースホルダー: `https://192.168.11.110:8443`
    - [x] URLバリデーション（https://必須）
  - [x] 代替URL入力セクション
    - [x] 「+ 代替URLを追加」ボタン
    - [x] 複数URL入力対応（Tailscale等）
    - [x] 削除ボタン（スワイプ or ボタン）
  - [x] 自動フォールバック設定
    - [x] トグルスイッチ
    - [x] 説明: 「メインURL接続失敗時に代替URLを試行」
  - [x] API Key入力フィールド
    - [x] SecureField使用
    - [x] ペースト対応
  - [x] 接続テストボタン
  - [x] 接続状態表示
    - [x] 未接続 / 接続中 / 成功 / 失敗
    - [x] 接続中のURL表示（どのURLで接続したか）
  - [x] 証明書情報表示（信頼済みの場合）
    - [x] フィンガープリント
    - [x] 有効期限

### 2.4 サーバー設定ViewModel

- [x] `ViewModels/ServerSettingsViewModel.swift` 新規作成
  - [x] `@Published var serverURL: String`
  - [x] `@Published var alternativeURLs: [String]`
  - [x] `@Published var autoFallback: Bool`
  - [x] `@Published var apiKey: String`
  - [x] `@Published var connectionStatus: ConnectionStatus`
  - [x] `@Published var connectedURL: String?` - 実際に接続できたURL
  - [x] `@Published var certificateInfo: CertificateInfo?`
  - [x] `@Published var showCertificateAlert: Bool`
  - [x] 関数: `testConnection() async`
    - [x] メインURL試行
    - [x] 失敗時かつautoFallback有効 → 代替URL順次試行
    - [x] 接続成功したURLを記録
  - [x] 関数: `addAlternativeURL(_ url: String)`
  - [x] 関数: `removeAlternativeURL(at index: Int)`
  - [x] 関数: `trustCertificate()`
  - [x] 関数: `saveConfiguration()`

### 2.5 Bonjour自動検出（オプション）

- [x] `Services/BonjourDiscovery.swift` 新規作成
  - [x] `NWBrowser` (Network framework) でローカルサーバー検出
  - [x] サービスタイプ: `_remoteprompt._tcp`
  - [x] 検出されたサーバーをリスト表示
  - [x] タップで自動入力
  - [x] TXTレコードからメタデータ（ssl_mode, fingerprint等）取得

- [x] サーバー側: Bonjour公開
  - [x] `remote-job-server/bonjour_publisher.py` 新規作成
  - [x] zeroconf ライブラリ使用
  - [x] config.py に `bonjour_enabled`, `bonjour_service_name` 追加
  - [x] main.py lifespan に Bonjour開始/停止処理追加

---

## Phase 3: iOS側 - 証明書ピンニング実装

### 3.1 カスタムURLSessionDelegate

- [x] `Services/CertificatePinningDelegate.swift` 新規作成
  - [x] `class CertificatePinningDelegate: NSObject, URLSessionDelegate`
  - [x] 関数: `urlSession(_:didReceive:completionHandler:)`
    - [x] サーバー証明書を取得
    - [x] 保存済みフィンガープリントと比較
    - [x] 一致: 接続許可
    - [x] 不一致: 接続拒否 + エラー通知
    - [x] 未保存: 新規証明書として処理依頼

### 3.2 証明書検証ユーティリティ

- [x] `Utilities/CertificateValidator.swift` 新規作成
  - [x] 関数: `extractFingerprint(from trust: SecTrust) -> String?`
    - [x] SecTrustから証明書取得
    - [x] SHA256ハッシュ計算
    - [x] コロン区切り文字列に変換
  - [x] 関数: `extractCertificateData(from trust: SecTrust) -> Data?`
    - [x] DER形式でエクスポート
  - [x] 関数: `compareCertificates(stored: Data, received: SecTrust) -> Bool`

### 3.3 証明書確認アラート

- [x] `Views/Settings/CertificateConfirmationView.swift` 新規作成
  - [x] モーダル表示
  - [x] 表示内容:
    - [x] 警告アイコン
    - [x] 「サーバーの証明書を検証できません」メッセージ
    - [x] フィンガープリント（SHA256）
    - [x] 「サーバー側の表示と一致していますか？」
  - [x] ボタン:
    - [x] 「キャンセル」→ 接続中止
    - [x] 「信頼して接続」→ 証明書保存

### 3.3.1 証明書変更検知・再確認UI

- [x] `Views/Settings/CertificateChangedAlertView.swift` 新規作成
  - [x] 表示トリガー: ピンニング済み証明書と異なる証明書を受信
  - [x] 表示内容:
    - [x] **警告アイコン（赤）**
    - [x] 「サーバーの証明書が変更されました」
    - [x] 「これは中間者攻撃の可能性があります」
    - [x] 旧フィンガープリント表示
    - [x] 新フィンガープリント表示
    - [x] 「サーバー管理者に確認してください」
  - [x] ボタン:
    - [x] 「接続を中止」（デフォルト、目立つ配色）
    - [x] 「新しい証明書を信頼」（確認ダイアログ付き）
    - [x] 「保存済み証明書を破棄」→ 設定画面へ遷移

### 3.3.2 証明書信頼の破棄・リセット機能

- [x] `ServerConfigurationStore.swift` に追加
  - [x] 関数: `clearTrustedCertificate()`
    - [x] Keychainから証明書データ削除
    - [x] `isTrusted = false` に設定
  - [x] 関数: `resetAllConfiguration()`
    - [x] 全設定をクリア（URL、API Key含む）
    - [x] 初期状態に戻す
- [x] 設定画面に「証明書信頼をリセット」ボタン追加
  - [x] 確認ダイアログ: 「次回接続時に再確認が必要になります」
- [x] 設定画面に「すべての設定をリセット」ボタン追加
  - [x] 確認ダイアログ: 「サーバー接続情報がすべて削除されます」

### 3.4 APIClient統合

- [x] `Services/APIClient.swift` 修正
  - [x] URLSession生成時にカスタムDelegate設定（`getSession()`メソッド追加）
  - [x] 証明書エラー時のコールバック追加（`onCertificateError`）
  - [x] 新規/不一致証明書のコールバック（`onNewCertificate`, `onCertificateMismatch`）
  - [x] 設定変更時のセッション再生成（`invalidateSession()`）

### 3.5 SSEManager統合

- [x] `Services/SSEManager.swift` 修正
  - [x] カスタムDelegate適用（`CertificatePinningDelegate`）
  - [x] 証明書変更検知時のイベントハンドラ追加
  - [x] `certificate_changed`, `certificate_revoked`, `certificate_mode_changed` イベント対応

---

## Phase 4: iOS側 - 設定画面統合

### 4.1 アプリ起動フロー修正

- [x] `ContentView.swift` 修正
  - [x] 起動時にサーバー設定をチェック（`Constants.isServerConfigured`）
  - [x] 未設定 → ServerSettingsView表示へ誘導
  - [x] 設定済み → 通常のRoomsListView表示
  - [x] 旧設定からの移行処理（`migrateIfNeeded`）

### 4.2 既存Constants.swift修正

- [x] `Support/Constants.swift` 修正
  - [x] `ServerConfigurationStore`から動的に取得（優先）
  - [x] 旧設定（plist）をフォールバックとして維持
  - [x] `isServerConfigured` プロパティ追加
  - [x] `currentServerConfiguration` プロパティ追加

### 4.3 既存AppConfiguration.swift修正

- [x] `Support/AppConfiguration.swift` は変更なし
  - [x] レガシー設定としてConstants.swiftから参照される形で維持
  - [x] 移行ロジックはServerConfigurationStore.migrateIfNeededで実装済み

### 4.3.1 既存ユーザー設定の移行手順

- [x] 移行元（旧設定）
  - [x] `RemotePromptConfig.plist` の `RemotePromptBaseURL`
  - [x] `RemotePromptConfig.plist` の `RemotePromptAPIKey`
  - [x] Keychain の `device_id`（既存）
- [x] 移行先（新設定）
  - [x] `ServerConfigurationStore` の `url`
  - [x] `ServerConfigurationStore` の `apiKey`（Keychain経由）
  - [x] `ServerConfigurationStore` の `certificateFingerprint`（新規）
- [x] 移行フロー（`ServerConfigurationStore.migrateIfNeeded()`として実装済み）
  ```swift
  func migrateIfNeeded() {
      // 1. 新設定が既に存在 → 移行不要
      if ServerConfigurationStore.shared.load() != nil { return }

      // 2. 旧設定を読み込み
      let oldConfig = AppConfiguration()
      guard !oldConfig.baseURL.isEmpty else { return }

      // 3. 新設定に変換
      let newConfig = ServerConfiguration(
          id: UUID(),
          name: "Migrated Server",
          url: oldConfig.baseURL,
          alternativeURLs: [],
          apiKey: oldConfig.apiKey ?? "",
          certificateFingerprint: nil,  // 移行時は未信頼
          isTrusted: false,  // 初回接続時に再確認
          autoFallback: false,
          lastConnected: nil,
          createdAt: Date()
      )

      // 4. 保存
      ServerConfigurationStore.shared.save(newConfig)

      // 5. 移行完了フラグ設定
      UserDefaults.standard.set(true, forKey: "settings_migrated_v2")
  }
  ```
- [x] 移行失敗時のフォールバック
  - [x] plist読み込み失敗 → 設定画面表示（手動入力促進）
  - [x] Keychain読み込み失敗 → API Key手動入力促進
  - [x] エラーログ出力（デバッグ用）
- [x] 移行完了後の旧設定
  - [x] plistファイルは残置（アンインストール時に自動削除）
  - [x] 旧KeychainのAPI Key項目は残置（互換性維持）

### 4.4 設定画面へのナビゲーション

- [x] `Views/RoomsListView.swift` 修正
  - [x] 設定ボタン追加（ナビゲーションバー右上のgearアイコン）
  - [x] タップでServerSettingsView表示（sheet）

### 4.5 接続エラー時の誘導

- [x] 接続エラー発生時に設定画面へのリンク表示
  - [x] ContentViewでサーバー未設定時に初期設定画面を表示
  - [x] 「サーバーを設定」ボタンでServerSettingsView起動

---

## Phase 5: Info.plist設定

### 5.1 ローカルネットワーク許可

- [x] Xcodeプロジェクト設定に追加
  - `INFOPLIST_KEY_NSLocalNetworkUsageDescription = "ローカルネットワーク上のRemotePromptサーバーに接続します。"`

### 5.2 Bonjourサービス宣言（自動検出使用時）

- [x] Xcodeプロジェクト設定に追加
  - `INFOPLIST_KEY_NSBonjourServices = "_remoteprompt._tcp"`

### 5.3 ATS設定詳細

#### 5.3.1 ATS技術的背景

自己署名証明書 + IP直接アクセスは、ATSのデフォルト評価を満たさない場合がある：
- ATSはTLS 1.2以上、Forward Secrecy対応を要求
- 自己署名証明書自体はATSで禁止されていないが、URLSessionDelegateでの手動信頼が必要

#### 5.3.2 必要な設定

- [x] **ATS例外は基本的に不要**（ピンニングで対応）
- [x] ただし、審査時に説明を求められた場合の対応準備
  - [x] `NSAllowsLocalNetworking = true` は不要（iOS 14以降は別途許可ダイアログで対応）
  - [x] `NSExceptionDomains` によるIP例外は**追加しない**（審査リスク増大）

#### 5.3.3 App Store審査向け説明テンプレート

- [ ] 審査向け説明文を準備（App Review Notesに記載）
  ```
  【日本語】
  このアプリはユーザーが自己ホストするサーバーに接続します。
  サーバーは自己署名証明書を使用しますが、SSH接続と同様に
  初回接続時にユーザーが証明書のフィンガープリントを確認し、
  明示的に信頼することで安全性を確保しています。

  このアプローチは以下のApp Storeアプリで採用済みです：
  - Termius (SSH Client)
  - Prompt 3 (SSH Client)
  - ServerCat (Server Status)

  【English】
  This app connects to user's self-hosted server on their local network.
  The server uses a self-signed certificate. Similar to SSH clients,
  users manually verify and trust the certificate fingerprint on first
  connection, ensuring security through explicit user confirmation.

  This approach is already used by these App Store apps:
  - Termius (SSH Client)
  - Prompt 3 (SSH Client)
  - ServerCat (Server Status)
  ```

#### 5.3.4 審査リジェクト時の対応計画

- [ ] リジェクト理由ごとの対応策準備
  - [ ] 「ATS例外の理由が不明」→ 上記説明文を詳細に記載
  - [ ] 「セキュリティリスク」→ ピンニング実装の詳細説明
  - [ ] 「ユーザー保護不足」→ 証明書確認UIのスクリーンショット提供

---

## Phase 6: macOS/iPadOS対応

### 6.1 macOS Catalyst対応

- [ ] ServerSettingsViewのmacOSレイアウト調整
  - [ ] ウィンドウサイズ適正化
  - [ ] キーボードショートカット対応

### 6.2 iPadOS対応

- [x] Split View対応
  - [x] ServerSettingsViewにhorizontalSizeClass対応追加
  - [x] ContentViewにiPad用初期設定画面追加
  - [x] RoomsListViewにpresentationDetents追加

### 6.3 証明書の共有（同一AppleID）

- [ ] iCloud Keychain同期の検討
  - [ ] 同一ユーザーの複数デバイスで証明書共有
  - [ ] セキュリティ考慮（オプトイン）

---

## Phase 7: テスト

### 7.1 サーバー側ユニットテスト

- [x] `tests/test_cert_generator.py` 新規作成
  - [x] 証明書生成テスト（22テスト、全パス）
  - [x] フィンガープリント計算テスト
  - [x] 証明書読み込みテスト
  - [x] 証明書再生成・失効テスト

### 7.2 iOS側ユニットテスト

- [x] `RemotePromptTests/CertificateValidatorTests.swift` 新規作成（6テスト、全パス）
  - [x] フィンガープリント抽出テスト
  - [x] 証明書比較テスト
  - [x] フィンガープリント形式テスト

- [x] `RemotePromptTests/ServerConfigurationStoreTests.swift` 作成済み（8テスト、全パス）
  - [x] 保存・読み込みテスト
  - [x] URL検証テスト

- [x] 既存テストの修正
  - [x] Swift Testing → XCTest形式変換
    - [x] MessageParserTests.swift（9テスト、全パス）
    - [x] CodeBlockViewTests.swift（5テスト、全パス）
    - [x] RemotePromptTests.swift（1テスト、全パス）
    - [x] MarkdownRendererTests.swift（3テスト、全パス）
    - [x] AppConfigurationTests.swift（7テスト、全パス）
  - [x] RoomBasedArchitectureTests.swift API互換性修正（11テスト、全パス）
    - [x] @MainActor対応
    - [x] Room初期化パラメータ追加
    - [x] MockAPIClient不足メソッド追加

### 7.2.1 テスト実行結果サマリー

| テストスイート | テスト数 | 結果 |
|---------------|---------|------|
| AppConfigurationTests | 7 | ✅ 全パス |
| CertificateInfoTests | 3 | ✅ 全パス |
| CertificateValidatorTests | 6 | ✅ 全パス |
| CodeBlockViewTests | 5 | ✅ 全パス |
| MarkdownRendererTests | 3 | ✅ 全パス |
| MessageParserTests | 9 | ✅ 全パス |
| RemotePromptTests | 1 | ✅ 全パス |
| RoomBasedArchitectureTests | 11 | ✅ 全パス |
| ServerConfigurationStoreTests | 8 | ✅ 全パス |
| **合計** | **53** | **✅ 全パス** |

### 7.3 統合テスト

- [ ] `RemotePromptUITests/ServerSettingsUITests.swift` 新規作成
  - [ ] 設定画面表示テスト
  - [ ] URL入力テスト
  - [ ] 接続テストボタン動作テスト

### 7.4 手動テスト

- [ ] 初回接続フロー
  - [ ] 新規サーバー設定入力
  - [ ] 証明書確認ダイアログ表示
  - [ ] 信頼後の接続成功
- [ ] 2回目以降の接続
  - [ ] 保存済み証明書での自動接続
- [ ] 証明書変更検知
  - [ ] サーバー証明書再生成後の警告表示
- [ ] ネットワーク切り替え
  - [ ] Wi-Fi → LTE → Wi-Fi での動作確認
- [ ] マルチURL・フォールバック動作
  - [ ] ローカルIP + Tailscale IPの両方設定
  - [ ] ローカルWi-Fi接続時 → ローカルIPで接続確認
  - [ ] Tailscale接続時 → Tailscale IPで接続確認
  - [ ] 自動フォールバック動作確認
    - [ ] メインURL到達不可 → 代替URLへ自動切替
    - [ ] 切替成功のログ/表示確認

### 7.5 証明書ローテーション・復旧テスト

- [ ] 証明書ローテーションフロー
  - [ ] サーバー側で証明書再生成API実行
  - [ ] クライアントへのSSE `certificate_changed` 通知確認
  - [ ] SSE受信後のクライアント表示確認（「サーバー再起動後に再接続」メッセージ）
  - [ ] サーバー再起動後の接続確認
  - [ ] クライアント側で証明書変更警告表示確認
  - [ ] 「新しい証明書を信頼」で再接続成功
- [ ] SSE通知後のクライアント自動再接続テスト
  - [ ] `effective_after_restart: true` 時は即座に再接続しないことを確認
  - [ ] サーバー再起動完了後に再接続試行
- [ ] 証明書信頼リセットフロー
  - [ ] 設定画面から「証明書信頼をリセット」実行
  - [ ] 次回接続時に証明書確認ダイアログ表示確認
- [ ] 不正証明書検知
  - [ ] MITM攻撃シミュレーション（プロキシで別証明書挿入）
  - [ ] 警告表示・接続拒否確認
- [ ] 復旧パステスト
  - [ ] 証明書不一致後に「接続を中止」→ 設定画面表示
  - [ ] 「すべての設定をリセット」→ 初期状態に戻る確認
- [ ] `certificate_revoked` イベント受信テスト
  - [ ] SSEイベント受信時に接続切断されることを確認
  - [ ] Keychainから証明書が削除されることを確認
  - [ ] 失効ダイアログが表示されることを確認
  - [ ] サーバー再起動後、新証明書で再接続フロー実行
- [ ] `certificate_mode_changed` イベント受信テスト
  - [ ] SSEイベント受信時にダイアログ表示確認
  - [ ] `isTrusted = false` に設定されることを確認
  - [ ] 次回接続時に証明書再確認フローが発動することを確認

### 7.6 フォールバック時のピンニング整合性テスト

- [ ] フォールバック経路でも同一証明書であることの検証
  - [ ] メインURL証明書 = 代替URL証明書（SAN含む）
  - [ ] 異なる証明書の場合は警告表示
- [ ] 旧証明書がフォールバック経路で残っていないことの検証
  - [ ] メインURL証明書更新後、代替URLでも新証明書を要求

### 7.7 Bonjour + 自己署名証明書複合テスト

- [ ] Bonjourで検出されたサーバーへの接続
  - [ ] 自動検出 → 証明書確認フロー正常動作
  - [ ] 複数サーバー検出時の選択UI

### 7.8 ATS関連テスト

- [ ] Info.plist ATS設定なしでの動作確認
  - [ ] 自己署名証明書への接続成功（ピンニングのみ）
- [ ] Xcode ATSデバッグ出力確認
  - [ ] `nscurl --ats-diagnostics` での検証
- [ ] 審査シミュレーション
  - [ ] TestFlight配布での動作確認

### 7.9 SSL_MODE切替テスト

- [ ] `SSL_MODE=commercial` テスト
  - [ ] 商用証明書（Let's Encrypt）での起動確認
  - [ ] クライアント側でピンニングなしで接続成功
- [ ] `SSL_MODE=self_signed` テスト
  - [ ] 自己署名証明書での起動確認
  - [ ] クライアント側でピンニング動作確認
- [ ] `SSL_MODE=auto` フォールバックテスト
  - [ ] 商用証明書存在時 → 商用証明書使用確認
  - [ ] 商用証明書削除後 → 自己署名にフォールバック確認
  - [ ] フォールバック時のログ出力確認
  - [ ] フォールバック時のクライアント側ピンニング動作確認
- [ ] モード切替時のピンニング整合性
  - [ ] 商用→自己署名切替時、クライアントに証明書変更警告が出ることを確認
  - [ ] 自己署名→商用切替時、正規CAのためピンニング不要であることを確認

---

## Phase 8: ドキュメント・リリース

### 8.1 ユーザー向けドキュメント

- [ ] `Docs/User_Guide/Server_Setup.md` 新規作成
  - [ ] サーバーインストール手順
    - [ ] システム要件（Python 3.9+、メモリ、ディスク）
    - [ ] 依存ライブラリインストール
    - [ ] 初回起動手順
  - [ ] 証明書の確認方法
    - [ ] コンソール出力の見方
    - [ ] フィンガープリントの記録推奨
  - [ ] 証明書ローテーション手順
    - [ ] 手動再生成の方法
    - [ ] クライアント側での再確認手順
  - [ ] トラブルシューティング
    - [ ] 「接続できない」場合
    - [ ] 「証明書エラー」の場合
    - [ ] ファイアウォール設定

- [ ] `Docs/User_Guide/iOS_Setup.md` 新規作成
  - [ ] アプリ初回設定手順
  - [ ] サーバー接続設定
  - [ ] 証明書信頼の説明
    - [ ] なぜフィンガープリント確認が必要か
    - [ ] 確認の正しい方法
  - [ ] 複数URL（ローカル/Tailscale）の設定方法
  - [ ] 証明書変更時の対処法
  - [ ] 設定リセットの方法

- [ ] `Docs/User_Guide/Certificate_Mode_Switching.md` 新規作成
  - [ ] SSL_MODE切替のユースケース説明
    - [ ] 開発時: `self_signed`で素早くセットアップ
    - [ ] 本番時: `commercial`でLet's Encrypt使用
    - [ ] 移行期: `auto`で段階的移行
  - [ ] 切替時のクライアント側影響
    - [ ] 商用→自己署名: 証明書再確認が必要
    - [ ] 自己署名→商用: 自動的に接続OK（CAが信頼済み）
  - [ ] 切替手順
    - [ ] サーバー停止
    - [ ] `.env` の `SSL_MODE` 変更
    - [ ] サーバー再起動
    - [ ] クライアント側での対応（必要な場合）
  - [ ] トラブルシューティング
    - [ ] 「証明書が変更されました」警告が出た場合
    - [ ] 切り戻し手順

### 8.1.1 運用ガイド

- [ ] `Docs/User_Guide/Operations_Guide.md` 新規作成
  - [ ] 定期メンテナンス
    - [ ] ログローテーション
    - [ ] ディスク容量監視
  - [ ] 証明書の有効期限管理
    - [ ] 10年後の更新手順
  - [ ] バックアップ・リストア
    - [ ] 証明書ファイルのバックアップ
    - [ ] データベースバックアップ
  - [ ] サーバー再起動時の注意点
    - [ ] ダウンタイムの最小化
    - [ ] クライアント再接続の挙動

### 8.2 Master_Specification.md更新

- [ ] `Docs/Specifications/Master_Specification.md` 更新
  - [ ] 自己署名証明書方式の追加
  - [ ] サーバー設定APIの追加
  - [ ] クライアント設定画面の追加

### 8.3 App Store審査対応

- [ ] 審査向け説明文準備
  ```
  This app connects to user's self-hosted server on their local network.
  Users configure their own server URL and manually verify the certificate
  fingerprint before trusting the connection. This is similar to SSH client
  applications like Termius or Prompt.
  ```

- [ ] デモアカウント/サーバー情報準備（審査用）

### 8.4 CHANGELOG更新

- [ ] バージョン番号決定
- [ ] 変更内容記載

---

## リスク・考慮事項

### 技術的リスク

| リスク | 発生確度 | 影響 | 対策 |
|--------|---------|------|------|
| App Store審査リジェクト | 低 | 高 | 先例アプリの調査、審査向け説明準備 |
| 証明書ピンニングバグ | 中 | 高 | 十分なテスト、フォールバック実装 |
| ユーザーの操作ミス | 中 | 低 | 明確なUI/UX、ヘルプテキスト |

### セキュリティ考慮

| 項目 | 対策 |
|------|------|
| 中間者攻撃 | フィンガープリント目視確認 + ピンニング |
| 証明書漏洩 | Keychain保存、アプリ削除時自動削除 |
| APIキー漏洩 | Keychain暗号化保存 |

---

## 依存関係

### サーバー側

| ライブラリ | バージョン | 用途 |
|-----------|-----------|------|
| cryptography | >=41.0.0 | 証明書生成 |
| zeroconf | >=0.80.0 | Bonjour公開（オプション） |

### iOS側

| フレームワーク | 用途 |
|---------------|------|
| Security.framework | Keychain, 証明書操作 |
| Network.framework | Bonjour検出（オプション） |

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|----------|---------|
| 2025-12-01 | v1.0 | 初版作成 |
| 2025-12-01 | v1.1 | Tailscale対応追記: SAN複数IP対応、代替URL機能、フォールバック機能 |
| 2025-12-01 | v1.2 | Codexレビュー反映: 証明書ローテーション/失効、ATS審査対応詳細、既存仕様との整合、運用手順、クライアント復旧パス、テスト観点拡充 |
| 2025-12-01 | v1.3 | Codex追加レビュー反映: SSE通知仕様詳細化、証明書モード選択ロジック、既存設定移行手順、SSL_MODE切替テスト、レート制限・監査ログ追加 |
| 2025-12-01 | v1.4 | Codex最終レビュー反映: SSL_AUTO_FALLBACK_ENABLED明示オプトイン方式、SSE送信頻度制限(5分/回)、証明書モード切替UXドキュメント |
| 2025-12-01 | v1.5 | Codex補完レビュー反映: certificate_mode_changed/certificate_revoked Payload定義、/healthエンドポイント拡張タスク、クライアント側SSEイベントハンドラ詳細化、テストケース追加 |
| 2025-12-01 | v1.6 | Codex実装レビュー反映: 証明書フィンガープリント整合性修正(pending_restart状態管理)、/eventsグローバルSSEエンドポイント追加、get_ssl_paths()キャッシュ化(fallback警告維持)、SSEイベント名標準フォーマット対応 |
| 2025-12-01 | v1.7 | Phase 2-3 iOS実装完了: ServerConfiguration/ServerConfigurationStore/ServerSettingsView/ServerSettingsViewModel/CertificatePinningDelegate/CertificateValidator/CertificateConfirmationView 作成、ビルド成功確認 |
| 2025-12-01 | v1.8 | Phase 2.5 Bonjour自動検出実装完了: bonjour_publisher.py(サーバー側)、BonjourDiscovery.swift(iOS側)、ServerSettingsViewにBonjour検出セクション追加、zeroconfライブラリ追加 |
| 2025-12-01 | v1.9 | Phase 3.4-4.5 実装完了: APIClient証明書ピンニング統合、SSEManager証明書イベント対応、Constants.swift動的URL対応、ContentView初期設定フロー、RoomsListView設定ボタン追加、ビルド成功確認 |
| 2025-12-02 | v2.0 | Phase 5-7 完了: Info.plist設定修正(IPHONEOS_DEPLOYMENT_TARGET=17.0, NSBonjourServices配列化)、iPadOS Split View対応、全ユニットテスト53件パス(Swift Testing→XCTest変換、@MainActor対応) |
