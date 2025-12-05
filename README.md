# RemotePrompt Server

[日本語](#日本語) | [English](#english)

---

## 日本語

RemotePrompt Serverは、iOSアプリからClaude Code、Codex、Gemini CLIをリモート操作するためのサーバーです。

### 特徴

- **複数のAI CLI対応**: Claude Code、OpenAI Codex、Google Gemini CLI
- **リアルタイム通信**: Server-Sent Events (SSE)によるストリーミング
- **自動検出**: Bonjour/mDNSによるローカルネットワーク自動検出
- **セキュア通信**: SSL/TLS暗号化（自己署名証明書の自動生成対応）
- **セッション管理**: 会話の継続が可能

### 必要環境

- **OS**: macOS（推奨）、Linux（実験的）、Windows（WSL2推奨）
- **Python**: 3.11以上
- **Node.js**: 18以上（CLI用）

### AI CLIのインストール

使用するCLIを少なくとも1つインストールしてください：

```bash
# Claude Code
npm install -g @anthropic-ai/claude-code

# OpenAI Codex
npm install -g @openai/codex

# Google Gemini CLI
npm install -g @anthropic-ai/claude-code  # TODO: 正式なパッケージ名に更新
```

### サーバーのインストール

```bash
# リポジトリをクローン
git clone https://github.com/Soconnect-Limited/RemotePromptServer.git
cd RemotePromptServer

# 仮想環境を作成
python3 -m venv .venv
source .venv/bin/activate

# 依存関係をインストール
pip install -r requirements.txt

# 設定ファイルを作成
cp .env.example .env

# 設定を編集
nano .env  # または任意のエディタ
```

### 設定

`.env`ファイルで以下を設定してください：

| 項目 | 説明 | 例 |
|------|------|-----|
| `API_KEY` | iOS認証用キー | `python3 -c "import secrets; print(secrets.token_urlsafe(32))"` |
| `SERVER_HOSTNAME` | サーバーのIPまたはホスト名 | `192.168.1.100` |
| `SERVER_SAN_IPS` | 証明書に含めるIP（カンマ区切り） | `192.168.1.100,127.0.0.1` |
| `SERVER_PORT` | サーバーポート | `8443` |

### 起動

```bash
# 仮想環境を有効化
source .venv/bin/activate

# サーバーを起動
python main.py
```

起動すると、証明書のフィンガープリントが表示されます。iOSアプリでの初回接続時にこのフィンガープリントを確認してください。

### iOSアプリとの接続

1. **Bonjour自動検出**: 同じネットワーク上でアプリを開くと自動的にサーバーが検出されます
2. **QRコード**: サーバー起動時に表示されるQRコードをスキャン
3. **手動設定**: サーバーのURL、APIキー、フィンガープリントを手動入力

### ドキュメント

- [サーバー版マニュアル](docs/manual/server/ja.html)
- [iOS版マニュアル](docs/manual/ios/ja.html)
- [プライバシーポリシー](docs/privacy/ja.html)

### ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照

---

## English

RemotePrompt Server enables remote control of Claude Code, Codex, and Gemini CLI from iOS app.

### Features

- **Multiple AI CLI Support**: Claude Code, OpenAI Codex, Google Gemini CLI
- **Real-time Communication**: Streaming via Server-Sent Events (SSE)
- **Auto Discovery**: Local network discovery via Bonjour/mDNS
- **Secure Communication**: SSL/TLS encryption with auto-generated self-signed certificates
- **Session Management**: Conversation continuity support

### Requirements

- **OS**: macOS (recommended), Linux (experimental), Windows (WSL2 recommended)
- **Python**: 3.11 or later
- **Node.js**: 18 or later (for CLI tools)

### Install AI CLI

Install at least one of the following CLI tools:

```bash
# Claude Code
npm install -g @anthropic-ai/claude-code

# OpenAI Codex
npm install -g @openai/codex

# Google Gemini CLI
npm install -g @anthropic-ai/claude-code  # TODO: Update to official package name
```

### Install Server

```bash
# Clone repository
git clone https://github.com/Soconnect-Limited/RemotePromptServer.git
cd RemotePromptServer

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create configuration file
cp .env.example .env

# Edit configuration
nano .env  # or your preferred editor
```

### Configuration

Configure the following in `.env`:

| Setting | Description | Example |
|---------|-------------|---------|
| `API_KEY` | Authentication key for iOS app | `python3 -c "import secrets; print(secrets.token_urlsafe(32))"` |
| `SERVER_HOSTNAME` | Server IP or hostname | `192.168.1.100` |
| `SERVER_SAN_IPS` | IPs for certificate (comma-separated) | `192.168.1.100,127.0.0.1` |
| `SERVER_PORT` | Server port | `8443` |

### Start Server

```bash
# Activate virtual environment
source .venv/bin/activate

# Start server
python main.py
```

On startup, the certificate fingerprint will be displayed. Verify this fingerprint when connecting from the iOS app for the first time.

### Connect from iOS App

1. **Bonjour Auto-Discovery**: Open the app on the same network to automatically discover the server
2. **QR Code**: Scan the QR code displayed on server startup
3. **Manual Configuration**: Manually enter server URL, API key, and fingerprint

### Documentation

- [Server Manual](docs/manual/server/en.html)
- [iOS Manual](docs/manual/ios/en.html)
- [Privacy Policy](docs/privacy/en.html)

### License

MIT License - See [LICENSE](LICENSE) for details
