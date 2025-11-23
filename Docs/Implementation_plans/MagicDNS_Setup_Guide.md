# MagicDNS 設定ガイド (Tailscale)

作成日: 2025-11-23
想定環境: RemotePrompt 開発用 Tailnet（MacStudio 常時起動、iPhone/その他端末は Wi-Fi または Tailscale 接続）

## 1. 概要
MagicDNS は Tailscale が提供する内蔵 DNS 機能で、Tailnet 内の各ノードに自動で名前解決を提供する。mDNS を VPN に流さなくても `http://macstudio:35000` のようにホスト名でアクセスでき、外出先からも一貫した名前空間を利用できる。

## 2. 前提条件
- Tailnet の管理権限を持っていること（Admin Console にアクセス可能）。
- 各端末に Tailscale クライアントが導入済みでサインイン済み。
- RemotePrompt サーバ（MacStudio）が Tailscale に接続し続けていること。
- 追加料金: MagicDNS は全プランで利用可（追加課金なし）。

## 3. 設定手順 (Admin Console)
1. ブラウザで https://login.tailscale.com/admin にアクセスし、対象 Tailnet にサインイン。
2. 左メニューで **DNS** を開く。
3. **MagicDNS** トグルを **On** にする。
4. オプション: 短縮ホスト名を使う場合は "Override local DNS" を有効化（デフォルトで有効）。
5. 変更を保存。クライアントは自動で新しい DNS 設定を取得する。

## 4. クライアント側確認
- macOS / Linux: `tailscale status` でノード名が見えることを確認。
- 名前解決テスト: `ping macstudio` または `ping macstudio.tailnet-name.ts.net`。
- iOS: Tailscale アプリ > Settings > DNS で MagicDNS が Enabled になっていることを確認。

## 5. RemotePrompt での利用例
- サーバー API へ: `http://macstudio:35000/health` （例）
- iOS/WatchOS クライアント設定: ベースURLに MagicDNS 名を指定すれば、外出先でも同じ URL を使用可能。
- CLI での利用: `curl http://macstudio:35000/jobs` のように固定 IP を意識せずアクセス可能。

## 6. トラブルシュート
- 解決できない場合: `tailscale up --reset` で設定再取得、もしくはクライアントを再接続。
- DNS キャッシュクリア: macOS `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`。
- 依然として mDNS を要求するサービス(AirPlay等)は VPN 越しでは不可。代替として MagicDNS + 手動ポート指定を使用。

## 7. 補足: mDNS との違い
- mDNS: リンクローカルマルチキャスト依存で VPN を越えない。
- MagicDNS: Tailscale コントロールプレーン + ノード内 DNS で単一の名前空間を提供。サービス自動列挙は行わないため、ポートは明示が必要。

## 8. 今後の拡張アイデア
- サービスディスカバリを補完する場合、Consul/etcd などを併用してヘルスチェック付きの一覧を提供する。
- RemotePrompt サーバで簡易の `/services` エンドポイントを提供し、利用可能ポートを返す実装を検討。
