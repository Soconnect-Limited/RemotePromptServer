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

        return segments.isEmpty ? [.text(renderText(markdown, isUser: isUser))] : segments
    }

    private static func renderText(_ text: String, isUser: Bool) -> NSAttributedString {
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
        codeTextView.text = code
    }

    @objc private func copyCode() {
        UIPasteboard.general.string = codeContent

        // コピー成功のフィードバック
        let originalTitle = copyButton.titleLabel?.text
        copyButton.setTitle("Copied!", for: .normal)
        copyButton.isEnabled = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.setTitle(originalTitle, for: .normal)
            self?.copyButton.isEnabled = true
        }
    }
}

/// SwiftUIからUIKitチャットリストを利用するためのブリッジ。
struct ChatListRepresentable: UIViewRepresentable {
    /// 表示対象のメッセージ配列（最新順を想定）。
    var messages: [Message]
    var runner: String  // アバター表示用にrunner情報を追加

    func makeUIView(context: Context) -> ChatListContainerView {
        let view = ChatListContainerView()
        view.tableView.dataSource = context.coordinator
        view.tableView.delegate = context.coordinator
        view.tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseId)

        // Phase 4: prefetchDataSource 無効化（不要な先読みを防ぐ）
        view.tableView.prefetchDataSource = nil
        view.tableView.isPrefetchingEnabled = false

        context.coordinator.tableView = view.tableView
        context.coordinator.runner = runner
        context.coordinator.reload(with: messages)
        return view
    }

    func updateUIView(_ uiView: ChatListContainerView, context: Context) {
        context.coordinator.runner = runner
        context.coordinator.reload(with: messages)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        weak var tableView: UITableView?
        private var messages: [Message] = []
        var runner: String = "claude"

        // MARK: Public API
        func reload(with newMessages: [Message]) {
            guard let tableView else {
                messages = newMessages
                return
            }

            let oldCount = messages.count
            let newCount = newMessages.count

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

            // 既存メッセージの変更検出
            let minCount = min(oldCount, newCount)
            for i in 0..<minCount {
                let oldMsg = messages[i]
                let newMsg = newMessages[i]
                // ID が同じでも content/status が変わっている場合は更新
                if oldMsg.id == newMsg.id {
                    if oldMsg.content != newMsg.content || oldMsg.status != newMsg.status {
                        indexPathsToReload.append(IndexPath(row: i, section: 0))
                    }
                } else {
                    // ID が違う場合は全体リロード（順序変更）
                    messages = newMessages
                    tableView.reloadData()
                    scrollToBottomIfNeeded()
                    return
                }
            }

            // 新規追加メッセージの検出
            if newCount > oldCount {
                for i in oldCount..<newCount {
                    indexPathsToInsert.append(IndexPath(row: i, section: 0))
                }
            }

            messages = newMessages

            // バッチ更新（アニメーション無効化）
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
            let count = messages[indexPath.row].content.count
            if count < 1000 { return 80 }
            if count < 10_000 { return 300 }
            return 1000
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
        expandButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)  // footnote → body に変更
        expandButton.addTarget(self, action: #selector(toggleExpand), for: .touchUpInside)
        expandButton.contentHorizontalAlignment = .trailing  // 右寄せ
        expandButton.isHidden = true
        bubbleView.addSubview(expandButton)

        expandButtonBottomConstraint = expandButton.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)

        NSLayoutConstraint.activate([
            expandButton.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),  // 右下に配置
            expandButton.leadingAnchor.constraint(greaterThanOrEqualTo: bubbleView.leadingAnchor, constant: 12),  // 最小マージン確保
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

            var segments = MessageParser.parse(markdown, isUser: isUser)

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

            // Phase B-13: 旧textViewは完全に隠す
            textView.isHidden = true

            // Phase 4: 長文折りたたみ（現状は無効化 - 今後UIStackViewベースで再実装）
            expandButton.isHidden = true
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

    private func renderMarkdown(_ text: String, isUser: Bool) -> NSMutableAttributedString {
        let textColor: UIColor = isUser ? .white : .label
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let boldFont = UIFont.preferredFont(forTextStyle: .body).withTraits(.traitBold)
        let italicFont = UIFont.preferredFont(forTextStyle: .body).withTraits(.traitItalic)
        let mono = UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 4

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ])

        let fullRange = NSRange(location: 0, length: attributed.length)

        // コードブロック（```...```）→ 等幅フォント + 背景色
        let codeBlockPattern = "```[a-zA-Z]*\\n?([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                attributed.addAttribute(.font, value: mono, range: match.range)
                attributed.addAttribute(.backgroundColor, value: UIColor.systemGray4, range: match.range)
            }
        }

        // インラインコード（`code`）→ 等幅フォント + 薄い背景色
        let inlineCodePattern = "`([^`\n]+)`"
        if let regex = try? NSRegularExpression(pattern: inlineCodePattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                attributed.addAttribute(.font, value: mono, range: match.range)
                attributed.addAttribute(.backgroundColor, value: UIColor.systemGray5, range: match.range)
            }
        }

        // 太字（**text**）
        let boldPattern = "\\*\\*([^*]+)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: boldPattern, options: []) {
            let matches = regex.matches(in: attributed.string, options: [], range: NSRange(location: 0, length: attributed.length))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let contentRange = match.range(at: 1)
                    let content = (attributed.string as NSString).substring(with: contentRange)
                    let replacement = NSAttributedString(string: content, attributes: [
                        .font: boldFont,
                        .foregroundColor: textColor
                    ])
                    attributed.replaceCharacters(in: match.range, with: replacement)
                }
            }
        }

        // 斜体（*text*）
        let italicPattern = "(?<!\\*)\\*([^*\n]+)\\*(?!\\*)"
        if let regex = try? NSRegularExpression(pattern: italicPattern, options: []) {
            let matches = regex.matches(in: attributed.string, options: [], range: NSRange(location: 0, length: attributed.length))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let contentRange = match.range(at: 1)
                    let content = (attributed.string as NSString).substring(with: contentRange)
                    let replacement = NSAttributedString(string: content, attributes: [
                        .font: italicFont,
                        .foregroundColor: textColor
                    ])
                    attributed.replaceCharacters(in: match.range, with: replacement)
                }
            }
        }

        return attributed
    }

    private func applyCodeStyling(_ attributed: NSMutableAttributedString, isUser: Bool) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let textColor: UIColor = isUser ? .white : .label
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let mono = UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)

        // 段落スタイルを設定（改行の行間調整）
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2  // 行間を適度に（4→2に縮小）
        paragraphStyle.paragraphSpacing = 4  // 段落間を適度に（8→4に縮小）
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        // フォントサイズを統一（Markdown由来のサイズ調整を保持しつつベースを設定）
        attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if let font = value as? UIFont {
                // 見出しなど既存のフォント属性のサイズ比率を保持
                let newFont = font.withSize(max(font.pointSize, bodyFont.pointSize))
                attributed.addAttribute(.font, value: newFont, range: range)
            } else {
                // フォント未設定の範囲にはbodyフォントを適用
                attributed.addAttribute(.font, value: bodyFont, range: range)
            }
        }

        // テキスト色を設定（User=白、Assistant=自動）
        attributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { _, range, _ in
            attributed.addAttribute(.foregroundColor, value: textColor, range: range)
        }

        // コードブロック検出（```で囲まれた部分全体をスタイリング）
        let text = attributed.string
        let pattern = "```[a-zA-Z]*\\n?([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                // バッククォートを含む全体にスタイル適用
                attributed.addAttribute(.font, value: mono, range: match.range)
                attributed.addAttribute(.backgroundColor, value: UIColor.systemGray4, range: match.range)
                attributed.addAttribute(.foregroundColor, value: textColor, range: match.range)
            }
        }

        // インラインコード（`code`）のスタイリング
        let inlinePattern = "`([^`]+)`"
        if let inlineRegex = try? NSRegularExpression(pattern: inlinePattern, options: []) {
            let matches = inlineRegex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                attributed.addAttribute(.font, value: mono, range: match.range)
                attributed.addAttribute(.backgroundColor, value: UIColor.systemGray5, range: match.range)
                attributed.addAttribute(.foregroundColor, value: textColor, range: match.range)
            }
        }
    }

    // Phase 4: 展開/折りたたみトグル
    @objc private func toggleExpand() {
        isExpanded.toggle()
        expandButton.setTitle(isExpanded ? "折りたたむ" : "続きを読む", for: .normal)

        // 全文表示/省略表示を切り替え
        let displayContent = isExpanded ? fullContent : String(fullContent.prefix(truncateThreshold))
        let isUser = bubbleView.backgroundColor == UIColor.systemBlue

        // 手動でMarkdownスタイリングを適用（コードブロックを保持）
        let mutable = renderMarkdown(displayContent, isUser: isUser)

        if !isExpanded && fullContent.count > truncateThreshold {
            let ellipsis = NSAttributedString(string: "...", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: isUser ? UIColor.white : UIColor.label
            ])
            mutable.append(ellipsis)
        }

        textView.attributedText = mutable

        // 高さ再計算
        if let tableView = superview as? UITableView {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = nil
        textView.attributedText = nil
        activityIndicator.stopAnimating()
        loadingStackView.isHidden = true
        textView.isHidden = false

        // Phase 4: 折りたたみ状態をリセット
        isExpanded = false
        fullContent = ""
        expandButton.isHidden = true
        expandButton.setTitle("続きを読む", for: .normal)

        // 制約をリセット（textViewBottomConstraintは再設定時に制御される）
        textViewBottomConstraint?.isActive = false
    }
}
