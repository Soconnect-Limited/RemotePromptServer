import SwiftUI

struct ChatView: View {
    @ObservedObject private var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    @State private var hasFinishedInitialFetch = false

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
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical)
                    }
                    .background(Color(.systemBackground))
                    .onAppear { scrollProxy = proxy }
                    .onChange(of: viewModel.messages.count) { _ in
                        if !viewModel.isHistoryLoading {
                            hasFinishedInitialFetch = true
                        }
                        if !viewModel.isLoadingMoreHistory {
                            scrollToBottom()
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
                isLoading: viewModel.isLoading
            )
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
