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
                    TextField("スレッド名", text: $threadName)
                        .focused($isTextFieldFocused)
                } header: {
                    Text("スレッド名を編集")
                }
            }
            .navigationTitle("スレッド編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onUpdate(threadName.isEmpty ? "無題" : threadName)
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
