import SwiftUI

struct CreateRoomView: View {
    @ObservedObject var viewModel: RoomsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var workspacePath = ""
    @State private var icon = "📁"
    @State private var isSubmitting = false

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("ルーム名", text: $name)
                    TextField("ワークスペースパス", text: $workspacePath)
                    TextField("アイコン (絵文字)", text: $icon)
                        .textInputAutocapitalization(.never)
                }

                if let error = viewModel.errorMessage {
                    Section("エラー") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("新規ルーム")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("作成")
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if await viewModel.createRoom(name: name, workspacePath: workspacePath, icon: icon) != nil {
            dismiss()
        }
    }
}

#Preview {
    CreateRoomView(viewModel: RoomsViewModel())
}
