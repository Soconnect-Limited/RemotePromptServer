import Foundation

@available(iOS 13.0, *)
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()
    private var source: DispatchSourceMemoryPressure?
    
    /// Memory Leak Fix: コールバックを弱参照で保持
    private var warningCallbacks: [() -> Void] = []
    private var criticalCallbacks: [() -> Void] = []
    private let lock = NSLock()

    func start(onWarning: @escaping () -> Void, onCritical: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        // 既存のコールバックに追加（複数のViewModelから登録可能）
        warningCallbacks.append(onWarning)
        criticalCallbacks.append(onCritical)
        
        // 既にソースが開始済みなら追加のみ
        guard source == nil else { return }
        
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self = self, let data = self.source?.data else { return }
            
            self.lock.lock()
            let warnings = self.warningCallbacks
            let criticals = self.criticalCallbacks
            self.lock.unlock()
            
            if data.contains(.warning) {
                print("DEBUG: [MEMORY-PRESSURE] WARNING - clearing caches")
                // パースキャッシュをクリア
                ParsedMessageCache.shared.clear()
                warnings.forEach { $0() }
            }
            if data.contains(.critical) {
                print("DEBUG: [MEMORY-PRESSURE] CRITICAL - aggressive cleanup")
                // パースキャッシュをクリア
                ParsedMessageCache.shared.clear()
                criticals.forEach { $0() }
            }
        }
        src.resume()
        source = src
    }
    
    /// Memory Leak Fix: コールバックをリセット（テスト用）
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        warningCallbacks.removeAll()
        criticalCallbacks.removeAll()
    }
}
