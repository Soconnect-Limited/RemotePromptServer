import SwiftUI

struct MessageBubble: View {
    let message: Message
    let runner: String

    var body: some View {
        HStack(alignment: .top) {
            if message.type == .assistant || message.type == .system {
                avatar
            } else {
                Spacer(minLength: 0) // ユーザーメッセージは左余白で右寄せ
            }

            VStack(alignment: message.type == .user ? .trailing : .leading, spacing: 4) {
                bubble
                statusRow
            }

            if message.type == .assistant || message.type == .system {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal)
    }

    private var bubble: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.type == .assistant {
                Group {
                    if message.content.isEmpty && message.isRunning {
                        ProgressView("応答を生成中...")
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    } else if message.content.isEmpty {
                        Text("結果を待機中…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    } else {
                        MarkdownView(content: message.content)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    }
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)

                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)

                Text(message.content)
                    .foregroundColor(message.type == .user ? .white : .primary)
                    .padding(12)
                    .background(message.type == .user ? Color.blue : Color(.systemGray5))
                    .cornerRadius(16)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .trailing)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 4) {
            if message.isRunning {
                ProgressView()
                    .scaleEffect(0.6)
            }
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if message.status == .completed {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if message.status == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var avatar: some View {
        Image(aiIconName)
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var aiIconName: String {
        switch runner.lowercased() {
        case "codex":
            return "Codex"
        default:
            return "Claude-Code"
        }
    }

    private var statusText: String {
        switch message.status {
        case .sending:
            return "送信中"
        case .queued:
            return "待機中"
        case .running:
            return "実行中"
        case .completed:
            if let finished = message.finishedAt {
                return finished.formatted(date: .omitted, time: .shortened)
            }
            return "完了"
        case .failed:
            return "失敗"
        }
    }
}
