# OAuth認証機能 実装計画

**作成日**: 2025-12-01
**対象**: RemotePrompt サーバー / iOS アプリケーション
**要件**: マルチデバイス・マルチユーザー対応のためのOAuth認証導入

---

## 概要

### 背景

現在のRemotePromptはdeviceId（UUID）ベースでデータを識別しており、以下の課題がある：

1. **アプリ再インストール問題**: UserDefaults削除によるデータ消失（→Keychain対応で暫定解決）
2. **マルチデバイス非対応**: 同一ユーザーが複数デバイスで同じルームにアクセス不可
3. **共有利用不可**: 複数ユーザーで同一サーバーを利用する場合の識別が不可能
4. **セキュリティ**: VPN内利用を前提とした簡易認証のみ

### 目標

- ユーザー認証機能の追加（Apple Sign In / Google Sign In）
- deviceIdとuserIdの紐付け
- マルチデバイスでのデータ同期
- 既存データの移行（後方互換性維持）

### 推奨OAuthプロバイダー

| プロバイダー | 優先度 | 理由 |
|------------|--------|------|
| **Apple Sign In** | ⭐⭐⭐⭐⭐ | iOS/watchOSネイティブ統合、App Store要件 |
| **Google Sign In** | ⭐⭐⭐⭐ | 汎用性、既存アカウント活用 |
| **GitHub** | ⭐⭐⭐ | 開発者向け（将来対応可） |

---

## 実装フェーズ

### Phase 1: データベース設計・拡張

#### 1.1 Usersテーブル追加

- [ ] `remote-job-server/models.py`にUserモデル追加
  ```python
  class User(Base):
      __tablename__ = "users"

      id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
      email = Column(String(255), unique=True, nullable=False)
      provider = Column(String(20), nullable=False)  # 'apple', 'google', 'github'
      provider_id = Column(String(255), nullable=False)  # OAuthプロバイダーのユーザーID
      name = Column(String(255), nullable=True)
      profile_picture_url = Column(String(500), nullable=True)
      created_at = Column(DateTime, nullable=False, default=utcnow)
      updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

      # Relationships
      devices = relationship("Device", back_populates="user")
      rooms = relationship("Room", back_populates="user")

      __table_args__ = (
          UniqueConstraint('provider', 'provider_id', name='uq_user_provider'),
      )
  ```

#### 1.2 OAuthTokensテーブル追加

- [ ] `remote-job-server/models.py`にOAuthTokenモデル追加
  ```python
  class OAuthToken(Base):
      __tablename__ = "oauth_tokens"

      id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
      user_id = Column(String(36), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
      provider = Column(String(20), nullable=False)
      access_token_hash = Column(String(255), nullable=False)  # ハッシュ化して保存
      refresh_token_encrypted = Column(String(2000), nullable=True)  # 暗号化して保存
      expires_at = Column(DateTime, nullable=True)
      created_at = Column(DateTime, nullable=False, default=utcnow)
      updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)

      # Relationships
      user = relationship("User", back_populates="oauth_tokens")
  ```

#### 1.3 SessionsテーブルEll追加（JWTセッション管理）

- [ ] `remote-job-server/models.py`にSessionモデル追加
  ```python
  class Session(Base):
      __tablename__ = "sessions"

      id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
      user_id = Column(String(36), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
      device_id = Column(String(100), nullable=False)
      refresh_token_hash = Column(String(255), nullable=False)
      expires_at = Column(DateTime, nullable=False)
      created_at = Column(DateTime, nullable=False, default=utcnow)

      # Relationships
      user = relationship("User")
  ```

#### 1.4 既存テーブルへのuser_id追加

- [ ] Roomsテーブルにuser_id追加（nullable、移行期間中）
  ```python
  # Room model
  user_id = Column(String(36), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
  user = relationship("User", back_populates="rooms")
  ```

- [ ] Devicesテーブルにuser_id追加
  ```python
  # Device model
  user_id = Column(String(36), ForeignKey('users.id', ondelete='CASCADE'), nullable=True)
  user = relationship("User", back_populates="devices")
  ```

#### 1.5 マイグレーションスクリプト作成

- [ ] `remote-job-server/migrations/001_add_oauth_tables.py`作成
  - [ ] users, oauth_tokens, sessionsテーブル作成
  - [ ] rooms, devicesにuser_idカラム追加
  - [ ] ロールバック対応

---

### Phase 2: サーバー側OAuth実装

#### 2.1 認証ヘルパー拡張

- [ ] `remote-job-server/oauth_manager.py`新規作成
  - [ ] OAuthManagerクラス実装
    - [ ] Apple Sign In トークン検証
    - [ ] Google Sign In トークン検証
    - [ ] ユーザー情報取得
  - [ ] PKCE対応（認可コードフロー）
  - [ ] state パラメータ生成・検証（CSRF対策）

#### 2.2 JWT管理

- [ ] `remote-job-server/jwt_manager.py`新規作成
  - [ ] JWTManagerクラス実装
    - [ ] `create_access_token(user_id, device_id)` → 15分有効
    - [ ] `create_refresh_token(user_id, device_id)` → 30日有効
    - [ ] `verify_access_token(token)` → user_id, device_id返却
    - [ ] `refresh_tokens(refresh_token)` → 新しいトークンペア返却
  - [ ] トークン失効リスト管理（Redis推奨、SQLite fallback）

#### 2.3 認証エンドポイント追加

- [ ] `remote-job-server/main.py`に認証ルート追加
  ```python
  # Apple Sign In
  POST /auth/apple/callback
    - Request: { "identity_token": str, "authorization_code": str, "device_id": str }
    - Response: { "access_token": str, "refresh_token": str, "user": User }

  # Google Sign In
  POST /auth/google/callback
    - Request: { "id_token": str, "device_id": str }
    - Response: { "access_token": str, "refresh_token": str, "user": User }

  # トークン更新
  POST /auth/refresh
    - Request: { "refresh_token": str }
    - Response: { "access_token": str, "refresh_token": str }

  # ログアウト
  POST /auth/logout
    - Headers: Authorization: Bearer <access_token>
    - Response: { "success": true }

  # 現在のユーザー情報
  GET /auth/me
    - Headers: Authorization: Bearer <access_token>
    - Response: { "user": User, "devices": [Device] }
  ```

#### 2.4 認証ミドルウェア実装

- [ ] `remote-job-server/auth_middleware.py`新規作成
  - [ ] `get_current_user()`依存関数
    - [ ] Authorizationヘッダーからトークン抽出
    - [ ] JWTデコード・検証
    - [ ] ユーザー情報取得
  - [ ] `get_optional_user()`依存関数（移行期間用）
    - [ ] トークンあり → ユーザー認証
    - [ ] トークンなし → device_idベースの従来動作

#### 2.5 既存エンドポイントの認証対応

- [ ] 全エンドポイントに`get_optional_user()`追加（段階的移行）
  - [ ] `/rooms` - user_idまたはdevice_idでフィルタ
  - [ ] `/rooms/{room_id}/threads` - 所有権確認にuser_idを優先
  - [ ] `/jobs` - 認証済みユーザーのジョブ作成
  - [ ] その他全エンドポイント

#### 2.6 環境変数追加

- [ ] `.env`に以下を追加
  ```bash
  # OAuth Settings
  OAUTH_ENABLED=false  # 段階的有効化用

  # Apple Sign In
  APPLE_CLIENT_ID=com.yourteam.RemotePrompt
  APPLE_TEAM_ID=YYYYYYYYYY
  APPLE_KEY_ID=XXXXXXXXXX
  APPLE_KEY_PATH=/path/to/AuthKey.p8

  # Google Sign In
  GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
  GOOGLE_CLIENT_SECRET=xxx

  # JWT Settings
  JWT_SECRET_KEY=your-secret-key-here
  JWT_ACCESS_TOKEN_EXPIRE_MINUTES=15
  JWT_REFRESH_TOKEN_EXPIRE_DAYS=30
  ```

#### 2.7 依存ライブラリ追加

- [ ] `requirements.txt`に追加
  ```
  PyJWT>=2.8.0
  python-jose[cryptography]>=3.3.0
  httpx>=0.25.0
  cryptography>=41.0.0
  ```

---

### Phase 3: iOS側OAuth実装

#### 3.1 Apple Sign In実装

- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/AppleSignInManager.swift`新規作成
  - [ ] AppleSignInManagerクラス実装
    - [ ] `@Published var isAuthenticated: Bool`
    - [ ] `@Published var currentUser: User?`
    - [ ] `signIn()` → Apple認証フロー開始
    - [ ] `handleAuthorization(authorization: ASAuthorization)` → コールバック処理
    - [ ] `sendTokenToServer(identityToken:, authorizationCode:)` → サーバー認証
  - [ ] ASAuthorizationControllerDelegate実装
  - [ ] ASAuthorizationControllerPresentationContextProviding実装

#### 3.2 Google Sign In実装（オプション）

- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/GoogleSignInManager.swift`新規作成
  - [ ] Google Sign In SDK統合
  - [ ] GoogleSignInManagerクラス実装
    - [ ] `signIn()` → Google認証フロー開始
    - [ ] `handleCallback(url:)` → コールバック処理
    - [ ] `sendTokenToServer(idToken:)` → サーバー認証

#### 3.3 認証統合マネージャー

- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/AuthManager.swift`新規作成
  - [ ] AuthManagerクラス実装
    - [ ] `@Published var authState: AuthState` (unauthenticated/authenticated/loading)
    - [ ] `@Published var currentUser: User?`
    - [ ] `signInWithApple()` → Apple Sign In呼び出し
    - [ ] `signInWithGoogle()` → Google Sign In呼び出し
    - [ ] `signOut()` → ログアウト処理
    - [ ] `refreshTokensIfNeeded()` → トークン自動更新
  - [ ] Keychain統合
    - [ ] アクセストークン保存・取得
    - [ ] リフレッシュトークン保存・取得
    - [ ] トークン削除（ログアウト時）

#### 3.4 KeychainHelper拡張

- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/KeychainHelper.swift`拡張
  - [ ] `accessToken`キー追加
  - [ ] `refreshToken`キー追加
  - [ ] `userId`キー追加

#### 3.5 APIClient認証対応

- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Services/APIClient.swift`修正
  - [ ] `Authorization: Bearer <token>`ヘッダー追加
  - [ ] 401エラー時の自動トークン更新
  - [ ] トークン更新失敗時のログアウト処理
  - [ ] 認証状態に応じたリクエスト分岐（移行期間）

#### 3.6 ログイン画面UI

- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/Views/LoginView.swift`新規作成
  - [ ] Sign in with Appleボタン
  - [ ] Sign in with Googleボタン（オプション）
  - [ ] ゲストモード続行ボタン（移行期間）
  - [ ] ロゴ・アプリ説明

#### 3.7 アプリ起動フロー修正

- [ ] `iOS_WatchOS/RemotePrompt/RemotePrompt/RemotePromptApp.swift`修正
  - [ ] 起動時の認証状態チェック
  - [ ] 未認証→LoginView表示
  - [ ] 認証済み→ContentView表示
  - [ ] トークン自動更新の初期化

#### 3.8 Xcodeプロジェクト設定

- [ ] Signing & Capabilities
  - [ ] Sign in with Apple capability追加
- [ ] Info.plist
  - [ ] Google Sign In URL Scheme追加（使用する場合）

---

### Phase 4: データ移行・後方互換性

#### 4.1 既存データ移行戦略

- [ ] マイグレーションエンドポイント実装
  ```python
  POST /auth/migrate
    - Request: { "device_id": str }
    - Headers: Authorization: Bearer <access_token>
    - Response: { "migrated_rooms": int, "migrated_threads": int }
  ```
  - [ ] device_idで所有するrooms, threadsをuser_idに紐付け
  - [ ] 重複チェック（既にuser_idがある場合はスキップ）

#### 4.2 iOS側移行フロー

- [ ] 初回ログイン時の移行確認ダイアログ
  - [ ] 「このデバイスのデータをアカウントに紐付けますか？」
  - [ ] 「はい」→ マイグレーションAPI呼び出し
  - [ ] 「いいえ」→ 新規ユーザーとして開始

#### 4.3 後方互換性維持

- [ ] 移行期間（3-6ヶ月）のデュアルモード
  - [ ] 認証あり → user_idベース
  - [ ] 認証なし → device_idベース（従来動作）
- [ ] 移行完了後のdevice_id専用モード廃止フラグ

---

### Phase 5: セキュリティ強化

#### 5.1 トークンセキュリティ

- [ ] アクセストークン
  - [ ] 短い有効期限（15分）
  - [ ] HTTPSのみで送信
  - [ ] Keychain保存（iOS）
- [ ] リフレッシュトークン
  - [ ] 長い有効期限（30日）
  - [ ] ローテーション実装（使用時に新トークン発行）
  - [ ] サーバー側でハッシュ保存

#### 5.2 PKCE実装

- [ ] 認可コードフロー + PKCE
  - [ ] code_verifier生成（43-128文字のランダム文字列）
  - [ ] code_challenge生成（SHA256 + Base64URL）
  - [ ] サーバー側でcode_verifier検証

#### 5.3 セッション管理

- [ ] 同時ログインデバイス数制限（オプション）
- [ ] 強制ログアウト機能（全デバイス）
- [ ] 最終ログイン日時記録

#### 5.4 レート制限

- [ ] 認証エンドポイントへのレート制限
  - [ ] `/auth/*` - 10回/分/IP
  - [ ] 失敗時の指数バックオフ

---

### Phase 6: テスト・検証

#### 6.1 ユニットテスト

- [ ] `remote-job-server/tests/test_oauth.py`
  - [ ] Apple ID Token検証テスト
  - [ ] Google ID Token検証テスト
  - [ ] JWT生成・検証テスト
  - [ ] トークンリフレッシュテスト

#### 6.2 統合テスト

- [ ] `remote-job-server/tests/test_auth_flow.py`
  - [ ] 完全な認証フローテスト
  - [ ] マイグレーションテスト
  - [ ] 認証あり/なしの両モードテスト

#### 6.3 iOS UIテスト

- [ ] `iOS_WatchOS/RemotePrompt/RemotePromptUITests/AuthUITests.swift`
  - [ ] ログイン画面表示テスト
  - [ ] Apple Sign Inボタン動作テスト
  - [ ] 認証後の画面遷移テスト

#### 6.4 手動テスト

- [ ] Apple Sign In実機テスト
  - [ ] 初回ログイン
  - [ ] 再ログイン（トークン更新）
  - [ ] ログアウト
  - [ ] 複数デバイスでの同期
- [ ] データ移行テスト
  - [ ] 既存デバイスからのマイグレーション
  - [ ] マイグレーション後のデータアクセス

---

### Phase 7: ドキュメント・リリース

#### 7.1 ドキュメント更新

- [ ] `Docs/Specifications/Master_Specification.md`更新
  - [ ] 認証フロー図追加
  - [ ] APIエンドポイント追加
  - [ ] セキュリティ仕様追加

- [ ] `Docs/Specifications/OAuth_Setup_Guide.md`新規作成
  - [ ] Apple Developer Portal設定手順
  - [ ] Google Cloud Console設定手順
  - [ ] サーバー環境変数設定手順

#### 7.2 リリース計画

- [ ] Beta版リリース
  - [ ] TestFlight配信
  - [ ] 内部テスト（1週間）
- [ ] 段階的ロールアウト
  - [ ] OAUTH_ENABLED=falseでリリース（UIのみ）
  - [ ] 問題なければOAUTH_ENABLED=trueに変更
- [ ] 移行期間設定
  - [ ] 3-6ヶ月はdevice_idモードも維持
  - [ ] 移行完了後にレガシーモード廃止

---

## アーキテクチャ図

### 認証フロー（Apple Sign In）

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   iOS App       │     │  RemotePrompt    │     │  Apple Server   │
│                 │     │  Server          │     │                 │
└────────┬────────┘     └────────┬─────────┘     └────────┬────────┘
         │                       │                        │
         │  1. Sign in with Apple│                        │
         │───────────────────────────────────────────────>│
         │                       │                        │
         │  2. identity_token, authorization_code         │
         │<───────────────────────────────────────────────│
         │                       │                        │
         │  3. POST /auth/apple/callback                  │
         │──────────────────────>│                        │
         │                       │  4. Verify token       │
         │                       │───────────────────────>│
         │                       │                        │
         │                       │  5. Token valid + user │
         │                       │<───────────────────────│
         │                       │                        │
         │  6. access_token,     │                        │
         │     refresh_token,    │                        │
         │     user              │                        │
         │<──────────────────────│                        │
         │                       │                        │
         │  7. Store in Keychain │                        │
         │                       │                        │
         ▼                       ▼                        ▼
```

### データモデル関係図

```
┌───────────────────┐
│      User         │
├───────────────────┤
│ id                │
│ email             │◀──────────────┐
│ provider          │               │
│ provider_id       │               │
│ name              │               │
└─────────┬─────────┘               │
          │                         │
          │ 1:N                     │ 1:N
          ▼                         │
┌───────────────────┐     ┌─────────┴─────────┐
│     Device        │     │      Room         │
├───────────────────┤     ├───────────────────┤
│ device_id (PK)    │     │ id                │
│ user_id (FK)      │     │ user_id (FK)      │
│ device_token      │     │ device_id         │
│ device_name       │     │ name              │
└───────────────────┘     │ workspace_path    │
                          └─────────┬─────────┘
                                    │
                                    │ 1:N
                                    ▼
                          ┌───────────────────┐
                          │     Thread        │
                          ├───────────────────┤
                          │ id                │
                          │ room_id (FK)      │
                          │ device_id         │
                          │ name              │
                          └─────────┬─────────┘
                                    │
                                    │ 1:N
                                    ▼
                          ┌───────────────────┐
                          │      Job          │
                          ├───────────────────┤
                          │ id                │
                          │ thread_id (FK)    │
                          │ device_id         │
                          │ prompt            │
                          └───────────────────┘
```

---

## リスク・考慮事項

### 技術的リスク

| リスク | 発生確度 | 影響 | 対策 |
|--------|---------|------|------|
| Apple Review リジェクト | 低 | 高 | Sign in with Appleガイドライン厳守 |
| トークン管理バグ | 中 | 高 | 十分なテスト、セキュリティ監査 |
| 既存データ移行失敗 | 低 | 極高 | 段階的移行、ロールバック計画 |
| パフォーマンス低下 | 低 | 中 | JWT検証の最適化、キャッシュ |

### App Store要件

- **Sign in with Apple必須**: 他のサードパーティログイン（Google等）を提供する場合、Apple Sign Inも必須
- **プライバシーポリシー**: OAuth使用時は必須
- **データ削除機能**: ユーザーがアカウント削除を要求できる機能が必要

---

## 工数見積もり

| フェーズ | 作業内容 | 見積もり |
|---------|---------|---------|
| Phase 1 | DB設計・拡張 | 4-6時間 |
| Phase 2 | サーバー側OAuth実装 | 12-16時間 |
| Phase 3 | iOS側OAuth実装 | 10-14時間 |
| Phase 4 | データ移行・後方互換性 | 4-6時間 |
| Phase 5 | セキュリティ強化 | 4-6時間 |
| Phase 6 | テスト・検証 | 8-10時間 |
| Phase 7 | ドキュメント・リリース | 4-6時間 |
| **合計** | | **46-64時間** |

---

## 次のステップ

1. この計画のレビュー・承認
2. Apple Developer PortalでのSign in with Apple設定
3. Phase 1（DB設計）から順次実装開始
4. 各フェーズ完了時にチェックリスト更新

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|----------|---------|
| 2025-12-01 | v1.0 | 初版作成 |
