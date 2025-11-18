import SwiftUI

struct ContentView: View {
    @State private var jobId: String = ""
    @State private var selectedJobId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("ジョブID") {
                    TextField("例: 550e8400-e29b-41d4-a716-446655440000", text: $jobId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("ジョブ詳細を開く") {
                        let trimmed = jobId.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        selectedJobId = trimmed
                    }
                    .disabled(jobId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let id = selectedJobId {
                    Section("ジョブ詳細") {
                        JobDetailView(jobId: id)
                    }
                } else {
                    Section {
                        Text("ジョブIDを入力して「ジョブ詳細を開く」をタップすると、リアルタイム更新が始まります。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("RemotePrompt")
        }
        .onChange(of: jobId) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedJobId = nil
            }
        }
    }
}

#Preview {
    ContentView()
}
