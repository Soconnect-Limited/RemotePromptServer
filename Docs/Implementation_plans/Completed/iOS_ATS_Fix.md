# iOS App Transport Security (ATS) 修正手順

作成日: 2025-11-19
問題: HTTP接続が ATS ポリシーで拒否される

## エラー内容

```
The resource could not be loaded because the App Transport Security policy
requires the use of a secure connection
```

## 原因

iOSは デフォルトで HTTPS のみ許可し、HTTP 接続を拒否します。
現在のサーバーURL: `http://100.100.30.35:35000` (HTTP)

## 解決方法 (Xcode GUI)

### 手順1: Xcodeでプロジェクトを開く

```bash
open /Users/macstudio/Projects/RemotePrompt/iOS_WatchOS/RemotePrompt/RemotePrompt.xcodeproj
```

### 手順2: Info.plist 設定を追加

1. Xcode左のナビゲーターで **RemotePrompt** プロジェクトをクリック
2. **TARGETS** → **RemotePrompt** を選択
3. **Info** タブをクリック
4. **Custom iOS Target Properties** セクションで、右クリック → **Add Row**
5. 以下のキーと値を追加:

#### 追加する設定

```
Key: App Transport Security Settings (NSAppTransportSecurity)
Type: Dictionary

  └─ Key: Allow Arbitrary Loads (NSAllowsArbitraryLoads)
     Type: Boolean
     Value: NO

  └─ Key: Exception Domains (NSExceptionDomains)
     Type: Dictionary

       └─ Key: 100.100.30.35
          Type: Dictionary

            └─ Key: NSExceptionAllowsInsecureHTTPLoads
               Type: Boolean
               Value: YES

            └─ Key: NSIncludesSubdomains
               Type: Boolean
               Value: YES
```

### 手順3: プロジェクトを再ビルド

```bash
# Xcode で Command+B
# または
xcodebuild -scheme RemotePrompt -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## 代替方法: Info.plist ファイル直接編集

もしプロジェクト設定で `Info.plist` ファイルが生成されている場合:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>100.100.30.35</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

## セキュリティに関する注意

**本番環境では HTTPS を使用してください。**

この設定は開発環境専用です。本番リリース時には:

1. サーバーに SSL証明書を設定 (Let's Encrypt等)
2. `https://` URL に変更
3. ATS 例外設定を削除

## 確認方法

再ビルド後、シミュレータでメッセージを送信してください。
HTTP接続が許可され、ジョブが正常に作成されるはずです。

## トラブルシューティング

### エラーが継続する場合

1. **クリーンビルド**: Xcode → Product → Clean Build Folder (⌘⇧K)
2. **シミュレータリセット**: Simulator → Device → Erase All Content and Settings
3. **キャッシュクリア**: `rm -rf ~/Library/Developer/Xcode/DerivedData/*`
