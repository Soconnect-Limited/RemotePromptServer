import SwiftUI

struct RoomSettingsView: View {
    let room: Room
    let runner: String
    @StateObject private var viewModel: RoomSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(room: Room, runner: String) {
        self.room = room
        self.runner = runner
        _viewModel = StateObject(wrappedValue: RoomSettingsViewModel(room: room, runner: runner))
    }

    private var reasoningEffortOptions: [String] {
        // gpt-5.1-codex-max のみ extra-high をサポート
        if viewModel.settings.codex.model == "gpt-5.1-codex-max" {
            return ["low", "medium", "high", "extra-high"]
        } else {
            return ["low", "medium", "high"]
        }
    }

    private var runnerDisplayName: String {
        L10n.Settings.runnerSettings(runner)
    }

    var body: some View {
        NavigationStack {
            Form {
                if runner == "claude" {
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
                } else if runner == "codex" {
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
                            ForEach(reasoningEffortOptions, id: \.self) { Text($0) }
                        }
                        CustomFlagsEditor(flags: $viewModel.settings.codex.customFlags)
                    }
                } else if runner == "gemini" {
                    Section("Gemini") {
                        Picker("Model", selection: $viewModel.settings.gemini.model) {
                            ForEach(["gemini-3.0-pro", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.0-flash"], id: \.self) { Text($0) }
                        }
                        Toggle("Sandbox", isOn: $viewModel.settings.gemini.sandbox)
                        Toggle("YOLO Mode", isOn: $viewModel.settings.gemini.yolo)
                        Picker("Approval", selection: $viewModel.settings.gemini.approvalMode) {
                            ForEach(["default", "auto_edit", "yolo"], id: \.self) { Text($0) }
                        }
                        CustomFlagsEditor(flags: $viewModel.settings.gemini.customFlags)
                    }
                }
            }
            .navigationTitle(runnerDisplayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) { Task { await save() } }
                        .disabled(viewModel.isLoading)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(L10n.RoomSettings.resetDefault) { Task { await resetToDefault() } }
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
            .alert(L10n.Common.error, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button(L10n.Common.ok, role: .cancel) { viewModel.errorMessage = nil }
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
                Text(L10n.RoomSettings.sendValue(flags.joined(separator: ", ")))
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
    RoomSettingsView(
        room: Room(
            id: UUID().uuidString,
            name: "Preview Room",
            workspacePath: "/tmp",
            icon: "📁",
            deviceId: "device",
            createdAt: Date(),
            updatedAt: Date()
        ),
        runner: "claude"
    )
}
