import SwiftUI
import UIKit

/// SwiftUIからUIKitチャットリストを利用するためのブリッジ。
struct ChatListRepresentable: UIViewRepresentable {
    /// 表示対象のメッセージ配列（最新順を想定）。
    var messages: [Message]

    func makeUIView(context: Context) -> ChatListContainerView {
        let view = ChatListContainerView()
        view.tableView.dataSource = context.coordinator
        view.tableView.delegate = context.coordinator
        view.tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseId)
        context.coordinator.tableView = view.tableView
        context.coordinator.reload(with: messages)
        return view
    }

    func updateUIView(_ uiView: ChatListContainerView, context: Context) {
        context.coordinator.reload(with: messages)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        weak var tableView: UITableView?
        private var messages: [Message] = []

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
            cell.configure(with: msg)
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

    private let bubbleView = UIView()
    private let textView = UITextView()

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
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 12
        bubbleView.layer.masksToBounds = true
        contentView.addSubview(bubbleView)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        bubbleView.addSubview(textView)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            textView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            textView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
            textView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12)
        ])
    }

    func configure(with message: Message) {
        let isUser = message.type == .user
        bubbleView.backgroundColor = isUser ? UIColor.systemBlue.withAlphaComponent(0.12) : UIColor.secondarySystemBackground
        textView.textColor = isUser ? .label : .label
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]

        let markdown = message.content
        if let attributed = try? AttributedString(markdown: markdown) {
            let mutable = NSMutableAttributedString(attributed)
            applyCodeStyling(mutable)
            textView.attributedText = mutable
        } else {
            textView.text = markdown
            textView.font = UIFont.preferredFont(forTextStyle: .body)
        }
    }

    private func applyCodeStyling(_ attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let mono = UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
        attributed.addAttribute(.font, value: bodyFont, range: fullRange)

        let pattern = "```([\\s\\S]*?)```" // code fences
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: attributed.string, options: [], range: fullRange)
            for match in matches {
                attributed.addAttribute(.font, value: mono, range: match.range)
                attributed.addAttribute(.backgroundColor, value: UIColor.systemGray5, range: match.range)
            }
        }
    }
}
