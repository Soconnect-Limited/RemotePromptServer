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
                Section(header: Text(L10n.Room.sectionBasic)) {
                    TextField(L10n.Room.fieldName, text: $name)
                        .accessibilityIdentifier("createRoom.name")
                    TextField(L10n.Room.fieldWorkspace, text: $workspacePath)
                        .accessibilityIdentifier("createRoom.workspacePath")
                    TextField(L10n.Room.fieldIcon, text: $icon)
                        .accessibilityIdentifier("createRoom.icon")
                        .textInputAutocapitalization(.never)
                }

                if let error = viewModel.errorMessage {
                    Section(L10n.Common.error) {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(L10n.Room.createTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(L10n.Common.create)
                        }
                    }
                    .accessibilityIdentifier("createRoom.submit")
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
