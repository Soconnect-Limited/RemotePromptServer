import SwiftUI
import UIKit

// MARK: - UIFont Extension
extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

// MARK: - Message Content Types
enum MessageContentSegment {
    case text(NSAttributedString)
    case codeBlock(code: String, language: String?)
}

// MARK: - Message Parser
struct MessageParser {
    static func parse(_ markdown: String, isUser: Bool) -> [MessageContentSegment] {
        // Phase 7: 性能計測（100KB以上のメッセージ）
        let shouldMeasure = markdown.utf8.count >= 100_000
        let startTime = shouldMeasure ? CFAbsoluteTimeGetCurrent() : 0

        var segments: [MessageContentSegment] = []
        let pattern = "```([a-zA-Z]*)\\n([\\s\\S]*?)```"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // Regex失敗時はテキストとして返す
            let attributed = renderText(markdown, isUser: isUser)
            return [.text(attributed)]
        }

        let fullRange = NSRange(location: 0, length: (markdown as NSString).length)
        let matches = regex.matches(in: markdown, options: [], range: fullRange)

        var lastIndex = 0

        for match in matches {
            // コードブロック前のテキスト
            if match.range.location > lastIndex {
                let textRange = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                let textContent = (markdown as NSString).substring(with: textRange)
                if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let attributed = renderText(textContent, isUser: isUser)
                    segments.append(.text(attributed))
                }
            }

            // コードブロック
            if match.numberOfRanges >= 3 {
                let languageRange = match.range(at: 1)
                let codeRange = match.range(at: 2)

                let language = languageRange.length > 0
                    ? (markdown as NSString).substring(with: languageRange)
                    : nil
                let code = (markdown as NSString).substring(with: codeRange)

                segments.append(.codeBlock(code: code, language: language))
            }

            lastIndex = match.range.location + match.range.length
        }

        // 最後のテキスト
        if lastIndex < (markdown as NSString).length {
            let textRange = NSRange(location: lastIndex, length: (markdown as NSString).length - lastIndex)
            let textContent = (markdown as NSString).substring(with: textRange)
            if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let attributed = renderText(textContent, isUser: isUser)
                segments.append(.text(attributed))
            }
        }

        // Phase 7: セグメント上限チェック（DoS防止）
        if segments.count > 20 {
            print("[Phase 7] ⚠️ Segment count \(segments.count) exceeds limit 20, truncating")
            segments = Array(segments.prefix(20))
        }

        // Phase 7: 性能計測ログ出力
        if shouldMeasure {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[Phase 7] Parse time: \(String(format: "%.1f", elapsed))ms for \(segments.count) segments")
            if elapsed > 100 {
                print("[Phase 7] ⚠️ Parse exceeded 100ms, consider Phase 7-A")
            }
        }

        return segments.isEmpty ? [.text(renderText(markdown, isUser: isUser))] : segments
    }

    private static func renderText(_ text: String, isUser: Bool) -> NSAttributedString {
        // Phase 7: フォールバック処理（Markdown構文エラー時）
        let textColor: UIColor = isUser ? .white : .label
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)

        do {
            return try renderTextInternal(text, isUser: isUser)
        } catch {
            // フォールバック: プレーンテキストで返却
            print("[Phase 7] Markdown parsing failed, fallback to plain text: \(error)")
            return NSAttributedString(string: text, attributes: [
                .font: bodyFont,
                .foregroundColor: textColor
            ])
        }
    }

    private static func renderTextInternal(_ text: String, isUser: Bool) throws -> NSAttributedString {
        let textColor: UIColor = isUser ? .white : .label
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let boldFont = bodyFont.withTraits(.traitBold)
        let italicFont = bodyFont.withTraits(.traitItalic)
        let mono = UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)

        // 見出し用フォント
        let h1Font = UIFont.preferredFont(forTextStyle: .title1).withTraits(.traitBold)
        let h2Font = UIFont.preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        let h3Font = UIFont.preferredFont(forTextStyle: .title3).withTraits(.traitBold)
        let h4Font = UIFont.preferredFont(forTextStyle: .headline).withTraits(.traitBold)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 4

        // 戦略: 後ろから前に向かって文字列置換＋属性適用
        // 1. マッチ情報を収集（処理順序が重要：インラインコード→太字→斜体）
        // 2. 後ろから置換（インデックスずれ防止）
        // 3. 属性適用

        struct MarkdownMatch {
            let range: NSRange
            let replacement: String
            let font: UIFont?
            let backgroundColor: UIColor?
            let isLink: Bool
            let linkURL: String?
        }

        var matches: [MarkdownMatch] = []

        // 1. インラインコード（`code`）- 最優先（他のパターンと競合しないように）
        let inlineCodePattern = "`([^`\n]+)`"
        if let regex = try? NSRegularExpression(pattern: inlineCodePattern, options: []) {
            let foundMatches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in foundMatches {
                if match.numberOfRanges >= 2 {
                    let content = (text as NSString).substring(with: match.range(at: 1))
                    matches.append(MarkdownMatch(range: match.range, replacement: content, font: mono, backgroundColor: UIColor.systemGray5, isLink: false, linkURL: nil))
                }
            }
        }

        // 2. リンク（[text](url)）- 太字・斜体より前に処理
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            let foundMatches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in foundMatches {
                if match.numberOfRanges >= 3 {
                    let linkText = (text as NSString).substring(with: match.range(at: 1))
                    let linkURL = (text as NSString).substring(with: match.range(at: 2))
                    matches.append(MarkdownMatch(range: match.range, replacement: linkText, font: bodyFont, backgroundColor: nil, isLink: true, linkURL: linkURL))
                }
            }
        }

        // 3. 太字（**text**）- 斜体より前に処理（**を先に消費）
        let boldPattern = "\\*\\*([^*]+)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: boldPattern, options: []) {
            let foundMatches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in foundMatches {
                if match.numberOfRanges >= 2 {
                    let content = (text as NSString).substring(with: match.range(at: 1))
                    matches.append(MarkdownMatch(range: match.range, replacement: content, font: boldFont, backgroundColor: nil, isLink: false, linkURL: nil))
                }
            }
        }

        // 4. 斜体（*text*）- 太字処理後に実行
        let italicPattern = "(?<!\\*)\\*([^*\n]+?)\\*(?!\\*)"
        if let regex = try? NSRegularExpression(pattern: italicPattern, options: []) {
            let foundMatches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in foundMatches {
                if match.numberOfRanges >= 2 {
                    let content = (text as NSString).substring(with: match.range(at: 1))
                    // 既に太字/リンク/コードの範囲内かチェック（重複回避）
                    let isOverlapping = matches.contains { existing in
                        NSIntersectionRange(existing.range, match.range).length > 0
                    }
                    if !isOverlapping {
                        matches.append(MarkdownMatch(range: match.range, replacement: content, font: italicFont, backgroundColor: nil, isLink: false, linkURL: nil))
                    }
                }
            }
        }

        // 5. 見出し（# text）
        let headingPattern = "^(#{1,4})\\s+(.+)$"
        if let regex = try? NSRegularExpression(pattern: headingPattern, options: [.anchorsMatchLines]) {
            let foundMatches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in foundMatches {
                if match.numberOfRanges >= 3 {
                    let hashCount = (text as NSString).substring(with: match.range(at: 1)).count
                    let content = (text as NSString).substring(with: match.range(at: 2))

                    let headingFont: UIFont
                    switch hashCount {
                    case 1: headingFont = h1Font
                    case 2: headingFont = h2Font
                    case 3: headingFont = h3Font
                    default: headingFont = h4Font
                    }

                    matches.append(MarkdownMatch(range: match.range, replacement: content, font: headingFont, backgroundColor: nil, isLink: false, linkURL: nil))
                }
            }
        }

        // 6. 箇条書き（- → •）とネスト対応（  - → ◦）
        let listPattern = "^(\\s*)-\\s+"
        if let regex = try? NSRegularExpression(pattern: listPattern, options: [.anchorsMatchLines]) {
            let foundMatches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in foundMatches {
                if match.numberOfRanges >= 2 {
                    let indent = (text as NSString).substring(with: match.range(at: 1))
                    let bullet = indent.count >= 2 ? "  ◦ " : "• "  // インデント2文字以上でネスト記号
                    matches.append(MarkdownMatch(range: match.range, replacement: bullet, font: nil, backgroundColor: nil, isLink: false, linkURL: nil))
                }
            }
        }

        // 位置順にソート（後ろから処理するため降順）
        matches.sort { $0.range.location > $1.range.location }

        // 文字列置換実行
        var workingText = text
        for match in matches {
            workingText = (workingText as NSString).replacingCharacters(in: match.range, with: match.replacement)
        }

        // AttributedString作成
        let attributed = NSMutableAttributedString(string: workingText, attributes: [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ])

        // 属性適用（置換後の位置で）
        // matchesは降順なので、前から順に処理して位置を調整
        matches.reverse()  // 前から処理するため昇順に戻す

        var offset = 0
        for match in matches {
            let newLocation = match.range.location - offset
            let newLength = match.replacement.utf16.count
            let newRange = NSRange(location: newLocation, length: newLength)

            if newRange.location >= 0 && newRange.location + newRange.length <= workingText.utf16.count {
                // リンクの場合
                if match.isLink, let url = match.linkURL, let validURL = URL(string: url) {
                    attributed.addAttribute(.link, value: validURL, range: newRange)
                    attributed.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: newRange)
                    attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
                }
                // 通常の装飾（フォント）
                else if let font = match.font {
                    attributed.removeAttribute(.font, range: newRange)
                    attributed.addAttribute(.font, value: font, range: newRange)
                }

                // 背景色（インラインコード）
                if let bgColor = match.backgroundColor {
                    attributed.addAttribute(.backgroundColor, value: bgColor, range: newRange)
                }
            }

            // オフセット更新（元の長さ - 新しい長さ）
            offset += (match.range.length - match.replacement.utf16.count)
        }

        return attributed
    }
}

// MARK: - CodeBlockView
final class CodeBlockView: UIView {
    private let headerView = UIView()
    private let languageLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let codeTextView = UITextView()
    private var codeContent: String = ""

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // コンテナ設定
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGray4.cgColor
        backgroundColor = UIColor.systemGray6.withAlphaComponent(0.3)
        translatesAutoresizingMaskIntoConstraints = false

        // ヘッダー設定
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.5)
        addSubview(headerView)

        // 言語ラベル設定
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        languageLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        languageLabel.textColor = .secondaryLabel
        headerView.addSubview(languageLabel)

        // コピーボタン設定
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setTitle("Copy", for: .normal)
        copyButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        copyButton.addTarget(self, action: #selector(copyCode), for: .touchUpInside)
        headerView.addSubview(copyButton)

        // コードテキストビュー設定
        codeTextView.translatesAutoresizingMaskIntoConstraints = false
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.isScrollEnabled = false
        codeTextView.backgroundColor = .clear
        codeTextView.font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        codeTextView.textColor = .label
        codeTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        codeTextView.textContainer.lineFragmentPadding = 0
        addSubview(codeTextView)

        NSLayoutConstraint.activate([
            // ヘッダー
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 32),

            // 言語ラベル
            languageLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            languageLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // コピーボタン
            copyButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            copyButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            copyButton.leadingAnchor.constraint(greaterThanOrEqualTo: languageLabel.trailingAnchor, constant: 8),

            // コードテキストビュー
            codeTextView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            codeTextView.leadingAnchor.constraint(equalTo: leadingAnchor),
            codeTextView.trailingAnchor.constraint(equalTo: trailingAnchor),
            codeTextView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(code: String, language: String?) {
        codeContent = code
        languageLabel.text = language?.uppercased() ?? "CODE"

        // シンタックスハイライト適用
        let highlightedCode = applySyntaxHighlighting(code: code, language: language)
        codeTextView.attributedText = highlightedCode
    }

    private func applySyntaxHighlighting(code: String, language: String?) -> NSAttributedString {
        let baseFont = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        let baseColor = UIColor.label

        let attributedString = NSMutableAttributedString(string: code, attributes: [
            .font: baseFont,
            .foregroundColor: baseColor
        ])

        guard let lang = language?.lowercased() else {
            return attributedString
        }

        // 言語ごとのキーワードとカラー定義
        let keywordColor = UIColor.systemPurple
        let stringColor = UIColor.systemRed
        let commentColor = UIColor.systemGreen
        let numberColor = UIColor.systemBlue
        let functionColor = UIColor.systemTeal       // 関数名
        let parameterColor = UIColor.systemOrange    // 引数・パラメータ

        var keywords: [String] = []

        switch lang {
        case "swift":
            keywords = [
                // 宣言キーワード
                "import", "class", "struct", "enum", "protocol", "extension", "typealias", "associatedtype",
                // 関数・プロパティ
                "func", "var", "let", "subscript", "init", "deinit",
                // 制御フロー
                "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat", "break", "continue", "fallthrough", "return", "defer", "do", "try", "catch", "throw", "throws", "rethrows", "where",
                // アクセス制御
                "private", "fileprivate", "internal", "public", "open",
                // 修飾子
                "static", "final", "lazy", "weak", "unowned", "mutating", "nonmutating", "dynamic", "optional", "required", "convenience", "override", "infix", "prefix", "postfix", "indirect",
                // 型関連
                "self", "Self", "super", "as", "is", "some", "any", "Any", "AnyObject",
                // プロパティ監視・アクセサ
                "get", "set", "willSet", "didSet", "inout",
                // 非同期・並行処理
                "async", "await", "actor",
                // リテラル・定数
                "true", "false", "nil"
            ]
        case "python", "py":
            keywords = ["import", "from", "class", "def", "if", "elif", "else", "for", "while", "return", "try", "except", "finally", "with", "as", "pass", "break", "continue", "lambda", "yield", "True", "False", "None", "and", "or", "not", "in", "is"]
        case "javascript", "js", "typescript", "ts":
            keywords = ["import", "export", "class", "function", "const", "let", "var", "if", "else", "for", "while", "return", "try", "catch", "finally", "throw", "async", "await", "new", "this", "super", "true", "false", "null", "undefined"]
        case "java":
            keywords = ["import", "package", "class", "interface", "extends", "implements", "public", "private", "protected", "static", "final", "abstract", "void", "if", "else", "for", "while", "return", "try", "catch", "finally", "throw", "new", "this", "super", "true", "false", "null"]
        case "go":
            keywords = ["package", "import", "func", "var", "const", "type", "struct", "interface", "if", "else", "for", "return", "defer", "go", "chan", "select", "case", "default", "break", "continue", "true", "false", "nil"]
        case "rust", "rs":
            keywords = ["use", "mod", "fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl", "if", "else", "for", "while", "loop", "return", "match", "break", "continue", "pub", "self", "Self", "true", "false"]
        case "c", "cpp", "c++":
            keywords = ["include", "class", "struct", "public", "private", "protected", "static", "const", "void", "int", "char", "float", "double", "if", "else", "for", "while", "return", "try", "catch", "throw", "new", "delete", "true", "false", "nullptr", "NULL"]
        default:
            keywords = []
        }

        // ハイライトの優先順位: コメント > 文字列 > キーワード > 数値
        // 既にハイライト済みの範囲を記録するセット
        var highlightedRanges: [NSRange] = []

        // 1. コメントのハイライト（最優先）
        let commentPattern = "//.*$|/\\*[\\s\\S]*?\\*/|#.*$"
        if let regex = try? NSRegularExpression(pattern: commentPattern, options: [.anchorsMatchLines]) {
            let matches = regex.matches(in: code, options: [], range: NSRange(location: 0, length: code.utf16.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                highlightedRanges.append(match.range)
            }
        }

        // 2. 文字列リテラルのハイライト
        let stringPattern = "\"[^\"]*\"|'[^']*'"
        if let regex = try? NSRegularExpression(pattern: stringPattern, options: []) {
            let matches = regex.matches(in: code, options: [], range: NSRange(location: 0, length: code.utf16.count))
            for match in matches {
                // 既にコメント範囲内ならスキップ
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    attributedString.addAttribute(.foregroundColor, value: stringColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
        }

        // 3. キーワードのハイライト
        for keyword in keywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: code, options: [], range: NSRange(location: 0, length: code.utf16.count))
                for match in matches {
                    // 既にコメント・文字列範囲内ならスキップ
                    if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                        attributedString.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
                    }
                }
            }
        }

        // 4. 関数定義・呼び出しのハイライト
        // パターン: func funcName( または funcName( の形式
        let functionPattern = "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\("
        if let regex = try? NSRegularExpression(pattern: functionPattern, options: []) {
            let matches = regex.matches(in: code, options: [], range: NSRange(location: 0, length: code.utf16.count))
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let funcNameRange = match.range(at: 1)
                    // 既にコメント・文字列範囲内ならスキップ
                    if !highlightedRanges.contains(where: { NSIntersectionRange($0, funcNameRange).length > 0 }) {
                        // キーワードでない場合のみ関数名として扱う
                        let funcName = (code as NSString).substring(with: funcNameRange)
                        if !keywords.contains(funcName) {
                            attributedString.addAttribute(.foregroundColor, value: functionColor, range: funcNameRange)
                        }
                    }
                }
            }
        }

        // 5. パラメータ・引数のハイライト（Swift/Python/JS等で name: の形式）
        let parameterPattern = "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*:"
        if let regex = try? NSRegularExpression(pattern: parameterPattern, options: []) {
            let matches = regex.matches(in: code, options: [], range: NSRange(location: 0, length: code.utf16.count))
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let paramNameRange = match.range(at: 1)
                    // 既にコメント・文字列範囲内ならスキップ
                    if !highlightedRanges.contains(where: { NSIntersectionRange($0, paramNameRange).length > 0 }) {
                        // キーワードでない場合のみパラメータ名として扱う
                        let paramName = (code as NSString).substring(with: paramNameRange)
                        if !keywords.contains(paramName) {
                            attributedString.addAttribute(.foregroundColor, value: parameterColor, range: paramNameRange)
                        }
                    }
                }
            }
        }

        // 6. 数値のハイライト
        let numberPattern = "\\b\\d+(\\.\\d+)?\\b"
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let matches = regex.matches(in: code, options: [], range: NSRange(location: 0, length: code.utf16.count))
            for match in matches {
                // 既にコメント・文字列範囲内ならスキップ
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    attributedString.addAttribute(.foregroundColor, value: numberColor, range: match.range)
                }
            }
        }

        return attributedString
    }

    @objc private func copyCode() {
        UIPasteboard.general.string = codeContent

        // コピー成功のフィードバック
        let originalTitle = copyButton.titleLabel?.text
        copyButton.setTitle("Copied!", for: .normal)
        copyButton.isEnabled = false

        // Memory Leak Fix: [weak self] を使用して循環参照を防止
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.copyButton.setTitle(originalTitle, for: .normal)
            self.copyButton.isEnabled = true
        }
    }
}

/// SwiftUIからUIKitチャットリストを利用するためのブリッジ。
struct ChatListRepresentable: UIViewRepresentable {
    /// 表示対象のメッセージ配列（最新順を想定）。
    var messages: [Message]
    var runner: String  // アバター表示用にrunner情報を追加
    /// 過去ログ読み込みコールバック
    var onLoadMore: (() async -> Void)?

    func makeUIView(context: Context) -> ChatListContainerView {
        let view = ChatListContainerView()
        view.tableView.dataSource = context.coordinator
        view.tableView.delegate = context.coordinator
        view.tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseId)

        // Phase 4: prefetchDataSource 無効化（不要な先読みを防ぐ）
        view.tableView.prefetchDataSource = nil
        view.tableView.isPrefetchingEnabled = false

        context.coordinator.tableView = view.tableView
        context.coordinator.containerView = view
        context.coordinator.runner = runner
        context.coordinator.setupLoadMore(callback: onLoadMore)
        context.coordinator.reload(with: messages)
        return view
    }

    func updateUIView(_ uiView: ChatListContainerView, context: Context) {
        context.coordinator.runner = runner
        context.coordinator.setupLoadMore(callback: onLoadMore)
        context.coordinator.reload(with: messages)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        weak var tableView: UITableView?
        weak var containerView: ChatListContainerView?
        private var messages: [Message] = []
        var runner: String = "claude"
        /// 過去ログ読み込み中フラグ（スクロール位置維持用）
        private var isLoadingOlderMessages = false
        private var onLoadMoreCallback: (() async -> Void)?

        /// 過去ログ読み込みコールバックを設定
        func setupLoadMore(callback: (() async -> Void)?) {
            onLoadMoreCallback = callback
            // コールバックをContainerViewに接続
            containerView?.onLoadMore = { [weak self] in
                print("DEBUG: Pull-to-refresh triggered")
                guard let self = self, let callback = self.onLoadMoreCallback else {
                    print("DEBUG: No callback available")
                    return
                }
                self.isLoadingOlderMessages = true
                print("DEBUG: Starting load more task, isLoadingOlder set to TRUE")
                Task {
                    await callback()
                    print("DEBUG: Load more callback completed, isLoadingOlder still TRUE")
                    // Note: isLoadingOlderMessagesはreload()完了後にリセットされる
                    // ここではendRefreshingのみ呼ぶ
                    await MainActor.run {
                        self.containerView?.endRefreshing()
                        print("DEBUG: endRefreshing called")
                    }
                }
            }
        }

        /// 過去ログ読み込み完了後にフラグをリセット
        func finishLoadingOlderMessages() {
            isLoadingOlderMessages = false
            print("DEBUG: finishLoadingOlderMessages - isLoadingOlder set to FALSE")
        }

        // MARK: Public API
        /// 過去ログ読み込み時のアンカー情報を保持
        private var savedAnchorMessageId: String?
        private var savedAnchorOffset: CGFloat = 0

        func reload(with newMessages: [Message]) {
            guard let tableView else {
                messages = newMessages
                return
            }

            let oldCount = messages.count
            let newCount = newMessages.count

            print("DEBUG: reload() - oldCount=\(oldCount), newCount=\(newCount), isLoadingOlderMessages=\(isLoadingOlderMessages)")

            // 過去ログ読み込み中: 初回のreloadでアンカーを保存（まだ保存されていない場合のみ）
            if isLoadingOlderMessages && savedAnchorMessageId == nil {
                if let firstVisibleIndexPath = tableView.indexPathsForVisibleRows?.first,
                   firstVisibleIndexPath.row < messages.count {
                    savedAnchorMessageId = messages[firstVisibleIndexPath.row].id
                    if let cell = tableView.cellForRow(at: firstVisibleIndexPath) {
                        savedAnchorOffset = cell.frame.minY - tableView.contentOffset.y
                    }
                    print("DEBUG: reload() - Saved anchor: \(savedAnchorMessageId ?? "nil"), offset: \(savedAnchorOffset)")
                }
            }

            // 過去ログ読み込み中はスクロール位置を維持
            if isLoadingOlderMessages {
                // データが実際に増加した場合のみ位置復元してフラグリセット
                if newCount > oldCount, let anchorId = savedAnchorMessageId {
                    messages = newMessages
                    tableView.reloadData()

                    if let newIndex = newMessages.firstIndex(where: { $0.id == anchorId }) {
                        tableView.layoutIfNeeded()
                        let targetIndexPath = IndexPath(row: newIndex, section: 0)
                        if let cell = tableView.cellForRow(at: targetIndexPath) {
                            let newOffset = cell.frame.minY - savedAnchorOffset
                            tableView.setContentOffset(CGPoint(x: 0, y: newOffset), animated: false)
                            print("DEBUG: reload() - Restored scroll position to index \(newIndex)")
                        } else {
                            tableView.scrollToRow(at: targetIndexPath, at: .top, animated: false)
                            print("DEBUG: reload() - Scrolled to anchor index \(newIndex)")
                        }
                    }
                    // データ増加後にフラグとアンカーをリセット
                    isLoadingOlderMessages = false
                    savedAnchorMessageId = nil
                    savedAnchorOffset = 0
                    print("DEBUG: reload() - Loading complete, flags reset")
                } else {
                    // データ未変更: メッセージ更新のみ、スクロールしない
                    messages = newMessages
                    tableView.reloadData()
                    print("DEBUG: reload() - Data unchanged, waiting for actual data")
                }
                return
            }

            // 通常のリロード処理（過去ログ読み込み中でない場合）
            // 初回ロードまたは大幅な変更の場合は全体リロード
            if oldCount == 0 || abs(newCount - oldCount) > 10 {
                messages = newMessages
                tableView.reloadData()
                scrollToBottomIfNeeded()
                return
            }

            // 差分検出と部分更新
            var indexPathsToReload: [IndexPath] = []
            var indexPathsToInsert: [IndexPath] = []

            let minCount = min(oldCount, newCount)
            for i in 0..<minCount {
                let oldMsg = messages[i]
                let newMsg = newMessages[i]
                if oldMsg.id == newMsg.id {
                    if oldMsg.content != newMsg.content || oldMsg.status != newMsg.status {
                        indexPathsToReload.append(IndexPath(row: i, section: 0))
                    }
                } else {
                    // ID が違う場合は全体リロード
                    messages = newMessages
                    tableView.reloadData()
                    scrollToBottomIfNeeded()
                    return
                }
            }

            if newCount > oldCount {
                for i in oldCount..<newCount {
                    indexPathsToInsert.append(IndexPath(row: i, section: 0))
                }
            }

            messages = newMessages

            UIView.performWithoutAnimation {
                tableView.performBatchUpdates {
                    if !indexPathsToInsert.isEmpty {
                        tableView.insertRows(at: indexPathsToInsert, with: .none)
                    }
                    if !indexPathsToReload.isEmpty {
                        tableView.reloadRows(at: indexPathsToReload, with: .none)
                    }
                } completion: { _ in
                    self.scrollToBottomIfNeeded()
                }
            }
        }

        private func scrollToBottomIfNeeded() {
            guard let tableView else { return }
            guard !messages.isEmpty else { return }
            let last = IndexPath(row: messages.count - 1, section: 0)
            // アニメーション無効化（ユーザー要望: 滑らかな遷移、アニメーション不要）
            tableView.scrollToRow(at: last, at: .bottom, animated: false)
        }

        // MARK: UITableViewDataSource
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            messages.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let msg = messages[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.reuseId, for: indexPath) as! ChatMessageCell
            cell.configure(with: msg, runner: runner)
            return cell
        }

        // MARK: UITableViewDelegate
        func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
            // Phase 6: コードブロック数を考慮した高さ推定
            let message = messages[indexPath.row]
            let charCount = message.content.count

            // 基本高さ（文字数ベース）
            let baseHeight: CGFloat
            if charCount < 1000 {
                baseHeight = 80
            } else if charCount < 10_000 {
                baseHeight = 300
            } else {
                baseHeight = 1000
            }

            // コードブロック数の検出（簡易的に```の出現回数/2）
            let codeBlockCount = message.content.components(separatedBy: "```").count / 2
            let codeBlockBonus = CGFloat(codeBlockCount) * 150  // 1ブロックあたり150pt加算

            return baseHeight + codeBlockBonus
        }

        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            UITableView.automaticDimension
        }
    }
}

// MARK: - Cell

final class ChatMessageCell: UITableViewCell {
    static let reuseId = "chat.message.cell"

    private let avatarImageView = UIImageView()
    private let bubbleView = UIView()
    private let textView = UITextView()

    // Phase B-13: UIStackView for mixed text and code block views
    private let contentStackView = UIStackView()

    // 推論中インジケーター
    private let loadingStackView = UIStackView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()

    // Phase 4: 長文折りたたみ
    private let expandButton = UIButton(type: .system)
    private var isExpanded = false
    private var fullContent: String = ""
    private let truncateThreshold = 1000  // 1000文字以上で折りたたみ

    // 制約を保持して再利用時に更新可能にする
    private var bubbleLeadingConstraint: NSLayoutConstraint?
    private var bubbleTrailingConstraint: NSLayoutConstraint?
    private var avatarLeadingConstraint: NSLayoutConstraint?
    private var textViewBottomConstraint: NSLayoutConstraint?
    private var expandButtonBottomConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground

        // アバター設定
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.layer.cornerRadius = 6
        avatarImageView.layer.masksToBounds = true
        contentView.addSubview(avatarImageView)

        // バブル設定
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.masksToBounds = true
        contentView.addSubview(bubbleView)

        // テキストビュー設定
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.delaysContentTouches = false
        bubbleView.addSubview(textView)

        // ローディングインジケーター設定
        loadingStackView.translatesAutoresizingMaskIntoConstraints = false
        loadingStackView.axis = .horizontal
        loadingStackView.spacing = 8
        loadingStackView.alignment = .center
        loadingStackView.isHidden = true
        bubbleView.addSubview(loadingStackView)

        activityIndicator.color = .label
        activityIndicator.hidesWhenStopped = true
        loadingStackView.addArrangedSubview(activityIndicator)

        loadingLabel.text = "応答を生成中..."
        loadingLabel.font = UIFont.preferredFont(forTextStyle: .body)
        loadingLabel.textColor = .label
        loadingStackView.addArrangedSubview(loadingLabel)

        NSLayoutConstraint.activate([
            loadingStackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 12),
            loadingStackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -12),
            loadingStackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            loadingStackView.trailingAnchor.constraint(lessThanOrEqualTo: bubbleView.trailingAnchor, constant: -12)
        ])

        // Phase 4: 展開ボタン設定
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.setTitle("続きを読む", for: .normal)
        expandButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        expandButton.addTarget(self, action: #selector(toggleExpand), for: .touchUpInside)
        expandButton.contentHorizontalAlignment = .trailing
        expandButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)  // 背景を追加して視認性向上
        expandButton.layer.cornerRadius = 4
        expandButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        expandButton.isHidden = true
        bubbleView.addSubview(expandButton)

        expandButtonBottomConstraint = expandButton.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)

        NSLayoutConstraint.activate([
            expandButton.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            expandButton.leadingAnchor.constraint(greaterThanOrEqualTo: bubbleView.leadingAnchor, constant: 12),
            expandButtonBottomConstraint!
        ])

        // アバター制約（Assistant時のみ表示）
        avatarLeadingConstraint = avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)

        // Phase B-13: contentStackView設定
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.spacing = 8
        contentStackView.distribution = .fill
        contentStackView.alignment = .fill
        bubbleView.addSubview(contentStackView)

        // bubbleViewのlayoutMarginsを設定（既存のtextView制約と同等）
        bubbleView.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: bubbleView.layoutMarginsGuide.topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bubbleView.layoutMarginsGuide.bottomAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: bubbleView.layoutMarginsGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: bubbleView.layoutMarginsGuide.trailingAnchor)
        ])

        // expandButtonを最前面に移動（contentStackViewの上に表示）
        bubbleView.bringSubviewToFront(expandButton)

        // textViewのbottom制約は動的に切り替える（展開ボタン表示時は変更）
        textViewBottomConstraint = textView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            avatarImageView.widthAnchor.constraint(equalToConstant: 28),
            avatarImageView.heightAnchor.constraint(equalToConstant: 28),

            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            textView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            textViewBottomConstraint!,
            textView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        ])

        // Phase B-13: textViewを非表示化（削除しない - expandButton等で使用）
        textView.isHidden = true
    }

    func configure(with message: Message, runner: String) {
        let isUser = message.type == .user
        let isLoading = message.content.isEmpty && message.isRunning

        // アバター表示制御（常に非表示）
        avatarImageView.isHidden = true
        avatarLeadingConstraint?.isActive = false

        // バブルレイアウト制約を更新
        bubbleLeadingConstraint?.isActive = false
        bubbleTrailingConstraint?.isActive = false

        if isUser {
            // User: 右寄せ、画面幅の75%、グレー背景、角丸
            bubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: UIScreen.main.bounds.width * 0.25)
            bubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

            bubbleView.backgroundColor = UIColor.systemGray5
            bubbleView.layer.cornerRadius = 16
            textView.textColor = .label
            expandButton.setTitleColor(.label, for: .normal)
        } else {
            // Assistant: 画面幅いっぱい、背景なし、角丸なし
            bubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
            bubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

            bubbleView.backgroundColor = .clear
            bubbleView.layer.cornerRadius = 0
            textView.textColor = .label
            textView.tintColor = .label
            expandButton.setTitleColor(.systemBlue, for: .normal)
        }

        bubbleLeadingConstraint?.isActive = true
        bubbleTrailingConstraint?.isActive = true
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]

        // Phase B-13: contentStackViewをクリア
        for view in contentStackView.arrangedSubviews {
            contentStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // 推論中の場合はインジケーターを表示
        if isLoading {
            loadingStackView.isHidden = false
            textView.isHidden = true
            activityIndicator.startAnimating()
            // contentStackViewは空のまま（推論中は既存のloadingStackViewを使用）
        } else {
            loadingStackView.isHidden = true
            activityIndicator.stopAnimating()

            // Phase B-13: MessageParser.parse()でMarkdownをセグメント化
            let markdown = message.content
            fullContent = markdown  // Phase 4: 全文を保存

            // Phase 4: 長文チェック（1000文字以上）
            let shouldTruncate = markdown.count > truncateThreshold && !isExpanded

            let displayContent = shouldTruncate ? String(markdown.prefix(truncateThreshold)) : markdown
            var segments = MessageParser.parse(displayContent, isUser: isUser)

            // セグメント数チェック（DoS防止）
            if segments.count > 20 {
                print("[Phase B-13] ⚠️ Segment count \(segments.count) exceeds limit 20, truncating")
                segments = Array(segments.prefix(20))
            }

            // segmentsをループ処理してcontentStackViewに追加
            for segment in segments {
                switch segment {
                case .text(let attributedString):
                    let textView = createTextView(with: attributedString, isUser: isUser)
                    contentStackView.addArrangedSubview(textView)
                case .codeBlock(let code, let language):
                    let codeBlockView = createCodeBlockView(code: code, language: language)
                    contentStackView.addArrangedSubview(codeBlockView)
                }
            }

            // Phase 4: 省略時の「...」表示
            if shouldTruncate {
                let ellipsisText = NSAttributedString(string: "...", attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: isUser ? UIColor.white : UIColor.label
                ])
                let ellipsisView = createTextView(with: ellipsisText, isUser: isUser)
                contentStackView.addArrangedSubview(ellipsisView)
            }

            // Phase B-13: 旧textViewは完全に隠す
            textView.isHidden = true

            // Phase 4: 長文折りたたみボタン表示制御
            if markdown.count > truncateThreshold {
                expandButton.isHidden = false
                expandButton.setTitle(isExpanded ? "折りたたむ" : "続きを読む", for: .normal)
            } else {
                expandButton.isHidden = true
            }
        }
    }

    // Phase B-13: テキスト用UITextView生成メソッド
    private func createTextView(with attributedString: NSAttributedString, isUser: Bool) -> UITextView {
        let newTextView = UITextView()
        newTextView.translatesAutoresizingMaskIntoConstraints = false
        newTextView.attributedText = attributedString
        newTextView.isEditable = false
        newTextView.isSelectable = true
        newTextView.isScrollEnabled = false
        newTextView.textContainerInset = .zero
        newTextView.textContainer.lineFragmentPadding = 0
        newTextView.backgroundColor = .clear
        // IMPORTANT: .fontを設定すると、attributedTextの全てのフォント属性が上書きされるため削除
        // newTextView.font = UIFont.preferredFont(forTextStyle: .body)
        // IMPORTANT: .textColorも同様にattributedTextの色属性を上書きするため削除
        // newTextView.textColor = isUser ? .white : UIColor.label
        newTextView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        newTextView.dataDetectorTypes = []
        newTextView.delaysContentTouches = false
        return newTextView
    }

    // Phase B-13: CodeBlockView生成メソッド
    private func createCodeBlockView(code: String, language: String?) -> CodeBlockView {
        let codeBlockView = CodeBlockView()
        codeBlockView.configure(code: code, language: language)
        return codeBlockView
    }

    // Phase 4: 展開/折りたたみトグル（UIStackViewベース）
    @objc private func toggleExpand() {
        isExpanded.toggle()
        expandButton.setTitle(isExpanded ? "折りたたむ" : "続きを読む", for: .normal)

        // contentStackViewをクリアして再構築
        for view in contentStackView.arrangedSubviews {
            contentStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // 表示内容を決定
        let shouldTruncate = fullContent.count > truncateThreshold && !isExpanded
        let displayContent = shouldTruncate ? String(fullContent.prefix(truncateThreshold)) : fullContent
        let isUser = bubbleView.backgroundColor == UIColor.systemGray5

        // セグメント化して表示
        var segments = MessageParser.parse(displayContent, isUser: isUser)
        if segments.count > 20 {
            segments = Array(segments.prefix(20))
        }

        for segment in segments {
            switch segment {
            case .text(let attributedString):
                let textView = createTextView(with: attributedString, isUser: isUser)
                contentStackView.addArrangedSubview(textView)
            case .codeBlock(let code, let language):
                let codeBlockView = createCodeBlockView(code: code, language: language)
                contentStackView.addArrangedSubview(codeBlockView)
            }
        }

        // 省略時の「...」表示
        if shouldTruncate {
            let ellipsisText = NSAttributedString(string: "...", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: isUser ? UIColor.white : UIColor.label
            ])
            let ellipsisView = createTextView(with: ellipsisText, isUser: isUser)
            contentStackView.addArrangedSubview(ellipsisView)
        }

        // 旧textViewは隠したまま
        textView.isHidden = true

        // 高さ再計算
        if let tableView = superview as? UITableView {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        // Phase 5: contentStackViewのサブビューをクリア
        // Memory Leak Fix: CodeBlockView等の複雑なビューを完全に解放
        for view in contentStackView.arrangedSubviews {
            contentStackView.removeArrangedSubview(view)
            // サブビューの階層も再帰的にクリア
            if let codeBlockView = view as? CodeBlockView {
                // CodeBlockViewの内部コンポーネントを明示的に解放
                codeBlockView.subviews.forEach { $0.removeFromSuperview() }
            }
            view.removeFromSuperview()
        }

        // 既存のtextViewはクリアのみ（削除しない）
        // IMPORTANT: isHiddenはリセットしない（configure()の最初で必ず設定されるため不要）
        textView.text = nil
        textView.attributedText = nil

        // その他既存のリセット処理
        avatarImageView.image = nil
        activityIndicator.stopAnimating()
        loadingStackView.isHidden = true

        // Phase 4: 折りたたみ状態をリセット
        isExpanded = false
        fullContent = ""
        expandButton.isHidden = true
        expandButton.setTitle("続きを読む", for: .normal)

        // 制約をリセット（textViewBottomConstraintは再設定時に制御される）
        textViewBottomConstraint?.isActive = false
    }
}
