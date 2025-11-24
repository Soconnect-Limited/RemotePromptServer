import SwiftUI

struct InputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onCancel: () -> Void
    let isLoading: Bool
    @FocusState.Binding var isFocused: Bool

    private func send() {
        onSend()
        // キーボードは開いたままにする（連続送信のため）
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Keyboard toolbar (shown when keyboard is visible)
            if isFocused {
                HStack {
                    // Cancel button (shown when inference is running)
                    if isLoading {
                        Button {
                            onCancel()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.body)
                                Text("推論キャンセル")
                                    .font(.callout)
                            }
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }

                    Spacer()

                    // Keyboard dismiss button
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
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend {
                            send()
                        }
                    }
                    .accessibilityIdentifier("chat.input")

                Button(action: send) {
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
