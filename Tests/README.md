# Tests ディレクトリ

このディレクトリにはプロジェクトの各種テストスクリプトを保管します。

## ディレクトリ構成

```
Tests/
├── README.md                    # このファイル
└── pty_investigation/           # PTY永続セッション調査用テストスクリプト
    ├── test_claude.exp          # Claude Code Expectスクリプト
    ├── test_claude_final.exp    # Claude Code 対話型テスト
    ├── test_pty_interactive.py  # PTY対話テスト(Python)
    └── test_pty_prompts.py      # PTYプロンプト記号検出テスト
```

## pty_investigation/

**目的**: PTY(疑似端末)を使用したClaude Code / Codex CLIの対話モード制御の実現可能性を検証

**調査結果**: [Docs/Investigation_Report.md](../Docs/Investigation_Report.md) を参照

**結論**:
- PTY経由の対話モード制御は実装困難
- 非対話モード(`--print` / `exec`)の使用を推奨

### テストスクリプト

#### test_pty_prompts.py
PTY経由でClaude CodeとCodexを起動し、プロンプト記号を検出するテスト。

```bash
python3 Tests/pty_investigation/test_pty_prompts.py
```

#### test_pty_interactive.py
信頼確認ダイアログを自動処理してプロンプト記号を確認するテスト。

```bash
python3 Tests/pty_investigation/test_pty_interactive.py
```

#### test_claude.exp
Expectスクリプトを使用したClaude Codeのプロンプト検出テスト。

```bash
./Tests/pty_investigation/test_claude.exp
```

#### test_claude_final.exp
Expectスクリプトによる対話型テスト(最終版)。

```bash
./Tests/pty_investigation/test_claude_final.exp
```

---

## テスト追加ガイドライン

新しいテストスクリプトを追加する場合:

1. **カテゴリ別にサブディレクトリを作成**
   ```bash
   mkdir -p Tests/<category_name>
   ```

2. **テストスクリプトには説明的な名前を付ける**
   - 良い例: `test_api_authentication.py`
   - 悪い例: `test1.py`

3. **README.mdを更新**
   - 新しいテストの目的と使用方法を記載

4. **実行権限を付与**
   ```bash
   chmod +x Tests/<category_name>/<script_name>
   ```

5. **CLAUDE.mdとAGENTS.mdに記載**
   - テストディレクトリの構成を最新に保つ

---

**作成日**: 2025-11-17
**最終更新**: 2025-11-17
