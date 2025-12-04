import SwiftUI

/// スレッド名を編集するビュー
struct EditThreadNameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var threadName: String
    @FocusState private var isTextFieldFocused: Bool

    let thread: Thread
    let onUpdate: (String) -> Void

    init(thread: Thread, onUpdate: @escaping (String) -> Void) {
        self.thread = thread
        self.onUpdate = onUpdate
        _threadName = State(initialValue: thread.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.Threads.fieldName, text: $threadName)
                        .focused($isTextFieldFocused)
                } header: {
                    Text(L10n.Threads.editTitle)
                }
            }
            .navigationTitle(L10n.Threads.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        onUpdate(threadName.isEmpty ? L10n.Threads.untitled : threadName)
                        dismiss()
                    }
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}

#Preview {
    EditThreadNameView(
        thread: Thread(
            id: "test",
            roomId: "room1",
            name: "テストスレッド",
            deviceId: "device1",
            createdAt: Date(),
            updatedAt: Date()
        )
    ) { name in
        print("Update to: \(name)")
    }
}
