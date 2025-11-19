import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel(runner: "claude")
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
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
                        scrollToBottom()
                    }
                }

                Divider()

                InputBar(
                    text: $viewModel.inputText,
                    onSend: viewModel.sendMessage,
                    isLoading: viewModel.isLoading
                )
            }
            .navigationTitle("Claude Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("RemotePrompt")
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("履歴をクリア", role: .destructive) {
                            viewModel.clearChat()
                        }
                        Button("Codexに切り替え") {
                            // TODO: Runner切り替え
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("エラー", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
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
