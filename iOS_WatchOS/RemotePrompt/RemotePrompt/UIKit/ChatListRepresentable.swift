import SwiftUI
import UIKit

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
            messages = newMessages
            tableView?.reloadData()
            scrollToBottomIfNeeded()
        }

        private func scrollToBottomIfNeeded() {
            guard let tableView else { return }
            guard !messages.isEmpty else { return }
            let last = IndexPath(row: messages.count - 1, section: 0)
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

    // 制約を保持して再利用時に更新可能にする
    private var bubbleLeadingConstraint: NSLayoutConstraint?
    private var bubbleTrailingConstraint: NSLayoutConstraint?
    private var avatarLeadingConstraint: NSLayoutConstraint?

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

        // アバター制約（Assistant時のみ表示）
        avatarLeadingConstraint = avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            avatarImageView.widthAnchor.constraint(equalToConstant: 28),
            avatarImageView.heightAnchor.constraint(equalToConstant: 28),

            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            textView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        ])
    }

    func configure(with message: Message, runner: String) {
        let isUser = message.type == .user

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
        } else {
            // Assistant: 左寄せ（アバター右）、画面幅の75%
            bubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8)
            bubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12)

            // 背景は暗めのグレー、文字は自動（ダークモードで白、ライトモードで黒）
            bubbleView.backgroundColor = UIColor.systemGray6
            textView.textColor = .label  // システム標準色（自動切替）
            textView.tintColor = .label
        }

        bubbleLeadingConstraint?.isActive = true
        bubbleTrailingConstraint?.isActive = true
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]

        // Markdownレンダリング
        let markdown = message.content
        if let attributed = try? AttributedString(markdown: markdown) {
            let mutable = NSMutableAttributedString(attributed)
            // Assistant用の色を明示的に設定（isUserフラグを渡す）
            applyCodeStyling(mutable, isUser: isUser)
            textView.attributedText = mutable
        } else {
            textView.text = markdown
            textView.font = UIFont.preferredFont(forTextStyle: .body)
        }
    }

    private func applyCodeStyling(_ attributed: NSMutableAttributedString, isUser: Bool) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let mono = UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)

        // フォントを設定
        attributed.addAttribute(.font, value: bodyFont, range: fullRange)

        // テキスト色を設定（User=白、Assistant=自動）
        let textColor: UIColor = isUser ? .white : .label
        attributed.addAttribute(.foregroundColor, value: textColor, range: fullRange)

        // コードブロックのスタイリング
        let pattern = "```([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: attributed.string, options: [], range: fullRange)
            for match in matches {
                attributed.addAttribute(.font, value: mono, range: match.range)
                attributed.addAttribute(.backgroundColor, value: UIColor.systemGray4, range: match.range)
                // コードブロック内も同じ色
                attributed.addAttribute(.foregroundColor, value: textColor, range: match.range)
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = nil
        textView.attributedText = nil
    }
}
