# APNs Push通知設定ガイド（RemotePrompt）

作成日: 2025-11-19
対象: Phase 4 プッシュ通知実装
担当: MacStudio Server + iOS Client

---

## 概要

Apple Push Notification service (APNs) を使用して、ジョブ完了時にiPhone/Apple Watchへ通知を送信する機能の設定手順。

---

## 1. APNsキーの保管

### 1.1 取得済みのAPNsキー

Apple Developer Portalから取得した `.p8` キーファイルを以下のように管理してください：

```bash
# 推奨ディレクトリ構造
~/Projects/RemotePrompt/
├── .env                    # 環境変数（gitignore済み）
└── secrets/                # 秘密鍵格納（gitignore必須）
    ├── AuthKey_XXXXXXXXXX.p8   # APNs認証キー
    └── README.md           # このディレクトリの説明
```

**重要**: `.p8` ファイルは絶対にGitにコミットしないでください。

### 1.2 gitignoreへの追加

```bash
# .gitignore に以下を追加（既に含まれている場合はスキップ）
secrets/
*.p8
.env
.env.local
```

### 1.3 環境変数の設定

`.env` ファイルに以下を記述してください：

```bash
# APNs認証情報
APNS_KEY_ID=XXXXXXXXXX              # Key ID（10文字の英数字）
APNS_TEAM_ID=YYYYYYYYYY             # Team ID（Apple Developer Portal）
APNS_KEY_PATH=/Users/macstudio/Projects/RemotePrompt/secrets/AuthKey_XXXXXXXXXX.p8
APNS_BUNDLE_ID=com.yourteam.RemotePrompt  # アプリのBundle Identifier

# APNs環境設定
APNS_ENVIRONMENT=sandbox            # 開発時: sandbox / 本番: production
```

---

## 2. サーバー側実装（Python FastAPI）

### 2.1 必要なライブラリ

```bash
# remote-job-server/ で実行
source .venv/bin/activate
pip install aioapns python-dotenv
pip freeze > requirements.txt
```

### 2.2 APNsクライアント実装

`remote-job-server/apns_manager.py` (新規作成):

```python
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

from aioapns import APNs, NotificationRequest
from dotenv import load_dotenv

load_dotenv()


class APNsManager:
    def __init__(self) -> None:
        key_path = Path(os.getenv("APNS_KEY_PATH", ""))
        if not key_path.exists():
            raise FileNotFoundError(f"APNs key not found: {key_path}")

        self.client = APNs(
            key=str(key_path),
            key_id=os.getenv("APNS_KEY_ID", ""),
            team_id=os.getenv("APNS_TEAM_ID", ""),
            topic=os.getenv("APNS_BUNDLE_ID", ""),
            use_sandbox=os.getenv("APNS_ENVIRONMENT") == "sandbox",
        )

    async def send_notification(
        self,
        device_token: str,
        title: str,
        body: str,
        badge: Optional[int] = None,
    ) -> bool:
        request = NotificationRequest(
            device_token=device_token,
            message={
                "aps": {
                    "alert": {"title": title, "body": body},
                    "badge": badge,
                    "sound": "default",
                }
            },
        )
        try:
            await self.client.send_notification(request)
            return True
        except Exception as e:
            print(f"[APNs] Failed to send: {e}")
            return False
```

### 2.3 ジョブ完了時の通知送信

`main.py` の `process_job` 関数に追加:

```python
from apns_manager import APNsManager

apns = APNsManager()

# ジョブ完了時（statusをsuccessに更新した後）
if job.notify_token:
    await apns.send_notification(
        device_token=job.notify_token,
        title="ジョブ完了",
        body=f"{job.runner} の実行が完了しました",
        badge=1,
    )
```

---

## 3. iOS側実装

### 3.1 Capabilityの有効化

Xcodeで `RemotePrompt` ターゲットを選択 → **Signing & Capabilities** → **+ Capability** → **Push Notifications** を追加。

### 3.2 デバイストークン取得

`iOS_WatchOS/RemotePrompt/RemotePrompt/RemotePromptApp.swift`:

```swift
import SwiftUI
import UserNotifications

@main
struct RemotePromptApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 APNs Device Token: \(token)")
        // TODO: サーバーに送信
        UserDefaults.standard.set(token, forKey: "apns_device_token")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for push: \(error)")
    }
}
```

### 3.3 ジョブ作成時にトークンを送信

`ChatViewModel.swift` の `sendMessage()` 修正:

```swift
let deviceToken = UserDefaults.standard.string(forKey: "apns_device_token")

let response = try await apiClient.createJob(
    runner: runner,
    prompt: prompt,
    deviceId: APIClient.getDeviceId(),
    notifyToken: deviceToken  // ✅ 追加
)
```

---

## 4. テスト手順

### 4.1 開発環境でのテスト

1. **実機でアプリを起動**（プッシュ通知はシミュレータ非対応）
2. コンソールから `APNs Device Token` をコピー
3. サーバー側で以下のテストスクリプトを実行：

```python
# test_apns.py
import asyncio
from apns_manager import APNsManager

async def test():
    apns = APNsManager()
    token = "YOUR_DEVICE_TOKEN_HERE"  # 実機から取得
    success = await apns.send_notification(
        device_token=token,
        title="テスト通知",
        body="APNs接続成功",
    )
    print(f"送信結果: {success}")

asyncio.run(test())
```

4. iPhoneで通知が届くことを確認

### 4.2 本番環境への移行

1. `.env` の `APNS_ENVIRONMENT` を `production` に変更
2. App Store Connectでアプリをリリース
3. 本番用証明書でビルド

---

## 5. トラブルシューティング

### 問題1: デバイストークンが取得できない

**原因**: Capability未設定 / プロビジョニングプロファイル不一致

**解決策**:
- Xcode → Signing & Capabilities → Push Notifications が追加されているか確認
- Automatically manage signing が有効か確認
- 実機で実行（シミュレータは不可）

### 問題2: 通知が届かない

**原因**:
- `.p8` キーのパスが間違っている
- Key ID / Team ID が間違っている
- Bundle IDが一致していない
- Sandbox/Production環境の不一致

**解決策**:
- `.env` の設定値を再確認
- `test_apns.py` でログを確認
- Apple Developer Portalで Key IDとTeam IDを再確認

---

## 6. セキュリティチェックリスト

- [ ] `.p8` ファイルが `.gitignore` に含まれている
- [ ] `.env` ファイルが `.gitignore` に含まれている
- [ ] `secrets/` ディレクトリが `.gitignore` に含まれている
- [ ] デバイストークンがサーバーのDBに暗号化されて保存されている（将来実装）
- [ ] 本番環境では環境変数を使用（`.env` ファイルは使わない）

---

## 7. 参考リンク

- [Apple Developer: APNs Overview](https://developer.apple.com/documentation/usernotifications)
- [aioapns Documentation](https://github.com/Fatal1ty/aioapns)
- [FastAPI Background Tasks](https://fastapi.tiangolo.com/tutorial/background-tasks/)

---

**現在のステータス**: Phase 1-2 完了、Phase 4（プッシュ通知）未実装

このガイドは Phase 4 実装時に参照してください。
