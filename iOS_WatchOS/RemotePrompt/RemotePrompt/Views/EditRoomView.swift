import SwiftUI

struct EditRoomView: View {
    @ObservedObject var viewModel: RoomsViewModel
    @Environment(\.dismiss) private var dismiss

    let room: Room

    @State private var name: String
    @State private var workspacePath: String
    @State private var icon: String
    @State private var isSubmitting = false

    init(viewModel: RoomsViewModel, room: Room) {
        self.viewModel = viewModel
        self.room = room
        _name = State(initialValue: room.name)
        _workspacePath = State(initialValue: room.workspacePath)
        _icon = State(initialValue: room.icon)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSubmitting
    }

    private var hasChanges: Bool {
        name != room.name ||
        workspacePath != room.workspacePath ||
        icon != room.icon
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("ルーム名", text: $name)
                        .accessibilityIdentifier("editRoom.name")
                    TextField("ワークスペースパス", text: $workspacePath)
                        .accessibilityIdentifier("editRoom.workspacePath")
                    TextField("アイコン (絵文字)", text: $icon)
                        .accessibilityIdentifier("editRoom.icon")
                        .textInputAutocapitalization(.never)
                }

                if let error = viewModel.errorMessage {
                    Section("エラー") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("ルームを編集")
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
                            Text("保存")
                        }
                    }
                    .accessibilityIdentifier("editRoom.submit")
                    .disabled(!canSubmit || !hasChanges)
                }
            }
        }
    }

    private func submit() async {
        guard canSubmit, hasChanges else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if await viewModel.updateRoom(room, name: name, workspacePath: workspacePath, icon: icon) != nil {
            dismiss()
        }
    }
}

#Preview {
    EditRoomView(
        viewModel: RoomsViewModel(),
        room: Room(
            id: "preview",
            name: "Preview Room",
            workspacePath: "/path/to/workspace",
            icon: "📁",
            deviceId: "device",
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    )
}
