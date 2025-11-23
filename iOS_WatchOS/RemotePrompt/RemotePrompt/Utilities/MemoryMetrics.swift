import Foundation
import os.log

#if DEBUG && MEMORY_METRICS
enum MemoryMetrics {
    private static let log = OSLog(subsystem: "RemotePrompt", category: "Memory")

    /// Returns resident size in megabytes.
    static func rssMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return -1 }
        return Double(info.resident_size) / 1_048_576.0
    }

    static func logRSS(_ label: String, extra: String? = nil) {
        let mb = rssMB()
        if mb >= 0 {
            if let extra {
                os_log("DEBUG: [MEM] %{public}@ RSS=%.1fMB %{public}@", log: log, type: .info, label, mb, extra)
            } else {
                os_log("DEBUG: [MEM] %{public}@ RSS=%.1fMB", log: log, type: .info, label, mb)
            }
        }
    }
}
#endif
