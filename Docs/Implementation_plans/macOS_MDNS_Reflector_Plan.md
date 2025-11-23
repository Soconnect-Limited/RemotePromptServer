# macOS mDNS Reflector 導入計画 (Tailscale 外出先から Bonjour を見るための非公式手段)

作成日: 2025-11-23
想定環境: RemotePrompt 開発用 Mac (常時起動) に Tailscale 接続済み。外出先端末も Tailscale 経由で接続。iPhone は既に開発用にペアリング済み。

## 1. 目的
- Tailscale は mDNS/Bonjour をトンネルしないため、外出先からワイヤレス実機デバッグ用の Bonjour サービスが見えない問題を緩和する。
- macOS 上に mDNS リフレクタを立て、`utun*`(Tailscale) と `en0`/`en1`(LAN/Wi‑Fi) 間で 224.0.0.251:5353 を中継し、外出先から Bonjour ブラウズを試みる。
- 非公式・ベストエフォートであり安定性は保証しない。

## 2. 前提条件
- Mac に Tailscale クライアント導入・サインイン済み（utun インターフェースが存在）。
- Homebrew インストール済み。
- Tailnet ACL でアクセス元ノードを限定できること。
- セキュリティより利便性を優先し、一時的/検証目的で運用することを理解していること。

## 3. 導入ステップ
### 3.1 パッケージ導入
```bash
brew install mdns-repeater
```

### 3.2 Tailscale IF 自動検出 & 手動起動例
```bash
#!/bin/zsh
TS_IF=$(ifconfig | awk '/^utun/ {cur=$1} /100\.64\./ {print cur; exit}')
LAN_IF=en0   # 有線/無線に応じて en1 などへ変更
if [ -z "$TS_IF" ]; then
  echo "Tailscale interface not found" >&2; exit 1
fi
echo "using $TS_IF -> $LAN_IF"
sudo mdns-repeater $TS_IF $LAN_IF
```
- `100.64.` は Tailnet CGN 範囲。必要に応じて `awk` の条件を調整。

### 3.3 launchd 自動起動（雛形）
1. `/usr/local/bin/mdns-repeater` のパスを確認 (`which mdns-repeater`).
2. `/Library/LaunchDaemons/com.local.mdns-repeater.plist` を作成（root権限）。
   - 起動時に utun を動的検出するよう、上記スクリプトを `/usr/local/sbin/mdns-reflector.sh` などに置き plist から呼び出す。
3. plist 例（簡略、必要に応じて調整）:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.mdns-repeater</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/sbin/mdns-reflector.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/mdns-reflector.log</string>
  <key>StandardErrorPath</key><string>/var/log/mdns-reflector.err</string>
</dict>
</plist>
```
4. 反映:
```bash
sudo launchctl load /Library/LaunchDaemons/com.local.mdns-repeater.plist
```

## 4. 動作確認
- 外出先端末で Tailscale 接続後、macOS なら `dns-sd -B _apple-mobdev2._tcp` を実行し、デバイスが列挙されるか確認。
- Xcode のデバイス一覧にターゲット iPhone が現れるか確認。
- 表示されない場合は utun 番号や LAN インターフェース名を確認し、再起動。

## 5. リスク・注意
- 非公式機能であり、OSアップデートやutun番号変動で容易に壊れる。
- mDNS を Tailnet に露出するため、Tailnet ACL で許可ノードを最小限にし、不要時は launchd を unload して無効化。
- パケット転送による負荷は小さいが、デバッグ時以外は停止推奨。

## 6. 代替案
- 小型 Linux/VM に Avahi reflector を常駐させる（IF 名が固定で管理しやすい）。
- 安定性重視なら USB 接続のまま Mac をリモート操作、または TestFlight 配信に切り替える。

## 7. 今後のフォロー
- 実機テスト時の成功/失敗事例を追記し、安定度を評価。
- うまくいかない場合は mDNS 以外の遠隔実行パス（REST API + MagicDNS + 固定ポート）へ移行検討。
