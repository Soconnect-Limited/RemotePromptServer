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

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 4

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ])

        let fullRange = NSRange(location: 0, length: attributed.length)

        // インラインコード（`code`）
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
            let matches = regex.matches(in: text, options: [], range: fullRange)
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let contentRange = match.range(at: 1)
                    let content = (text as NSString).substring(with: contentRange)
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

            // バッチ更新
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

        private func scrollToBottomIfNeeded() {
            guard let tableView else { return }
            guard !messages.isEmpty else { return }
            let last = IndexPath(row: messages.count - 1, section: 0)
            tableView.scrollToRow(at: last, at: .bottom, animated: true)
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
    }

    func configure(with message: Message, runner: String) {
        let isUser = message.type == .user
        let isLoading = message.content.isEmpty && message.isRunning

        // アバター表示制御
        if isUser {
            avatarImageView.isHidden = true
            avatarLeadingConstraint?.isActive = false
        } else {
            avatarImageView.isHidden = false
            avatarLeadingConstraint?.isActive = true

            // アバター画像設定（SwiftUI版と同じロジック）
            let iconName = runner.lowercased() == "codex" ? "Codex" : "Claude-Code"
            avatarImageView.image = UIImage(named: iconName)
        }

        // バブルレイアウト制約を更新
        bubbleLeadingConstraint?.isActive = false
        bubbleTrailingConstraint?.isActive = false

        if isUser {
            // User: 右寄せ、画面幅の75%
            bubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: UIScreen.main.bounds.width * 0.25)
            bubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

            bubbleView.backgroundColor = UIColor.systemBlue
            textView.textColor = .white
            // Phase 4: ユーザー送信の展開ボタンは白色
            expandButton.setTitleColor(.white, for: .normal)
        } else {
            // Assistant: 左寄せ（アバター右）、画面幅の75%
            bubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8)
            bubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12)

            // 背景は暗めのグレー、文字は自動（ダークモードで白、ライトモードで黒）
            bubbleView.backgroundColor = UIColor.systemGray6
            textView.textColor = .label  // システム標準色（自動切替）
            textView.tintColor = .label
            // Phase 4: Assistantの展開ボタンはシステムデフォルト
            expandButton.setTitleColor(.systemBlue, for: .normal)
        }

        bubbleLeadingConstraint?.isActive = true
        bubbleTrailingConstraint?.isActive = true
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]

        // 推論中の場合はインジケーターを表示
        if isLoading {
            loadingStackView.isHidden = false
            textView.isHidden = true
            activityIndicator.startAnimating()
        } else {
            loadingStackView.isHidden = true
            textView.isHidden = false
            activityIndicator.stopAnimating()

            // Markdownレンダリング
            let markdown = message.content
            fullContent = markdown  // Phase 4: 全文を保存

            // Phase 4: 長文折りたたみ（1000文字超）
            let shouldTruncate = markdown.count > truncateThreshold && !isExpanded
            let displayContent = shouldTruncate ? String(markdown.prefix(truncateThreshold)) : markdown
            let showExpandButton = markdown.count > truncateThreshold
            expandButton.isHidden = !showExpandButton

            // Phase 4: textViewのbottom制約を切り替え（制約を再利用）
            textViewBottomConstraint?.isActive = false
            if showExpandButton {
                // 展開ボタンがある場合はtextViewの下端を制限しない（内容に応じて伸びる）
                // expandButtonがbubbleView.bottomに固定されているので、textViewは自然にその上に配置される
                // textViewBottomConstraintは不要（nil）
            } else {
                // 展開ボタンがない場合はtextViewがbubbleの下まで伸びる
                textViewBottomConstraint?.isActive = true
            }

            // Phase 3-A: 性能計測（100KB以上のコンテンツのみ）
            let shouldMeasure = markdown.utf8.count >= 100_000
            let startTime = shouldMeasure ? CFAbsoluteTimeGetCurrent() : 0

            // 手動でMarkdownスタイリングを適用（コードブロックを保持）
            let mutable = renderMarkdown(displayContent, isUser: isUser)

            if shouldMeasure {
                let conversionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                let sizeKB = Double(markdown.utf8.count) / 1024.0
                print("[Phase 3-A] Markdown conversion: \(String(format: "%.1f", sizeKB))KB in \(String(format: "%.1f", conversionTime))ms")

                if conversionTime > 50 {
                    print("[Phase 3-A] ⚠️ Conversion exceeded 50ms target, consider Phase 3-A' chunked rendering")
                }
            }

            textView.attributedText = mutable

            // Phase 4: 折りたたみ時に省略記号を追加
            if shouldTruncate {
                let ellipsis = NSAttributedString(string: "...", attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: isUser ? UIColor.white : UIColor.label
                ])
                mutable.append(ellipsis)
                textView.attributedText = mutable
            }
        }
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
            let matches = regex.matches(in: text, options: [], range: fullRange)
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let contentRange = match.range(at: 1)
                    let content = (text as NSString).substring(with: contentRange)
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
