import SwiftUI

struct InputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let isLoading: Bool
    @FocusState.Binding var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Keyboard dismiss button (shown when keyboard is visible)
            if isFocused {
                HStack {
                    Spacer()
                    Button {
                        isFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
                .background(Color(.systemGray6))
            }

            HStack(spacing: 12) {
                TextField("メッセージを入力...", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(isLoading)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }
                    .accessibilityIdentifier("chat.input")

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.blue : Color.gray)
                }
                .accessibilityIdentifier("chat.send")
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}
