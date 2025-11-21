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
                    TextField("スレッド名", text: $threadName)
                        .focused($isTextFieldFocused)
                } header: {
                    Text("新しいスレッド")
                } footer: {
                    Text("会話を整理するためのスレッド名を入力してください")
                }
            }
            .navigationTitle("スレッド作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        onCreate(threadName.isEmpty ? "無題" : threadName)
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
