import SwiftUI

struct ChatView: View {
    @ObservedObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    init(viewModel: ChatViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatListRepresentable(messages: viewModel.messages, runner: viewModel.runnerName)
                .background(Color(.systemBackground))

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
        .background(Color(.systemBackground).ignoresSafeArea())
        .alert("エラー", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel(runner: "claude", roomId: "preview"))
}
