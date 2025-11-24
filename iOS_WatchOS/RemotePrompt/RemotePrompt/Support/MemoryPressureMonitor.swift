import Foundation

@available(iOS 13.0, *)
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()
    private var source: DispatchSourceMemoryPressure?

    func start(onWarning: @escaping () -> Void, onCritical: @escaping () -> Void) {
        guard source == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        src.setEventHandler { [weak self] in
            guard let data = self?.source?.data else { return }
            if data.contains(.warning) {
                print("DEBUG: [MEMORY-PRESSURE] WARNING")
                onWarning()
            }
            if data.contains(.critical) {
                print("DEBUG: [MEMORY-PRESSURE] CRITICAL")
                onCritical()
            }
        }
        src.resume()
        source = src
    }
}
