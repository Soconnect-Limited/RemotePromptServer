# 管理者向け：サブドメイン発行ガイド

## 概要

テストユーザーに専用のサブドメイン（`xxxxx.remoteprompt.net`）を発行する手順です。

---

## 前提条件

- Cloudflare APIトークンが設定済み（`secrets/cloudflare.ini`）
- Python仮想環境が有効

---

## 発行手順

### 1. ユーザーからTailscale IPアドレスを取得

ユーザーに以下を確認してもらう：

```bash
tailscale ip -4
```

例: `100.72.251.35`

### 2. サブドメイン発行ツールを実行

```bash
cd /Users/macstudio/Projects/RemotePrompt/remote-job-server
source .venv/bin/activate
python scripts/register_subdomain.py
```

### 3. IPアドレスを入力

```
============================================================
  RemotePrompt サブドメイン発行ツール
============================================================

Tailscale IPアドレスを入力 (100.x.x.x): 100.72.251.35

IPアドレス: 100.72.251.35
サブドメインを発行しています...

============================================================
  発行完了!
============================================================

  サブドメイン: abc12345
  フルドメイン: abc12345.remoteprompt.net
  IPアドレス:   100.72.251.35

  サーバーURL:  https://abc12345.remoteprompt.net:8443

============================================================
```

### 4. ユーザーに共有する情報

| 項目 | 例 |
|------|-----|
| サブドメイン名 | `abc12345` |
| サーバーURL | `https://abc12345.remoteprompt.net:8443` |
| Cloudflare APIトークン | `secrets/cloudflare.ini`の内容 |
| ユーザーガイドURL | `Docs/User_Server_Setup_Guide.md` |

---

## 発行済みサブドメインの確認

CloudflareダッシュボードでDNSレコードを確認：

1. https://dash.cloudflare.com にログイン
2. `remoteprompt.net` を選択
3. DNS → レコード

---

## サブドメインの削除

Cloudflareダッシュボードで該当のAレコードを削除してください。

---

## トラブルシューティング

### Cloudflare APIエラー

```
エラー: Cloudflare APIエラー - ...
```

**解決策**: APIトークンの権限を確認（Zone DNS Edit が必要）

### 重複エラー

```
Subdomain 'xxx' already exists
```

**解決策**: 別のIPアドレスで再実行するか、Cloudflareで既存レコードを削除
