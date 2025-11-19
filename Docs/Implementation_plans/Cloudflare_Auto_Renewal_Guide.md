# Cloudflare DNS + 証明書自動更新ガイド

作成日: 2025-11-19

## 概要

Cloudflare DNSを使用してLet's Encrypt証明書の完全自動更新を実現する方法。

## なぜCloudflareか？

- **完全無料**: DNS、SSL証明書ともに無料
- **自動更新**: certbot-dns-cloudflareで完全自動化
- **高速DNS**: Cloudflareの高速DNSネットワーク
- **追加機能**: DDoS防御、CDN、アクセス解析も無料

## 手順

### 1. Cloudflareアカウント作成

1. https://dash.cloudflare.com/sign-up にアクセス
2. メールアドレスとパスワードで登録（無料）

### 2. ドメインをCloudflareに追加

1. Cloudflareダッシュボードで「サイトを追加」
2. `soconnect.co.jp` を入力
3. プラン選択: **無料プラン** を選択
4. 既存のDNSレコードが自動スキャンされる

### 3. ネームサーバー変更

ムームードメインで以下の設定を変更:

```
ムームードメインコントロールパネル
→ ドメイン管理
→ soconnect.co.jp
→ ネームサーバ設定変更
→ GMOペパボ以外のネームサーバを使用する

ネームサーバ1: <Cloudflareが指定>
ネームサーバ2: <Cloudflareが指定>
```

例:
```
ネームサーバ1: adam.ns.cloudflare.com
ネームサーバ2: bella.ns.cloudflare.com
```

**注意**: Cloudflareダッシュボードに表示される実際の値を使用してください。

### 4. DNS伝播確認（最大24時間）

```bash
dig NS soconnect.co.jp @8.8.8.8
```

Cloudflareのネームサーバーが表示されればOK。

### 5. Cloudflare APIトークン取得

1. Cloudflareダッシュボード → My Profile → API Tokens
2. 「Create Token」をクリック
3. テンプレート: **Edit zone DNS** を選択
4. Zone Resources: **Include - Specific zone - soconnect.co.jp**
5. 「Continue to summary」→「Create Token」
6. トークンをコピー（**一度しか表示されません**）

### 6. certbot-dns-cloudflareインストール

```bash
brew install certbot-dns-cloudflare
```

または:

```bash
pip install certbot-dns-cloudflare
```

### 7. Cloudflare認証情報ファイル作成

```bash
mkdir -p /Users/macstudio/Projects/RemotePrompt/remote-job-server/secrets
cat > /Users/macstudio/Projects/RemotePrompt/remote-job-server/secrets/cloudflare.ini <<EOF
# Cloudflare API token
dns_cloudflare_api_token = <取得したAPIトークン>
EOF

chmod 600 /Users/macstudio/Projects/RemotePrompt/remote-job-server/secrets/cloudflare.ini
```

### 8. 証明書取得（初回）

```bash
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /Users/macstudio/Projects/RemotePrompt/remote-job-server/secrets/cloudflare.ini \
  -d remoteprompt.soconnect.co.jp \
  --config-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/config \
  --work-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/work \
  --logs-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/logs
```

### 9. 自動更新設定（cron）

```bash
sudo crontab -e
```

以下を追加（毎日午前3時に更新チェック）:

```cron
0 3 * * * certbot renew --dns-cloudflare --dns-cloudflare-credentials /Users/macstudio/Projects/RemotePrompt/remote-job-server/secrets/cloudflare.ini --config-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/config --work-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/work --logs-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/logs --post-hook "pkill -HUP uvicorn"
```

または、macOSの場合はLaunchAgentを使用:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.remoteprompt.certbot-renew</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/certbot</string>
        <string>renew</string>
        <string>--dns-cloudflare</string>
        <string>--dns-cloudflare-credentials</string>
        <string>/Users/macstudio/Projects/RemotePrompt/remote-job-server/secrets/cloudflare.ini</string>
        <string>--config-dir</string>
        <string>/Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/config</string>
        <string>--work-dir</string>
        <string>/Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/work</string>
        <string>--logs-dir</string>
        <string>/Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/logs</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

保存先: `~/Library/LaunchAgents/com.remoteprompt.certbot-renew.plist`

読み込み:
```bash
launchctl load ~/Library/LaunchAgents/com.remoteprompt.certbot-renew.plist
```

### 10. 更新テスト

```bash
sudo certbot renew --dry-run \
  --dns-cloudflare \
  --dns-cloudflare-credentials /Users/macstudio/Projects/RemotePrompt/remote-job-server/secrets/cloudflare.ini \
  --config-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/config \
  --work-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/work \
  --logs-dir /Users/macstudio/Projects/RemotePrompt/remote-job-server/certs/logs
```

## メリット

✅ **完全自動更新**: 90日ごとの手動更新不要
✅ **無料**: すべて無料で利用可能
✅ **高速**: Cloudflareの高速DNSネットワーク
✅ **セキュア**: DDoS防御機能付き
✅ **簡単**: 一度設定すれば放置可能

## デメリット

⚠️ ネームサーバー移管に最大24時間かかる
⚠️ ムームードメインの一部機能が使えなくなる可能性

## トラブルシューティング

### DNS伝播が遅い

```bash
# 現在のネームサーバー確認
dig NS soconnect.co.jp @8.8.8.8

# Cloudflareに切り替わっていない場合は待機
```

### API token error

- APIトークンの権限を確認
- Zone DNS Edit権限が付与されているか確認
- cloudflare.iniのパーミッションが600か確認

## 参考リンク

- [Cloudflare公式ガイド](https://developers.cloudflare.com/dns/)
- [certbot-dns-cloudflare](https://certbot-dns-cloudflare.readthedocs.io/)
