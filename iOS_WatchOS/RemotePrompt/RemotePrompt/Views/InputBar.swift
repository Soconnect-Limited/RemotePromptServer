import SwiftUI

struct InputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onSettingsTapped: (() -> Void)?
    let isLoading: Bool
    @FocusState.Binding var isFocused: Bool

    private func send() {
        onSend()
        // キーボードは開いたままにする（連続送信のため）
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Keyboard dismiss button (shown when keyboard is visible)
            if isFocused {
                HStack {
                    if let onSettingsTapped {
                        Button {
                            onSettingsTapped()
                        } label: {
                            Label("設定", systemImage: "gearshape")
                                .font(.body)
                        }
                        .accessibilityIdentifier("room.settings")
                        .accessibilityLabel("ルーム設定を開く")
                        Spacer()
                    } else {
                        Spacer()
                    }
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
