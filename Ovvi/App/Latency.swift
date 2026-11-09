import AppKit
import HerdrKit
import Observation
import SwiftUI

/// Runs `body` on the main run loop after Core Animation's commit (order 2000000), which runs before waiting and on
/// a loop's exit: what the turn drew (before waiting alone missed a flicker). Also on the `extra` activities.
@discardableResult
func afterCommit(_ extra: CFRunLoopActivity = [], _ body: @escaping @MainActor (CFRunLoopActivity) -> Void)
    -> CFRunLoopObserver
{
    let activities = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue | extra.rawValue
    let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, Int.max) { _, activity in
        MainActor.assumeIsolated { body(activity) }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    return observer!
}

/// e2e (`-recordLatency YES`): for each key or click, the time from the event to the end of the run loop turn whose
/// Core Animation commit drew a change of the key window (its page, workspace, tab, tabs, cards, panel or dialog),
/// how many turns that took, the time from the app taking the event to that end (an accessibility client's queries
/// can hold the event back for seconds), and how many times a panel's list was made for it: "⌘T 12ms 0 9ms 0".
@MainActor @Observable
final class Latency {
    static let shared = Latency()
    static let isOn = UserDefaults.standard.bool(forKey: "recordLatency")
    /// The sidebar's rows made (a space's or an agent's body), for the scroll and main records.
    private(set) static var rows = 0

    static func madeRow() -> Bool {
        if isOn {
            rows += 1
        }
        return true
    }

    private(set) var recorded: [String] = []
    /// The window's open panel, as it was last drawn.
    @ObservationIgnored var panel = ""
    /// The filter of the list made last: a typed key changes what the window shows. Each list made counts, so one
    /// made many times for one key shows in the key's record.
    @ObservationIgnored var filter = "" {
        didSet { lists += 1 }
    }

    @ObservationIgnored private var lists = 0
    @ObservationIgnored private var pending: Pending?
    private struct Pending {
        let name: String, time: TimeInterval, state: String
        /// When the app took the event: what came before is waiting (another app's queries, an earlier turn).
        let taken = ProcessInfo.processInfo.systemUptime
        var turns = 0
    }

    /// Once, at launch.
    func install() {
        guard Self.isOn else { return }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { event in
            MainActor.assumeIsolated { self.event(event) }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { self.meter.scrolled() }
            return event
        }
        afterCommit(.afterWaiting) { activity in
            if activity == .afterWaiting {
                self.awake = ProcessInfo.processInfo.systemUptime
            } else {
                // A nested run loop's exit (menu or scroll tracking) is no sleep: the turn goes on.
                self.turned(sleeps: activity == .beforeWaiting)
            }
        }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(5))
                recordMain()
            }
        }
    }

    /// The main thread's work in the last 5 s: run loop turns from wake to sleep, the longest, the
    /// snapshots applied and their own time, and the sidebar's rows made: "main 812ms 120ms 34 210ms 40".
    private func recordMain() {
        // A turn still running counts up to now, so a main thread that never sleeps does not show as idle.
        endTurn(next: awake.map { _ in ProcessInfo.processInfo.systemUptime })
        let line = "main \(Int(busy * 1000))ms \(Int(longest * 1000))ms \(snapshots) \(Int(applying * 1000))ms"
            + " \(Self.rows - rowsBefore)"
        rowsBefore = Self.rows
        record(line)
        (busy, longest, snapshots, applying) = (0, 0, 0, 0)
    }

    /// The turn since `awake` ends now; `next` starts another.
    private func endTurn(next: TimeInterval? = nil) {
        if let awake {
            let turn = ProcessInfo.processInfo.systemUptime - awake
            busy += turn
            longest = max(longest, turn)
        }
        awake = next
    }

    /// In `recorded`, and on stderr (unbuffered) for a run by hand: there no accessibility client's queries take
    /// the main thread.
    private func record(_ line: String) {
        recorded.append(line)
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }

    /// The main thread's own time, for `applied`: not the wall clock, which also counts a time the process was
    /// stopped (the e2e helper's `heap` stops it for seconds, and once did so inside an apply: 10.8 s).
    static var threadTime: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9
    }

    /// A snapshot's apply on the main thread, from `start` (`threadTime`) on.
    func applied(since start: TimeInterval) {
        guard Self.isOn else { return }
        let time = Self.threadTime - start
        snapshots += 1
        applying += time
        meter.step("apply:\(Int(time * 1000))")
    }

    @ObservationIgnored private var awake: TimeInterval?
    @ObservationIgnored private var busy = 0.0
    @ObservationIgnored private var longest = 0.0
    @ObservationIgnored private var applying = 0.0
    @ObservationIgnored private var snapshots = 0
    @ObservationIgnored private var rowsBefore = 0
    @ObservationIgnored private lazy var meter = FrameMeter { self.record($0) }

    private func event(_ event: NSEvent) {
        let name = event.type == .keyDown
            ? Self.glyphs(event.modifierFlags) + (event.charactersIgnoringModifiers ?? "").uppercased() : "click"
        pending = Pending(name: name, time: event.timestamp, state: state)
        lists = 0
    }

    private func turned(sleeps: Bool) {
        if sleeps {
            endTurn()
        }
        guard var pending else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - pending.time
        if state != pending.state {
            self.pending = nil
            let work = ProcessInfo.processInfo.systemUptime - pending.taken
            record("\(pending.name) \(Int(elapsed * 1000))ms \(pending.turns) \(Int(work * 1000))ms \(lists)")
        } else if elapsed > 3 {
            self.pending = nil
        } else {
            pending.turns += 1
            self.pending = pending
        }
    }

    /// What the key window shows, in short; the overview too.
    private var state: String {
        guard let pages = WindowPages.windows.first, let page = pages.current else { return "" }
        let workspace = page.selectedWorkspace, tab = page.selectedTab
        return [page.id, workspace?.id ?? "", tab?.id ?? "", workspace?.tabs.map(\.id).joined(separator: ",") ?? "",
                tab?.tree?.paneIDs.joined(separator: ",") ?? "", page.zoomedPaneID ?? "",
                page.closing == nil ? "" : "closing", panel, filter, pages.overview ? "overview" : "",
                // A space's fold.
                UserDefaults.agents.string(forKey: Page.openShelves) ?? ""]
            .joined(separator: " ")
    }

    /// The sidebar's pages after a swipe's lift: their offset at each frame for 0.8 s, in ms from the lift; first the
    /// ms to the last change, last the ms to the session's show (-1: none): "swipe 230ms 0:145.0,8:152.4,… 190".
    func lifted(_ offset: Double) {
        guard Self.isOn else { return }
        lifted = ProcessInfo.processInfo.systemUptime
        slide = []
        shownAt = -1
        slid(offset)
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            let path = slide.map { "\($0.0):\(($0.1 * 10).rounded() / 10)" }.joined(separator: ",")
            record("swipe \(slide.last?.0 ?? 0)ms \(path) \(shownAt)")
            lifted = nil
        }
    }

    func slid(_ offset: Double) {
        guard let lifted, slide.last?.1 != offset else { return }
        slide.append((Int((ProcessInfo.processInfo.systemUptime - lifted) * 1000), offset))
    }

    /// The swipe's session is about to show; its own record, as a key's, gives the time to the turn whose commit
    /// drew it ("session 40ms 0 40ms"). One record waits at a time: a key during the switch takes its place.
    func shown() {
        if let lifted {
            let now = ProcessInfo.processInfo.systemUptime
            shownAt = Int((now - lifted) * 1000)
            pending = Pending(name: "session", time: now, state: state)
        }
    }

    /// A split starts (a key, a button, the palette): its frames' record.
    func split() {
        if Self.isOn {
            meter.split()
        }
    }

    /// A step of the split being recorded: its name, its time from the split and the CPU of the frame it fell in,
    /// "list@12/9".
    func step(_ name: String) {
        if Self.isOn {
            meter.step(name)
        }
    }

    func note(_ text: String) {
        if Self.isOn {
            record(text)
        }
    }

    @ObservationIgnored private var shownAt = -1
    @ObservationIgnored private var lifted: TimeInterval?
    @ObservationIgnored private var slide: [(Int, Double)] = []

    private static func glyphs(_ flags: NSEvent.ModifierFlags) -> String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined()
    }
}

/// Frames while the window scrolls or splits, at the display's full rate: a display link runs from a scroll event
/// until 0.3 s after the last ("scroll <frames> <hitches> <ms> <p50> <p95> <max> <the main thread's CPU> <the sidebar's
/// rows made> <each hitch: its end+gap/CPU>"; a hitch, a frame over 25 ms after the one before), or for 1.2 s from a
/// split, its slide and what lands after ("split <frames> <hitches> <ms> <p50> <p95> <max> <the main thread's CPU>
/// <each hitch> <each step: name@time/CPU>", in ms; a hitch, over one and a half display frames).
@MainActor
private final class FrameMeter: NSObject {
    let record: (String) -> Void
    private var link: CADisplayLink?
    private var name = "", start = 0.0, last = 0.0, end = 0.0, cpu = 0.0
    private var gaps: [Double] = [], cpus: [Double] = [], lastCPU = 0.0, steps: [(String, Double)] = [], rowsBefore = 0

    init(record: @escaping (String) -> Void) {
        self.record = record
    }

    func scrolled() {
        run("scroll", until: ProcessInfo.processInfo.systemUptime + 0.3)
    }

    func split() {
        run("split", until: ProcessInfo.processInfo.systemUptime + 1.2)
    }

    func step(_ step: String) {
        if link != nil, name == "split" {
            steps.append((step, ProcessInfo.processInfo.systemUptime - start))
        }
    }

    private func run(_ name: String, until end: TimeInterval) {
        guard link == nil, let screen = NSScreen.main else {
            self.end = max(self.end, end)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        (self.name, self.end, start, last, gaps, steps) = (name, end, now, now, [], [])
        cpu = Latency.threadTime
        (lastCPU, cpus, rowsBefore) = (cpu, [], Latency.rows)
        link = screen.displayLink(target: self, selector: #selector(frame))
        // The display's full rate: ProMotion runs at 60 Hz or less when nothing asks for more.
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        link?.add(to: .main, forMode: .common)
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        gaps.append(now - last)
        last = now
        let thread = Latency.threadTime
        cpus.append(thread - lastCPU)
        lastCPU = thread
        guard now > end else { return }
        link.invalidate()
        self.link = nil
        let time = Int((now - start) * 1000)
        let sorted = gaps.sorted()
        let part = { (share: Double) in Int(sorted[Int(Double(sorted.count - 1) * share)] * 1000) }
        // Each hitch's end from the start, its gap, and the main thread's CPU in it: "130+41/30". A gap with little CPU
        // waited on the render server.
        var elapsed = 0.0
        let hitch = name == "scroll" ? 0.025 : link.duration * 1.5
        let hitches = zip(gaps, cpus).compactMap { gap, cpu in
            elapsed += gap
            return gap > hitch ? "\(Int(elapsed * 1000))+\(Int(gap * 1000))/\(Int(cpu * 1000))" : nil
        }
        let busy = Int((Latency.threadTime - cpu) * 1000)
        if name == "scroll" {
            record("scroll \(gaps.count) \(hitches.count) \(time)ms \(part(0.5)) \(part(0.95)) \(part(1)) \(busy)ms "
                + "\(Latency.rows - rowsBefore) " + hitches.joined(separator: ","))
            return
        }
        record("split \(gaps.count) \(hitches.count) \(time)ms \(part(0.5)) \(part(0.95)) \(part(1)) \(busy)ms "
            + hitches.joined(separator: ",") + " " + steps.map { step, time in
                // The CPU of the frame it fell in.
                var end = 0.0
                let cpu = zip(gaps, cpus).first { gap, _ in
                    end += gap
                    return end >= time
                }?.1 ?? 0
                return "\(step)@\(Int(time * 1000))/\(Int(cpu * 1000))"
            }.joined(separator: ","))
    }
}
