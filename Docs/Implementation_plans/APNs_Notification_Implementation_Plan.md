# AI推論完了時のプッシュ通知機能 実装計画

**作成日**: 2025-11-24
**対象**: RemotePrompt iOS/watchOS アプリケーション
**要件**: AI推論（job）完了時にiPhone/Apple Watchへプッシュ通知を送信

---

## 概要

### 背景

ユーザーからのリクエスト:「AIの推論が終わった時に通知が欲しい」

既に`notify_token`フィールドはDB・APIに実装済み。APNs実装ガイドも用意済み。
本計画では実際の通知送信処理を実装する。

### 目標

- サーバー側: job完了時にAPNsでプッシュ通知送信
- iOS/watchOS側: APNsデバイストークン取得・送信、通知受信

---

## 実装フェーズ

### Phase 1: サーバー側APNs実装 ✅ 完了 (2025-11-24)

#### 1.1 apns_manager.py作成

- [x] `remote-job-server/apns_manager.py`を新規作成
- [x] APNsManagerクラス実装
  - [x] `.env`からAPNs認証情報読み込み
  - [x] `aioapns`クライアント初期化
  - [x] `send_notification()`メソッド実装
- [x] エラーハンドリング（.p8ファイル不在、送信失敗）

#### 1.2 job_manager.pyに通知送信処理追加

- [x] `APNsManager`をインポート
- [x] `process_job()`メソッドで:
  - [x] job完了時（success/failed両方）に通知送信
  - [x] `job.notify_token`が存在する場合のみ実行
  - [x] 通知タイトル:「ジョブ完了」
  - [x] 通知本文: runner名と結果（success/failed）
- [x] 例外時（通知失敗）でもjob処理は継続

#### 1.3 .env設定追加

- [x] `.env`に以下を追加（コメントアウト状態）:
  ```bash
  # APNs認証情報
  # APNS_KEY_ID=XXXXXXXXXX
  # APNS_TEAM_ID=YYYYYYYYYY
  # APNS_KEY_PATH=/Users/macstudio/Projects/RemotePrompt/secrets/AuthKey_XXXXXXXXXX.p8
  # APNS_BUNDLE_ID=com.yourteam.RemotePrompt
  # APNS_ENVIRONMENT=sandbox
  ```

#### 1.4 依存ライブラリ追加

- [x] `requirements.txt`に`aioapns==3.2.0`追加（PyAPNs2から変更）
- [ ] `pip install aioapns`実行（次回サーバー起動時）

---

### Phase 2: iOS/watchOS側実装 ✅ 完了 (2025-11-24)

#### 2.1 AppDelegate追加

- [x] `RemotePromptApp.swift`に`UIApplicationDelegateAdaptor`追加
- [x] `AppDelegate`クラス作成:
  - [x] `didFinishLaunchingWithOptions`: UNUserNotificationCenterで権限リクエスト
  - [x] `registerForRemoteNotifications()`呼び出し
  - [x] `didRegisterForRemoteNotificationsWithDeviceToken`: トークンを16進数文字列に変換してUserDefaults保存
  - [x] `didFailToRegisterForRemoteNotificationsWithError`: エラーログ出力

#### 2.2 Xcodeプロジェクト設定

- [ ] Signing & Capabilities → Push Notifications 追加
- [ ] Bundle Identifierが`.env`の`APNS_BUNDLE_ID`と一致することを確認

#### 2.3 APIClientにnotify_token送信処理追加

- [x] `createJob()`メソッドで:
  - [x] UserDefaultsから`apns_device_token`取得
  - [x] `CreateJobRequest`の`notifyToken`パラメータに渡す

---

### Phase 3: セットアップ・テスト (1-2時間)

#### 3.1 APNsキーの取得と設定

- [ ] Apple Developer Portal → Certificates, Identifiers & Profiles
- [ ] Keys → 「+」ボタン → Apple Push Notifications service (APNs) にチェック
- [ ] Continue → Register → Download (.p8ファイル)
- [ ] Key IDとTeam IDをメモ
- [ ] `.p8`ファイルを`~/Projects/RemotePrompt/secrets/`に保存
- [ ] `.env`のAPNs設定をコメント解除して実際の値を記入
- [ ] `.gitignore`に`secrets/`が含まれていることを確認

#### 3.2 Xcodeプロジェクト設定

- [ ] Xcodeで`RemotePrompt`ターゲットを選択
- [ ] Signing & Capabilities → Push Notifications 追加
- [ ] Bundle Identifierを`.env`の`APNS_BUNDLE_ID`と一致させる

#### 3.3 サーバー再起動

- [ ] `cd remote-job-server && pip install -r requirements.txt`
- [ ] サーバー再起動

#### 3.4 実機テスト

- [ ] iPhoneでアプリ起動（シミュレータではAPNs非対応）
- [ ] 通知許可ダイアログで「許可」を選択
- [ ] Xcodeコンソールで「📱 APNs Device Token: xxxxxxxx」を確認
- [ ] Claudeにメッセージ送信
- [ ] job完了時に通知が届くことを確認

#### 3.5 エラーケーステスト

- [ ] APNs設定不正時（.p8ファイル不在）
- [ ] デバイストークン不正時
- [ ] ネットワークエラー時

#### 3.6 watchOSテスト

- [ ] Apple Watch単体でアプリ起動
- [ ] 通知がWatchに届くことを確認

---

## セキュリティチェックリスト

- [ ] `.p8`ファイルが`.gitignore`に含まれている
- [ ] `.env`ファイルが`.gitignore`に含まれている
- [ ] `secrets/`ディレクトリが`.gitignore`に含まれている
- [ ] APNs送信失敗時もjob処理が継続する

---

## 完了条件

- [x] apns_manager.py実装完了
- [x] job_manager.pyに通知送信処理追加
- [x] iOS AppDelegate実装完了
- [x] ChatViewModelにnotify_token送信処理追加
- [ ] 実機でjob完了時に通知受信確認
- [ ] エラーケーステスト完了

---

## 参考情報

- [APNs_Setup_Guide.md](./APNs_Setup_Guide.md) - APNs設定の詳細手順
- [Apple Developer: APNs Overview](https://developer.apple.com/documentation/usernotifications)
- [aioapns Documentation](https://github.com/Fatal1ty/aioapns)

---

## 備考

### APNsキーの取得方法（未取得の場合）

1. Apple Developer Portal → Certificates, Identifiers & Profiles
2. Keys → 「+」ボタン → Apple Push Notifications service (APNs) にチェック
3. Continue → Register → Download (.p8ファイル)
4. Key IDとTeam IDをメモ
5. `.p8`ファイルを`~/Projects/RemotePrompt/secrets/`に保存

### 本番環境への移行

1. `.env`の`APNS_ENVIRONMENT`を`production`に変更
2. App Store Connectでアプリをリリース
3. 本番用証明書でビルド
