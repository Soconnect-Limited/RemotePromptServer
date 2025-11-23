# Tailscale経由 Xcodeワイヤレス実機テスト実装計画

**作成日**: 2025-01-23
**目的**: TailscaleネットワークでiPhoneとMac Studioを接続し、Xcodeワイヤレスデバッグを実現する
**優先度**: 🟢 Low（開発効率化、必須ではない）
**工数**: 2.0時間

---

## 📋 概要

### 背景
- LAN内（192.168.11.x）でワイヤレス実機テスト可能
- Mac StudioはTailscaleネットワーク参加済み（100.100.30.35）
- 外出先からTailscale経由でiPhoneに実機デバッグ可能にする

### 技術的実現可能性
✅ 実現可能（MagicDNS有効化 + 手動IP指定で対応）

---

## ⚠️ 重要な制約

### 必須要件
- **初回USB接続必須**: 信頼関係確立のため（Apple仕様）
- **mDNS/Bonjour非対応**: TailscaleはデフォルトでBonjourをリレーしない → MagicDNSで代替
- **ポート62078**: Xcodeワイヤレスデバッグ専用ポート
- **Direct Connection推奨**: Relay経由は高レイテンシ（50-200ms）の可能性

### 前提条件
- Mac Studio: macOS 14.6.1, Tailscale導入済み（100.100.30.35）
- iPhone: iOS 15以降推奨
- Xcode: 14.0以降推奨（15.x推奨）
- Tailscaleアカウント: Mac Studioと同一アカウント使用

---

## ✅ 実装チェックリスト

### Phase 1: Tailscale環境設定（30分）

- [ ] MagicDNS有効化
  - [ ] https://login.tailscale.com/admin/dns にアクセス
  - [ ] "Enable MagicDNS" をON
  - [ ] Mac Studioで確認: `tailscale status | grep MagicDNS`
  - [ ] 出力に "MagicDNS: enabled" が表示されればOK

- [ ] iPhoneにTailscaleインストール
  - [ ] App Storeで "Tailscale" 検索・インストール
  - [ ] Mac Studioと同じアカウントでログイン
  - [ ] VPN構成プロファイルインストール許可
  - [ ] VPN接続確認（"Connected" 表示）

- [ ] Tailscale IP確認
  - [ ] iPhoneアプリでIPアドレス確認（例: 100.100.x.x）
  - [ ] **このIPをメモする**
  - [ ] Mac Studioからping疎通: `ping <iPhone_Tailscale_IP>`
  - [ ] Reply が返ってくればOK

- [ ] DNS解決確認（MagicDNS）
  - [ ] `nslookup <iphone-hostname>.tail-scale.ts.net`
  - [ ] IPアドレスが返却されればOK
  - [ ] 失敗時: DNSキャッシュクリア
    ```bash
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
    ```

---

### Phase 2: Xcode初回ペアリング（15分）

- [ ] USB接続・信頼関係確立
  - [ ] iPhoneをMac StudioにUSBケーブルで接続
  - [ ] iPhone画面ロック解除
  - [ ] Xcode → Window → Devices and Simulators (⇧⌘2)
  - [ ] 左側リストにiPhone表示確認
  - [ ] iPhone画面で "Trust This Computer?" → "Trust"
  - [ ] パスコード入力（必要に応じて）
  - [ ] Xcode側でiPhone詳細情報表示確認

- [ ] ワイヤレスデバッグ有効化
  - [ ] Devices and Simulators画面でiPhone選択
  - [ ] 右側パネルで "Connect via network" にチェック
  - [ ] デバイス名横にネットワークアイコン（地球儀マーク）表示待機（5-30秒）
  - [ ] ネットワークアイコン表示確認
  - [ ] USBケーブル取り外し
  - [ ] リストにiPhoneが残っていることを確認

---

### Phase 3: Tailscale経由接続設定（30分）

- [ ] LAN内ワイヤレス接続確認（ベースライン）
  - [ ] iPhone・Mac Studioを同一LAN（192.168.11.x）に接続
  - [ ] Xcode Devices and SimulatorsでiPhone表示確認
  - [ ] RemotePrompt.xcodeprojをビルド＆実行
  - [ ] Product → Run (⌘R)
  - [ ] ビルド時間測定（ベースライン）: ___秒
  - [ ] アプリ起動確認

- [ ] Tailscale接続テスト準備
  - [ ] iPhoneをLAN切断（Wi-Fiオフ、またはモバイルデータ通信のみ）
  - [ ] Tailscale VPN接続のみ有効
  - [ ] Mac Studioからping確認: `ping <iPhone_Tailscale_IP>`
  - [ ] Reply が返ってくることを確認

- [ ] MagicDNS自動認識テスト
  - [ ] Xcode Devices and Simulatorsを開く
  - [ ] 左側リスト確認
  - [ ] **期待**: `<iphone-hostname>.tail-scale.ts.net` として表示
  - [ ] 表示された場合 → デバイス選択 → "Connected" 状態確認 → **Phase 3-5へ**
  - [ ] 表示されない場合 → **Phase 3-4へ（手動IP指定）**

- [ ] 手動IP指定（MagicDNS失敗時のフォールバック）
  - [ ] ターミナルで以下を実行
    ```bash
    xcrun devicectl device add network \
      --name "iPhone (Tailscale)" \
      --address <iPhone_Tailscale_IP>:62078
    ```
  - [ ] **実例**:
    ```bash
    xcrun devicectl device add network \
      --name "iPhone (Tailscale)" \
      --address 100.100.50.123:62078
    ```
  - [ ] コマンド実行結果確認
    - 成功: "Device added successfully" 的なメッセージ
    - 失敗: エラーメッセージを記録
  - [ ] Xcode Devices and Simulatorsを再起動
  - [ ] 左側リストに "iPhone (Tailscale)" 表示確認
  - [ ] デバイス選択 → "Connected" 状態確認

- [ ] 接続安定性確認
  - [ ] Xcode Devices and Simulatorsでデバイス詳細確認
    - Connection: Network
    - Status: Connected
  - [ ] 5分間接続維持確認
    - Status が "Disconnected" に変わらないか監視
  - [ ] 切断された場合:
    - [ ] エラーメッセージを記録
    - [ ] Tailscale接続状態確認（iPhoneアプリで "Connected"）
    - [ ] 再接続試行

- [ ] Direct Connection vs Relay確認
  - [ ] Mac Studioで実行: `tailscale status | grep <iPhone_Tailscale_IP>`
  - [ ] 出力内容確認:
    - **"direct"** 表示: P2P直接接続（理想、低レイテンシ 5-20ms）
    - **"relay"** 表示: DERP Relay経由（高レイテンシ 50-200ms）
  - [ ] Relay経由の場合:
    - [ ] NAT/Firewall設定確認
    - [ ] ルーターのUPnP有効化検討
    - [ ] Direct接続確立まで待機（最大5分）

---

### Phase 4: 動作検証（30分）

- [ ] ビルド＆実行テスト
  - [ ] Xcodeでプロジェクトを開く（RemotePrompt.xcodeproj）
  - [ ] デバイス選択: iPhone (Tailscale)
  - [ ] Product → Clean Build Folder (⇧⌘K)
  - [ ] Product → Run (⌘R)
  - [ ] ビルド開始確認
  - [ ] ビルド完了時間測定
    - LAN内ワイヤレス: ___秒（ベースライン）
    - Tailscale経由: ___秒
  - [ ] アプリインストール確認
  - [ ] アプリ起動確認

- [ ] デバッグ機能テスト
  - [ ] ブレークポイント設定
    - ファイル: `ChatViewModel.swift`
    - 行: `sendMessage()` メソッド内
  - [ ] アプリでメッセージ送信操作
  - [ ] ブレークポイントで停止確認
  - [ ] 変数表示確認（Variables View）
    - `message` 変数の内容確認
  - [ ] Continue実行（⌃⌘Y）
  - [ ] アプリが正常動作継続確認

- [ ] Console表示確認
  - [ ] Xcode Console表示（⇧⌘C）
  - [ ] アプリでログ出力操作（例: メッセージ送信）
  - [ ] Console にログ出力確認
    - `DEBUG:` から始まるログ確認
  - [ ] ログのタイムスタンプ確認（リアルタイム出力されているか）

- [ ] パフォーマンス測定
  - [ ] ネットワークレイテンシ測定
    ```bash
    ping -c 10 <iPhone_Tailscale_IP>
    # 平均RTTを記録
    ```
    - LAN内: ___ms
    - Tailscale: ___ms
  - [ ] ビルド時間比較記録
    - LAN内: ___秒
    - Tailscale: ___秒
    - 増加率: ___%
  - [ ] デバッグレスポンス比較
    - ブレークポイント停止までの時間
    - LAN内: ___秒
    - Tailscale: ___秒

- [ ] 実用性評価
  - [ ] 以下の基準で判定
    | 項目 | 判定基準 |
    |------|---------|
    | ✅ 実用的 | レイテンシ<20ms、ビルド時間<LAN内の1.5倍 |
    | ⚠️ 条件付き | レイテンシ20-50ms、特定用途でのみ使用 |
    | ❌ 非推奨 | レイテンシ>50ms、LAN内のみ使用 |
  - [ ] 最終判定: ___

---

## 🚨 トラブルシューティング

### エラー1: "Device not found"

**原因**: Xcodeがデバイスを認識できていない

**解決策**:
1. [ ] iPhoneのTailscale VPN接続確認
   - Tailscaleアプリで "Connected" 表示確認
2. [ ] Mac Studioからping疎通確認
   ```bash
   ping <iPhone_Tailscale_IP>
   ```
3. [ ] Xcode再起動
4. [ ] iPhone再起動
5. [ ] 解決した場合、原因を記録

---

### エラー2: "Unable to establish connection"

**原因**: ネットワーク接続はあるが、デバッグプロトコルが失敗

**解決策**:
1. [ ] ポート62078疎通確認
   ```bash
   nc -zv <iPhone_Tailscale_IP> 62078
   ```
   - 成功: "Connection to xxx succeeded"
   - 失敗: Firewall設定確認へ
2. [ ] iPhoneで "Connect via network" 再有効化
   - USB再接続 → 再度チェック
3. [ ] Developer Mode確認（iOS 16以降）
   - 設定 → プライバシーとセキュリティ → デベロッパモード → ON

---

### エラー3: "Connection timed out"

**原因**: Tailscale経由のレイテンシが高すぎる

**解決策**:
1. [ ] Tailscale接続タイプ確認
   ```bash
   tailscale status | grep <iPhone_Tailscale_IP>
   # "direct" または "relay" を確認
   ```
2. [ ] Relay経由の場合:
   - [ ] NAT/Firewall設定確認
   - [ ] ルーターのUPnP有効化
   - [ ] Direct接続確立待機（5-10分）
3. [ ] Firewall設定確認
   - Mac Studio: システム環境設定 → セキュリティとプライバシー → Firewall
   - 必要に応じてXcodeを許可リストに追加

---

### エラー4: MagicDNS名前解決失敗

**原因**: MagicDNSが正しく設定されていない

**解決策**:
1. [ ] MagicDNS有効確認
   ```bash
   tailscale status | grep MagicDNS
   # "MagicDNS: enabled" を確認
   ```
2. [ ] 無効の場合、有効化
   - https://login.tailscale.com/admin/dns → Enable MagicDNS
3. [ ] DNS キャッシュクリア
   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder
   ```
4. [ ] 手動IP指定に切り替え（Phase 3-4参照）

---

## 📊 完了基準

### Phase 1完了基準
- [ ] MagicDNS有効化完了
- [ ] iPhoneがTailscaleネットワーク参加
- [ ] Mac StudioからiPhoneにping疎通成功

### Phase 2完了基準
- [ ] USB経由で信頼関係確立
- [ ] "Connect via network" 有効化成功
- [ ] ネットワークアイコン表示確認

### Phase 3完了基準
- [ ] Tailscale経由でXcodeがiPhone認識
- [ ] MagicDNSまたは手動IP指定で接続成功
- [ ] 5分間接続維持確認

### Phase 4完了基準
- [ ] ビルド＆実行成功
- [ ] デバッグ機能正常動作
- [ ] パフォーマンス測定完了
- [ ] 実用性評価完了

### 全体完了基準
- [ ] Phase 1-4のすべての完了基準を満たす
- [ ] パフォーマンス測定結果が記録されている
- [ ] 実用性評価完了（LAN内 vs Tailscale）
- [ ] トラブルシューティング手順が確認されている

---

## 📝 参考資料

### Apple公式
- [Xcode Wireless Debugging](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device)
- [devicectl command reference](https://developer.apple.com/documentation/xcode/devicectl)

### Tailscale公式
- [MagicDNS Setup](https://tailscale.com/kb/1081/magicdns)
- [Tailscale iOS App](https://tailscale.com/kb/1020/install-ios)

### コミュニティ
- [Tailscale GitHub Discussions](https://github.com/tailscale/tailscale/discussions)
- Stack Overflow: "Xcode wireless debugging over VPN"

---

**更新日**: 2025-01-23
**ステータス**: 実装待ち
