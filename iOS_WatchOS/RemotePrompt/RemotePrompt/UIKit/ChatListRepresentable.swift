import SwiftUI

/// SwiftUIからUIKitチャットリストを利用するためのブリッジ。
struct ChatListRepresentable: UIViewRepresentable {
    /// メッセージ配列。現段階では読み取り専用で表示のみ。
    var messages: [Message]

    func makeUIView(context: Context) -> ChatListContainerView {
        let view = ChatListContainerView()
        view.tableView.dataSource = context.coordinator
        view.tableView.delegate = context.coordinator
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

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        weak var tableView: UITableView?
        private var messages: [Message] = []

        // MARK: Public API
        func reload(with newMessages: [Message]) {
            messages = newMessages
            tableView?.reloadData()
        }

        // MARK: UITableViewDataSource
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            messages.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cellId = "chat.cell"
            let cell = tableView.dequeueReusableCell(withIdentifier: cellId) ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellId)
            let msg = messages[indexPath.row]
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.numberOfLines = 0
            cell.textLabel?.text = msg.type == .user ? "🙋‍♂️" : "🤖"
            cell.detailTextLabel?.text = msg.content
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
