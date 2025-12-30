# Remote Job Server

RemotePrompt iOS/watchOSアプリ用のバックエンドサーバー。
AI CLIツール（Claude Code, Codex CLI, Gemini CLI）をiOSからリモート操作できます。

## 目次

- [セットアップ](#セットアップ)
- [SSL証明書の発行](#ssl証明書の発行)
- [更新方法](#更新方法)
- [サーバーの再起動](#サーバーの再起動)
- [設定](#設定)
- [トラブルシューティング](#トラブルシューティング)

---

## セットアップ

```bash
# リポジトリをクローン
cd ~
git clone https://github.com/Soconnect-Limited/RemotePromptServer.git
cd ~/RemotePromptServer

# 仮想環境を作成
python3 -m venv .venv
source .venv/bin/activate

# 依存関係をインストール
pip install -r requirements.txt

# 環境変数を設定
cp .env.example .env
# .envファイルを編集して API_KEY を設定

# サーバーを起動
python main.py
```

---

## SSL証明書の発行

### 自己署名証明書（デフォルト）

初回起動時に自動生成されます。ローカルネットワーク内での利用に適しています。

iOSアプリ側で証明書の確認ダイアログが表示されるので、信頼して接続してください。

### Let's Encrypt証明書（推奨）

正規のSSL証明書を使用する場合、以下の手順で発行できます。

#### 前提条件

1. 管理者にTailscale IPを伝え、サブドメインを発行してもらう
2. ポート80が一時的に使用可能であること

#### 手順

1. **Tailscale IPを確認**
   ```bash
   tailscale ip -4
   ```
   このIPアドレスを管理者に伝えてください。

2. **管理者からサブドメインを受け取る**

   例: `abc12345.remoteprompt.net`

3. **DNS解決を確認**
   ```bash
   dig abc12345.remoteprompt.net
   ```
   あなたのIPアドレスが表示されればOK。

4. **証明書発行スクリプトを実行**
   ```bash
   cd ~/RemotePromptServer
   source .venv/bin/activate
   python3 scripts/setup_letsencrypt.py abc12345
   ```

   スクリプトが自動的に:
   - certbotをインストール
   - Let's Encrypt証明書を発行（HTTPチャレンジ）
   - `.env`ファイルを更新
   - 自動更新を設定（毎日3:00 AM）

5. **サーバーを起動**
   ```bash
   python main.py
   ```

6. **動作確認**
   ```bash
   curl https://abc12345.remoteprompt.net:8443/health
   ```

#### 証明書の手動更新

```bash
./scripts/renew-letsencrypt.sh
```

---

## 更新方法

```bash
cd ~/RemotePromptServer

# 最新版を取得
git pull origin main

# 依存関係を更新
source .venv/bin/activate
pip install -r requirements.txt

# サーバーを再起動（下記参照）
```

---

## サーバーの再起動

### 方法1: プロセスを探して停止

```bash
# 実行中のサーバープロセスを確認
ps aux | grep "python main.py"

# プロセスを停止（PIDは上記で確認した数字）
kill <PID>

# サーバーを起動
cd ~/RemotePromptServer
source .venv/bin/activate
python main.py
```

### 方法2: ポートを使用しているプロセスを停止

```bash
# 8443ポートを使用しているプロセスを確認
lsof -i :8443

# プロセスを停止
kill <PID>

# サーバーを起動
cd ~/RemotePromptServer
source .venv/bin/activate
python main.py
```

### 方法3: 一括コマンド

```bash
# 停止→更新→起動を一括実行
pkill -f "python main.py" ; cd ~/RemotePromptServer && git pull origin main && source .venv/bin/activate && pip install -r requirements.txt && python main.py
```

---

## 設定

`.env.example`を参考に`.env`ファイルを作成してください。

主な設定項目：

| 項目 | 説明 | デフォルト |
|------|------|-----------|
| `API_KEY` | クライアント認証用のAPIキー | **必須** |
| `SERVER_PORT` | サーバーポート | 8443 |
| `SSL_MODE` | 証明書モード（`auto`, `self_signed`, `commercial`） | auto |
| `BONJOUR_ENABLED` | ローカルネットワーク自動検出 | true |

※ このサーバーはCLI（Claude Code, Codex CLI等）をリモート操作するためのものです。各AIサービスのAPIキーはサーバー側ではなく、CLIがインストールされたマシン上で設定します。

---

## ファイル構成

```
RemotePromptServer/
├── main.py                      # サーバー本体
├── .env                         # 環境設定
├── .env.example                 # 環境設定テンプレート
├── certs/                       # SSL証明書
├── scripts/
│   ├── setup_letsencrypt.py    # Let's Encrypt証明書発行
│   └── renew-letsencrypt.sh    # 証明書更新スクリプト
└── utils/                       # ユーティリティ
```

---

## トラブルシューティング

### サーバーにアクセスできない

**確認事項**:
1. サーバーが起動しているか: `ps aux | grep "python main.py"`
2. ポートが開いているか: `lsof -i :8443`
3. ファイアウォール設定

### 「証明書が信頼されていない」エラー

自己署名証明書を使用している場合は正常です。iOSアプリで証明書を信頼してください。

正規証明書を使用している場合は、パスが正しいか確認：
```bash
ls -la ./certs/remoteprompt.net/config/live/
```

### 証明書発行に失敗する

**考えられる原因**:
1. ポート80が別のプロセスで使用中
2. ファイアウォールでポート80がブロックされている
3. DNSがまだ伝播していない（数分待ってから再試行）

```bash
# ポート80の使用状況を確認
lsof -i :80

# DNSを確認
dig abc12345.remoteprompt.net
```

---

## セキュリティに関する注意

1. **APIキーは必ず変更する** - デフォルト値を使用しない
2. **APIキーを他者に共有しない** - 各ユーザーが独自のキーを設定
3. **.envファイルをgit管理しない** - `.gitignore`に含まれていることを確認

---

## ライセンス

MIT License
