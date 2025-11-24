import SwiftUI

struct ChatView: View {
    @ObservedObject private var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    @State private var hasFinishedInitialFetch = false
    @FocusState private var isInputFocused: Bool

    init(viewModel: ChatViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if viewModel.canLoadMoreHistory {
                                historyLoader
                            }

                            ForEach(viewModel.messages) { message in
                                EquatableMessageBubble(message: message, runner: viewModel.runnerName)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical)
                        .transaction { $0.animation = nil }
                    }
                    .background(Color(.systemBackground))
                    .animation(nil, value: viewModel.messages.count)
                    .onAppear {
                        scrollProxy = proxy
                        // 初回表示時に最下部へスクロール
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom()
                        }
                    }
                    // 自動スクロールは一時無効化（フリーズ回避）。必要なら手動で最下部へ。
                    .onChange(of: viewModel.messages.count) { count in
                        if Constants.enableVerboseLogs {
                            print("DEBUG: [VIEW-ONCHANGE] message count changed: \(count)")
                        }
                        if !viewModel.isHistoryLoading {
                            hasFinishedInitialFetch = true
                        }
                        // scrollToBottom() を呼ばない
                    }
                    .onChange(of: isInputFocused) { focused in
                        if focused {
                            // キーボードが開いたら最下部にスクロール
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                scrollToBottom()
                            }
                        }
                    }
                }

                if viewModel.isHistoryLoading && viewModel.messages.isEmpty {
                    ProgressView("履歴を読み込み中...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }

            Divider()

            InputBar(
                text: $viewModel.inputText,
                onSend: viewModel.sendMessage,
                onCancel: viewModel.cancelInference,
                isLoading: viewModel.isLoading,
                isFocused: $isInputFocused
            )
#if DEBUG
            HStack {
                Button("100KB送信") {
                    viewModel.sendLoadTestPayload()
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                Spacer()
            }
#endif
        }
        .refreshable {
            await viewModel.loadLatestMessages()
        }
        .onChange(of: viewModel.isHistoryLoading) { loading in
            if !loading {
                hasFinishedInitialFetch = true
            }
        }
        .alert("エラー", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var historyLoader: some View {
        Group {
            if viewModel.isLoadingMoreHistory {
                ProgressView()
            } else {
                Text("過去の履歴を読み込み")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .onAppear {
            guard hasFinishedInitialFetch else { return }
            Task { await viewModel.loadMoreMessages() }
        }
    }

    private func scrollToBottom() {
        guard let last = viewModel.messages.last else { return }
        DispatchQueue.main.async {
            withAnimation {
                scrollProxy?.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel(runner: "claude", roomId: "preview"))
}

// Equatable wrapper to avoid unnecessary re-layout when content/status unchanged
private struct EquatableMessageBubble: View, Equatable {
    let message: Message
    let runner: String

    var body: some View {
        MessageBubble(message: message, runner: runner)
    }

    static func == (lhs: EquatableMessageBubble, rhs: EquatableMessageBubble) -> Bool {
        lhs.message.id == rhs.message.id &&
        lhs.message.status == rhs.message.status &&
        lhs.message.content.count == rhs.message.content.count &&
        lhs.runner == rhs.runner
    }
}
