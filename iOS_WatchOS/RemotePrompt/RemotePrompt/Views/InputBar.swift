import SwiftUI

struct InputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let isLoading: Bool
    @FocusState.Binding var isFocused: Bool

    private func send() {
        onSend()
        // キーボードは開いたままにする（連続送信のため）
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let result = hasText && !isLoading
        print("DEBUG: InputBar canSend - hasText: \(hasText), isLoading: \(isLoading), result: \(result)")
        return result
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
                    .onChange(of: text) { newValue in
                        print("DEBUG: InputBar TextField - text changed to: '\(newValue)'")
                    }
                    .onChange(of: isFocused) { newValue in
                        print("DEBUG: InputBar TextField - focus changed to: \(newValue)")
                    }
                    .onChange(of: isLoading) { newValue in
                        print("DEBUG: InputBar TextField - isLoading changed to: \(newValue)")
                    }
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
