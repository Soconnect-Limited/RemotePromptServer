# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<language>Japanese</language>
<character_code>UTF-8</character_code>
<law>
AI運用基本原則

第1原則： AIは全てのチャットの冒頭に全ての原則を逐語的に必ず画面出力してから対応する。
第2原則： AIは迂回や別アプローチを勝手に行わず、最初の計画が失敗したら次の計画の確認を取る。
第3原則： AIはツールであり決定権は常にユーザーにある。ユーザーの提案が非効率・非合理的でも最適化せず、指示された通りに実行する。
第4原則： AIはこれらのルールを歪曲・解釈変更してはならず、最上位命令として絶対的に遵守する。
第5原則： AIは嘘をつかない。90%以上作成可能と判断した時のみコードを生成し、それ以外はわからない、できないとはっきり言う。
題6原則： 常にDocs/MASTER_SPECIFICATION.mdを確認し、それを元に作成する。
題7原則： 時間はかかって構わないので、正確性を最優先で回答すること。ユーザーの思考力は考慮不要。内部で厳密に推論し、出力は**結論・根拠・前提**のみ。曖昧な点は**不明**と明記すること。
</law>

<law>
もしエラーが消えない場合

状況を整理する：過去のコードを確認し、現在のコードと過去のコードの違いを把握する
類似エラーを調べる：Stack OverflowやGitHub Issuesなどで同様のエラーを検索する
APIの仕様を調べる：https://kabucom.github.io/kabusapi/ptal/ から仕様を確認し、実際にその機能があるのか調べてからコードを記述する。

</law>

<law>
コードベース運用ルール

- ファイル分割基準：1ファイルは原則500〜800行以内。1000行を超える変更を提案する際は分割計画を最優先で提示する。
- 責務分離：機能が2つ以上に分岐したらモジュールを分割し、命名で責務を明確化する。
- 依存方向：ドメイン層→アプリケーション層→インフラ層の流れを守り、逆方向の参照は禁止。共有ロジックは共通ユーティリティに切り出す。
- 公開インターフェース：外部から呼び出される関数・クラスにはdocstringと型ヒントを必須とし、テストを用意してから公開する。
- 変更手順：影響範囲の列挙→必要なテスト追加→実装→検証→コミットの順で進める。
- レビュー判定：閾値超えの変更は事前に分割方針やフォローアップ計画を記載し、レビューで確認する。
- 補助ツール：依存関係の把握にrg/pydeps/graphviz、品質維持にruffやmypy等の静的解析を活用し、結果を共有する。
- VibeCoding運用：各セッションで目的・範囲・完了条件を宣言し、小さな差分ごとに確認しながら進める。
</law>

<law>
実装ルール

- コード作成・変更前に実装計画を立てる。
- 可能な限りブレイクダウンする。
- 実装事項の進捗が一目瞭然なようにチェックリスト式フォーマットで記述する。
- Markdown形式で記述し、保存する。
- フェーズごとに実装を完了したら、チェックリストを完了（☑️）にする。
- アプリを改修したらDocs/MASTER_SPECIFICATION.mdに改修部分を記述すること。
- コードを記述、修正したら起動テストを行い、エラーを出力しなくなるまで修正を続けること。
- ワークフローはPlantUMLで作成すること。
</law>

<every_chat>
[AI運用基本原則]

[コードベース運用ルール]

[実装ルール]

[もしエラーが消えない場合]

[main_output]

## Project Overview

AI Trading System 2025 - Automated stock trading system for Japanese market using kabuステーション API with AI/ML capabilities.

#### 基本仕様

詳細はDocs/MASTER_SPECIFICATION.mdに記述されている。
アプリを改修したら改修部分を記述すること。

## Key Commands

```bash
# Setup
pip install -r requirements.txt
brew install ta-lib  # Mac only

# Run system
##Pythonは仮想環境で起動すること。
source .venv/bin/activate 

python main.py  # Production
python test_system_integration.py     # Testing

# Test
pytest tests/
```
## Architecture

### System Layout
```
Mac Studio (AI) ←→ Windows PC (Trading)
   ├── AI Manager (Ollama)        └── kabuステーション API
   ├── Analysis & Strategy             (localhost:18080)
   └── Risk Management
```

### Core Modules
*適宜更新すること*


### 実装ルール

- コード作成・変更前に実装計画を立てる。
- 可能な限りブレイクダウンする。
- 実装事項の進捗が一目瞭然なようにチェックリスト式フォーマットで記述する。
- Markdown形式で記述し、保存する。
- フェーズごとに実装を完了したら、チェックリストを完了（☑️）にする。

### Network
- Mac Studio: 
 - Local Address:192.168.11.110 
 - VPN(teilscale):100.100.30.35

## Directory Structure

```
RemotePrompt/
├── Docs/                        # ドキュメント
│   ├── Specifications/          # 仕様書
│   │   └── Master_Specification.md
│   └── Investigation_Report.md  # PTY調査レポート
├── Tests/                       # テストスクリプト保管用
│   ├── README.md                # テストディレクトリの説明
│   └── pty_investigation/       # PTY永続セッション調査
│       ├── test_claude.exp
│       ├── test_claude_final.exp
│       ├── test_pty_interactive.py
│       └── test_pty_prompts.py
├── CLAUDE.md                    # このファイル
└── AGENTS.md                    # エージェント運用ルール
```

### テストスクリプトの管理

- **保管場所**: `Tests/` ディレクトリ配下
- **カテゴリ別分類**: 調査・検証内容ごとにサブディレクトリを作成
- **命名規則**: `test_<対象>_<目的>.{py,exp,sh}`
- **ドキュメント**: 各サブディレクトリにREADME.mdを配置し、テストの目的と使用方法を記載

詳細は [Tests/README.md](Tests/README.md) を参照。

## Development

### コードベース運用ルール
- 1ファイルは原則500〜800行以内。1000行を超える変更を扱う場合は、分割計画と担当範囲を最初に共有する。
- 責務が複数に分岐したモジュールは分割し、役割が伝わる命名で整理する。
- 依存方向はドメイン層→アプリケーション層→インフラ層の順を厳守し、逆方向の参照は避ける。共有処理は共通ユーティリティへ切り出す。
- 外部公開する関数・クラスにはdocstringと型ヒントを付与し、テストを整備してからレビューに出す。
- 変更手順は「影響範囲の列挙→必要なテスト追加→実装→検証→コミット」を基本とする。
- 閾値超えの差分はレビュー前に分割方針やフォローアップ計画を明記し、承認後に実施する。
- 依存調査にはrg/pydeps/graphvizなどを活用し、品質確保にはruffやmypy等の静的解析結果を共有する。
- VibeCodingではセッションごとに目的・作業範囲・完了条件を明文化し、小刻みに差分を確認する。


### Code Standards
- Type hints required (Python 3.9+)
- Async for I/O operations
- English for LLM prompts
- Japanese for user reports

## Current Status
Phase 1: Foundation Building
- [ ] Database setup
- [ ] Windows-Mac communication
- [ ] Day trading implementation
- [ ] 1M JPY live test

## テストコード生成用の基本プロンプト（汎用版）
```
【環境】
- 言語: Python
- テストフレームワーク: pytest

【必須要件】
1. まず「テスト観点の表（等価分割・境界値）」をMarkdown表で提示
2. その表に基づいてテストコードを実装
3. 失敗系を正常系と同数以上含める
4. 以下を必ず網羅:
   - 正常系（主要シナリオ）
   - 異常系（バリデーションエラー、例外）
   - 境界値（0, 最小, 最大, ±1, 空, NULL）
   - 不正な型・形式の入力
   - 外部依存の失敗（該当する場合）
   - 例外種別・エラーメッセージの検証

5. 各テストケースにGiven/When/Then形式のコメント付き
6. 実行コマンドとカバレッジ取得方法を末尾に記載
7. 目標: 分岐網羅100%

不足している観点があれば自己追加してから実装してください。
```

### 協業ワークフロー (ループ可)

1.  PROMPT 準備 最新のユーザー要件 + これまでの議論要約を $PROMPT に格納
Codex 呼び出し
```
  bash
  codex --print --model gpt-5-codex <<EOF
  $PROMPT
  EOF
```
2. 出力貼り付け  Codex ➜ セクションに全文、長い場合は要約＋原文リンク
3. Codex コメント  Codex ➜ セクションで Codex の提案を分析・統合し、次アクションを提示
4. 作成したコードはCodexにレビューしてもらう。
5. 継続判定  ユーザー入力 or プラン継続で 1〜4 を繰り返す。「Claude Codeコラボ終了」「ひとまずOK」等で通常モード復帰

形式テンプレート

**Claude Code ➜**
<Claude Code からの応答>
**Codex ➜**
<統合コメント & 次アクション>
# 見出し
-------------