# ユーザー向け：サーバーセットアップガイド

## 概要

RemotePromptサーバーを自分のMacにセットアップし、SSL証明書を取得する手順です。

---

## 前提条件

- macOS（Intel/Apple Silicon）
- Homebrew インストール済み
- Python 3.9以上
- Tailscale インストール・起動済み
- **管理者から発行されたサブドメイン名**
- **管理者から共有されたCloudflare APIトークン**

---

## セットアップ手順

### 1. Tailscale IPアドレスを確認

```bash
tailscale ip -4
```

このIPアドレスを管理者に伝えて、サブドメインを発行してもらってください。

---

### 2. リポジトリをクローン

```bash
git clone https://github.com/your-org/RemotePrompt.git
cd RemotePrompt/remote-job-server
```

---

### 3. Python仮想環境をセットアップ

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

---

### 4. Cloudflare認証情報を設定

管理者から受け取ったAPIトークンを設定：

```bash
mkdir -p ../secrets
cat > ../secrets/cloudflare.ini << 'EOF'
dns_cloudflare_api_token = ここにAPIトークンを貼り付け
EOF
chmod 600 ../secrets/cloudflare.ini
```

---

### 5. Let's Encrypt証明書を発行

管理者から発行されたサブドメイン名を使用：

```bash
python scripts/setup_letsencrypt.py <サブドメイン名>
```

例：
```bash
python scripts/setup_letsencrypt.py abc12345
```

実行結果：
```
============================================================
  Let's Encrypt 証明書セットアップ
============================================================

  ドメイン: abc12345.remoteprompt.net

certbotをインストールしています...
証明書を発行しています: abc12345.remoteprompt.net
証明書が発行されました
自動更新を設定しました（毎日3:00 AM）
.envファイルを更新しました

============================================================
  セットアップ完了!
============================================================
```

---

### 6. .envファイルを編集

```bash
cp .env.example .env
nano .env
```

**必須**: APIキーを変更してください：

```env
# API認証キー（必ず変更してください）
API_KEY=あなた独自の強力なキーに変更

# 以下はsetup_letsencrypt.pyが自動設定済み
SERVER_HOSTNAME=abc12345.remoteprompt.net
COMMERCIAL_CERT_PATH=./certs/remoteprompt.net/config/live/abc12345.remoteprompt.net/fullchain.pem
COMMERCIAL_KEY_PATH=./certs/remoteprompt.net/config/live/abc12345.remoteprompt.net/privkey.pem
```

---

### 7. サーバーを起動

```bash
python -m uvicorn main:app --host 0.0.0.0 --port 8443 \
  --ssl-keyfile ./certs/remoteprompt.net/config/live/abc12345.remoteprompt.net/privkey.pem \
  --ssl-certfile ./certs/remoteprompt.net/config/live/abc12345.remoteprompt.net/fullchain.pem
```

---

### 8. 動作確認

ブラウザまたはcurlでアクセス：

```bash
curl https://abc12345.remoteprompt.net:8443/health
```

期待される応答：
```json
{"status":"ok","ssl_mode":"commercial",...}
```

---

## 証明書の自動更新

セットアップ完了後、証明書は毎日3:00 AMに自動更新チェックされます。

| 項目 | 内容 |
|------|------|
| 更新スクリプト | `scripts/renew-letsencrypt.sh` |
| 実行タイミング | 毎日 3:00 AM |
| ログ | `./certs/remoteprompt.net/config/logs/renewal.log` |

### 手動で更新を確認

```bash
./scripts/renew-letsencrypt.sh
```

---

## トラブルシューティング

### 証明書発行に失敗する

**原因**: DNS伝播が完了していない

**解決策**: 数分待ってから再試行

```bash
dig abc12345.remoteprompt.net
# IPアドレスが表示されることを確認
```

### サーバーにアクセスできない

**原因**: Tailscaleが停止している

**解決策**:
```bash
tailscale status
# 停止している場合
sudo tailscale up
```

### 「証明書が信頼されていない」エラー

**原因**: 自己署名証明書が使用されている

**解決策**: 正しいパスでLet's Encrypt証明書を指定しているか確認

```bash
ls -la ./certs/remoteprompt.net/config/live/
```

---

## ファイル構成

```
remote-job-server/
├── scripts/
│   ├── setup_letsencrypt.py     # 証明書セットアップ
│   └── renew-letsencrypt.sh     # 証明書更新スクリプト（自動生成）
├── certs/
│   └── remoteprompt.net/
│       └── config/
│           └── live/
│               └── <subdomain>.remoteprompt.net/
│                   ├── fullchain.pem
│                   └── privkey.pem
├── .env                          # 環境設定
└── main.py                       # サーバー本体
```

---

## セキュリティに関する注意

1. **APIキーは必ず変更する** - デフォルト値を使用しない
2. **Cloudflare APIトークンを他者に共有しない**
3. **secrets/ディレクトリをgit管理しない** - `.gitignore`に含まれていることを確認

---

## サポート

問題が発生した場合は、管理者に連絡してください。
