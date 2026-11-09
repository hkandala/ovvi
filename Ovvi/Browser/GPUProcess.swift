import Darwin
import Foundation
import WebKit

/// WebKit ends its GPU process when it stops answering (a starved Mac) and starts another, but its signal fails (xpc:
/// "Operation not permitted"): the old one lives on and keeps every page's drawing connection, so every web card stays
/// blank, Reload too, while its page process is fine. The app ends that process: the pages connect to the new one
/// and draw again where they were, kept cards' when they show (their processes are paused until then).
/// WebKit has no public word of its GPU process: its pid is `WKProcessPool._gpuProcessIdentifier` (0 while none).
@MainActor
enum GPUProcess {
    /// Every 2 s, with the first web card. ponytail: one process WebKit gave up on per check; two swaps inside one
    /// check
    /// (WebKit waits seconds before it gives up) would leave the first.
    static let watch: Timer = {
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { check() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }()

    private static let key = "_gpuProcessIdentifier"
    /// The GPU processes WebKit had at the last check, with their start times: a pid used again is another process.
    private static var known: [pid_t: UInt64] = [:]

    static func check() {
        // Each card's pool: a pool no web view used has no GPU process (`processPool` is deprecated for that).
        let pools = PaneViewRegistry.recentWeb.compactMap { $0.registry?.webView($0.id)?.configuration }
            .compactMap { $0.value(forKey: "processPool") as? NSObject }
            .filter { $0.responds(to: NSSelectorFromString(key)) }
        // With no card, no page draws: WebKit may let its GPU process go.
        guard !pools.isEmpty else { return }
        let pids = Set(pools.compactMap { ($0.value(forKey: key) as? NSNumber)?.int32Value })
        for (pid, start) in known where !pids.contains(pid) && started(pid) == start {
            kill(pid, SIGKILL)
        }
        known = Dictionary(uniqueKeysWithValues: pids.compactMap { pid in started(pid).map { (pid, $0) } })
    }

    private static func started(_ pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }
}
