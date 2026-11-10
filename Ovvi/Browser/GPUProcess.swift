import Darwin
import Foundation
import HerdrKit
import os
import WebKit

/// WebKit ends its GPU process when it stops answering (a starved Mac) and starts another, but its signal fails (xpc:
/// "Operation not permitted"): the stuck one lives on and keeps every page's drawing connection, so every web card
/// stays blank, Reload too. Once the app ends it, the pages connect to the new one and draw again. WebKit has no public
/// word of its GPU process: its pid is `WKProcessPool._gpuProcessIdentifier` (0 while none).
@MainActor
enum GPUProcess {
    /// ponytail: one dropped process per pool and check; two swaps inside one check (WebKit waits seconds to give up)
    /// would leave the first.
    static let watch: Timer = {
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { check() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }()

    private static let key = "_gpuProcessIdentifier"
    private static let log = Logger(ovvi: "web")
    /// With its start time: a pid used again is another process. Per pool: a pool's pid is 0 until its own pages draw.
    private static let known = NSMapTable<NSObject, NSArray>.weakToStrongObjects()

    static func check() {
        let pools = PaneViewRegistry.recentWeb.compactMap { $0.registry?.webView($0.id)?.configuration }
            .compactMap { $0.value(forKey: "processPool") as? NSObject }
            .filter { $0.responds(to: NSSelectorFromString(key)) }
        // Many web views share a pool.
        for pool in Set(pools) {
            let pid = (pool.value(forKey: key) as? NSNumber)?.int32Value ?? 0
            // WebKit drops a pool's process only as it ends it (`gpuProcessExited`).
            if let old = known.object(forKey: pool) as? [UInt64], pid != pid_t(old[0]),
               started(pid_t(old[0])) == old[1]
            {
                let ended = kill(pid_t(old[0]), SIGKILL) == 0 ? "ok" : String(cString: strerror(errno))
                log.notice("Ended the GPU process \(old[0]) WebKit gave up on: \(ended, privacy: .public)")
            }
            known.setObject(started(pid).map { [UInt64(pid), $0] as NSArray }, forKey: pool)
        }
    }

    private static func started(_ pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }
}
