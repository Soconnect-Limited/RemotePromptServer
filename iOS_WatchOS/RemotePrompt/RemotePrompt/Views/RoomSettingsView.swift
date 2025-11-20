import SwiftUI

struct RoomSettingsView: View {
    let room: Room
    @StateObject private var viewModel: RoomSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(room: Room) {
        self.room = room
        _viewModel = StateObject(wrappedValue: RoomSettingsViewModel(room: room))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Claude") {
                    Picker("Model", selection: $viewModel.settings.claude.model) {
                        ForEach(["sonnet", "opus", "haiku"], id: \.self) { Text($0) }
                    }
                    Picker("Permission", selection: $viewModel.settings.claude.permissionMode) {
                        ForEach(["default", "ask", "deny"], id: \.self) { Text($0) }
                    }
                    ToolsEditor(tools: $viewModel.settings.claude.tools)
                    CustomFlagsEditor(flags: $viewModel.settings.claude.customFlags)
                }

                Section("Codex") {
                    Picker("Model", selection: $viewModel.settings.codex.model) {
                        ForEach(["gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-codex-max"], id: \.self) { Text($0) }
                    }
                    Picker("Sandbox", selection: $viewModel.settings.codex.sandbox) {
                        ForEach(["read-only", "workspace-write", "danger-full-access"], id: \.self) { Text($0) }
                    }
                    Picker("Approval", selection: $viewModel.settings.codex.approvalPolicy) {
                        ForEach(["untrusted", "on-failure", "on-request", "never"], id: \.self) { Text($0) }
                    }
                    Picker("Reasoning", selection: $viewModel.settings.codex.reasoningEffort) {
                        ForEach(["low", "medium", "high", "extra-high"], id: \.self) { Text($0) }
                    }
                    CustomFlagsEditor(flags: $viewModel.settings.codex.customFlags)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(viewModel.isLoading)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("デフォルトに戻す") { Task { await resetToDefault() } }
                        .disabled(viewModel.isLoading)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding()
                }
            }
            .alert("エラー", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task { await viewModel.load() }
        }
    }

    private func save() async {
        let ok = await viewModel.save()
        if ok { dismiss() }
    }

    private func resetToDefault() async {
        let ok = await viewModel.setDefaultToServer()
        if ok { dismiss() }
    }
}

private struct ToolsEditor: View {
    @Binding var tools: [String]
    private let allTools = ["Bash", "Edit", "Read", "Write", "Grep", "Glob", "Task", "WebFetch", "WebSearch", "NotebookEdit", "TodoWrite", "SlashCommand", "Skill"]

    var body: some View {
        ForEach(allTools, id: \.self) { tool in
            Toggle(tool, isOn: Binding(
                get: { tools.contains(tool) },
                set: { isOn in
                    if isOn {
                        tools.append(tool)
                    } else {
                        tools.removeAll { $0 == tool }
                    }
                }
            ))
        }
    }
}

private struct CustomFlagsEditor: View {
    @Binding var flags: [String]
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("--verbose, --max-tokens=100", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text) { newValue in
                    flags = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
            if !flags.isEmpty {
                Text("送信値: " + flags.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            text = flags.joined(separator: ", ")
        }
    }
}

#Preview {
    RoomSettingsView(room: Room(
        id: UUID().uuidString,
        name: "Preview Room",
        workspacePath: "/tmp",
        icon: "📁",
        deviceId: "device",
        createdAt: Date(),
        updatedAt: Date()
    ))
}
