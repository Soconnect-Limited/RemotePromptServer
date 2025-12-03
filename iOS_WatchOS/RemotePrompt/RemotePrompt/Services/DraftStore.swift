import Foundation

/// v4.4: 入力中テキストの永続化ストア
/// thread + runner 単位で下書きを保存し、画面遷移後も復元可能にする
final class DraftStore {
    static let shared = DraftStore()

    private let userDefaults = UserDefaults.standard
    private let storageKey = "draft_texts_v1"

    /// メモリキャッシュ（UserDefaultsへの頻繁なアクセスを避ける）
    private var cache: [String: String] = [:]

    private init() {
        loadFromStorage()
    }

    /// 下書きを保存
    /// - Parameters:
    ///   - text: 入力テキスト（空文字の場合は削除）
    ///   - threadId: スレッドID
    ///   - runner: AIランナー名
    func saveDraft(_ text: String, threadId: String, runner: String) {
        let key = makeKey(threadId: threadId, runner: runner)
        if text.isEmpty {
            cache.removeValue(forKey: key)
        } else {
            cache[key] = text
        }
        saveToStorage()
    }

    /// 下書きを取得
    /// - Parameters:
    ///   - threadId: スレッドID
    ///   - runner: AIランナー名
    /// - Returns: 保存されていた下書きテキスト（なければ空文字）
    func loadDraft(threadId: String, runner: String) -> String {
        let key = makeKey(threadId: threadId, runner: runner)
        return cache[key] ?? ""
    }

    /// 特定スレッドの全runner下書きをクリア
    func clearDrafts(threadId: String) {
        let prefix = "\(threadId):"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        saveToStorage()
    }

    /// 全下書きをクリア
    func clearAll() {
        cache.removeAll()
        saveToStorage()
    }

    // MARK: - Private

    private func makeKey(threadId: String, runner: String) -> String {
        "\(threadId):\(runner)"
    }

    private func loadFromStorage() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        cache = decoded
    }

    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
