import SwiftUI

struct JobDetailView: View {
    @StateObject private var viewModel: JobDetailViewModel
    private let jobId: String

    init(jobId: String) {
        self.jobId = jobId
        _viewModel = StateObject(wrappedValue: JobDetailViewModel(jobId: jobId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            statusSection
            outputSection
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.loadJob()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onDisappear {
            viewModel.stopSSEStreaming()
            viewModel.stopPolling()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ジョブID")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(jobId)
                .font(.callout)
                .textSelection(.enabled)
            if viewModel.isSSEConnected {
                Label("リアルタイム更新中", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if viewModel.job?.isRunning == true {
                Label("ポーリングで監視中", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("読み込み中…")
            } else if let job = viewModel.job {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ステータス: \(job.status.uppercased())")
                        .font(.headline)
                    if let started = job.startedAt {
                        Text("開始: \(started.formatted(date: .numeric, time: .shortened))")
                    }
                    if let finished = job.finishedAt {
                        Text("完了: \(finished.formatted(date: .numeric, time: .shortened))")
                    }
                    if let exit = job.exitCode {
                        Text("終了コード: \(exit)")
                    }
                }
            } else {
                Text("ジョブ情報が見つかりません")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("出力")
                .font(.headline)
            if let stdout = viewModel.job?.stdout, !stdout.isEmpty {
                ScrollView {
                    Text(stdout)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            } else {
                Text("出力はまだ利用できません")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
