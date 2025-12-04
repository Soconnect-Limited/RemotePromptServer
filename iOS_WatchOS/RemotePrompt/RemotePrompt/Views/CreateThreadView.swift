import SwiftUI

/// 新しいスレッドを作成するビュー
struct CreateThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var threadName = ""
    @FocusState private var isTextFieldFocused: Bool

    let runner: String
    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.Threads.fieldName, text: $threadName)
                        .focused($isTextFieldFocused)
                } header: {
                    Text(L10n.Threads.new)
                } footer: {
                    Text(L10n.Threads.createHint)
                }
            }
            .navigationTitle(L10n.Threads.createTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.create) {
                        onCreate(threadName.isEmpty ? L10n.Threads.untitled : threadName)
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
    CreateThreadView(runner: "claude") { name in
        print("Create thread: \(name)")
    }
}
