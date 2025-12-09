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
                    // 基本設定（モデル・パーミッションモード）
                    Section {
                        Picker("Model", selection: $viewModel.settings.claude.model) {
                            ForEach(["sonnet", "opus", "haiku"], id: \.self) { Text($0) }
                        }
                        Picker("Permission", selection: $viewModel.settings.claude.permissionMode) {
                            ForEach(["default", "ask", "deny"], id: \.self) { Text($0) }
                        }
                        CustomFlagsEditor(flags: $viewModel.settings.claude.customFlags)
                    } header: {
                        Text("基本設定")
                    }

                    // 使用可能ツール制限（--tools オプション）
                    Section {
                        ToolsEditor(tools: $viewModel.settings.claude.tools)
                    } header: {
                        Text("使用可能ツール (--tools)")
                    } footer: {
                        Text("ONにしたツールのみ使用可能になります。OFFのツールはClaude Codeが一切使えなくなります。")
                    }

                    // 動的ツール許可設定（--allowedTools / --disallowedTools）
                    AllowedToolsEditor(
                        allowedTools: $viewModel.settings.claude.allowedTools,
                        disallowedTools: $viewModel.settings.claude.disallowedTools
                    )
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

// v4.6: 動的ツール許可/拒否エディタ
private struct AllowedToolsEditor: View {
    @Binding var allowedTools: [String]
    @Binding var disallowedTools: [String]

    // Claude Codeで使用可能な主要ツール
    private let availableTools = [
        "Read", "Write", "Edit", "Bash", "Glob", "Grep",
        "Task", "WebFetch", "WebSearch", "NotebookEdit",
        "TodoWrite", "SlashCommand", "Skill", "BashOutput", "KillShell"
    ]

    // よく使うBashパターン
    private let bashPatterns = [
        "Bash(git:*)",
        "Bash(npm:*)",
        "Bash(yarn:*)",
        "Bash(python:*)",
        "Bash(pip:*)",
        "Bash(brew:*)"
    ]

    // 危険なBashパターン
    private let dangerousPatterns = ["Bash(rm:*)", "Bash(sudo:*)", "Bash(curl:*)", "Bash(wget:*)"]

    // カスタム入力用State
    @State private var customAllowedInput: String = ""
    @State private var customDisallowedInput: String = ""

    var body: some View {
        Group {
            // 許可ツール
            Section {
                ForEach(availableTools, id: \.self) { tool in
                    Toggle(tool, isOn: Binding(
                        get: { allowedTools.contains(tool) },
                        set: { isOn in
                            if isOn {
                                allowedTools.append(tool)
                                disallowedTools.removeAll { $0 == tool }
                            } else {
                                allowedTools.removeAll { $0 == tool }
                            }
                        }
                    ))
                    .tint(.green)
                }
            } header: {
                Text("許可するツール")
            }

            Section {
                ForEach(bashPatterns, id: \.self) { pattern in
                    Toggle(pattern, isOn: Binding(
                        get: { allowedTools.contains(pattern) },
                        set: { isOn in
                            if isOn {
                                allowedTools.append(pattern)
                                disallowedTools.removeAll { $0 == pattern }
                            } else {
                                allowedTools.removeAll { $0 == pattern }
                            }
                        }
                    ))
                    .tint(.green)
                }

                // カスタム入力
                HStack {
                    TextField("カスタム (例: mcp__*)", text: $customAllowedInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("追加") {
                        addCustomAllowed()
                    }
                    .disabled(customAllowedInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // カスタム追加されたツール
                ForEach(customAllowedTools, id: \.self) { tool in
                    HStack {
                        Text(tool)
                            .foregroundColor(.green)
                        Spacer()
                        Button {
                            allowedTools.removeAll { $0 == tool }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Bashパターン（許可）")
            }

            // 拒否ツール
            Section {
                ForEach(dangerousPatterns, id: \.self) { pattern in
                    Toggle(pattern, isOn: Binding(
                        get: { disallowedTools.contains(pattern) },
                        set: { isOn in
                            if isOn {
                                disallowedTools.append(pattern)
                                allowedTools.removeAll { $0 == pattern }
                            } else {
                                disallowedTools.removeAll { $0 == pattern }
                            }
                        }
                    ))
                    .tint(.red)
                }

                // カスタム入力
                HStack {
                    TextField("カスタム (例: Bash(chmod:*))", text: $customDisallowedInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("追加") {
                        addCustomDisallowed()
                    }
                    .disabled(customDisallowedInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // カスタム追加されたツール
                ForEach(customDisallowedTools, id: \.self) { tool in
                    HStack {
                        Text(tool)
                            .foregroundColor(.red)
                        Spacer()
                        Button {
                            disallowedTools.removeAll { $0 == tool }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("拒否するツール")
            }
        }
    }

    // プリセット以外のカスタムツール
    private var customAllowedTools: [String] {
        allowedTools.filter { tool in
            !availableTools.contains(tool) && !bashPatterns.contains(tool)
        }
    }

    private var customDisallowedTools: [String] {
        disallowedTools.filter { tool in
            !dangerousPatterns.contains(tool)
        }
    }

    private func addCustomAllowed() {
        let trimmed = customAllowedInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !allowedTools.contains(trimmed) {
            allowedTools.append(trimmed)
            disallowedTools.removeAll { $0 == trimmed }
        }
        customAllowedInput = ""
    }

    private func addCustomDisallowed() {
        let trimmed = customDisallowedInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !disallowedTools.contains(trimmed) {
            disallowedTools.append(trimmed)
            allowedTools.removeAll { $0 == trimmed }
        }
        customDisallowedInput = ""
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
