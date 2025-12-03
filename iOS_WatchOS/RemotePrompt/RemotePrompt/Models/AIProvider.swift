import Foundation

/// AIプロバイダー定義
/// Claude Code, Codex, Gemini の3種類をサポート
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    /// 表示名
    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        }
    }

    /// SF Symbols アイコン名
    var systemImage: String {
        switch self {
        case .claude: return "bubble.left"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .gemini: return "sparkles"
        }
    }

}

/// AIプロバイダー個別設定
struct AIProviderConfiguration: Codable, Identifiable, Equatable, Hashable {
    let provider: AIProvider
    var isEnabled: Bool
    var sortOrder: Int

    var id: String { provider.id }

    enum CodingKeys: String, CodingKey {
        case provider
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
    }

    /// デフォルト設定を生成
    static func defaultConfigurations() -> [AIProviderConfiguration] {
        AIProvider.allCases.enumerated().map { index, provider in
            AIProviderConfiguration(
                provider: provider,
                isEnabled: true,  // 全プロバイダーをデフォルト有効
                sortOrder: index
            )
        }
    }
}

// MARK: - Collection Extensions

extension Array where Element == AIProviderConfiguration {
    /// ソート順でソート済みの配列を返す
    var sorted: [AIProviderConfiguration] {
        self.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 有効なプロバイダーのみをソート順で返す
    var enabledProviders: [AIProviderConfiguration] {
        self.filter { $0.isEnabled }.sorted
    }

    /// 指定プロバイダーの設定を取得
    func configuration(for provider: AIProvider) -> AIProviderConfiguration? {
        first { $0.provider == provider }
    }

    /// ソート順を更新（移動後のインデックスに基づく）
    mutating func updateSortOrder() {
        for (index, _) in self.enumerated() {
            self[index].sortOrder = index
        }
    }
}
