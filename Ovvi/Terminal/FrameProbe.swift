import AppKit
import IOSurface
import Observation

/// Each sample is drawn at the commit: a display link's frames miss commits. Not seen: commits off the main thread or
/// from a flush within a turn, and a card's own SwiftUI opacity. libghostty sets a new picture on the main thread, so
/// each is a turn's commit.
@MainActor @Observable
final class FrameProbe {
    static let shared = FrameProbe()
    static let isOn = UserDefaults.standard.bool(forKey: "recordFrames")
    private(set) var recorded = ""
    @ObservationIgnored private var shown: (page: String, tab: String)?
    @ObservationIgnored private var start = 0.0
    @ObservationIgnored private var samples: [ObjectIdentifier: [Sample?]] = [:]
    @ObservationIgnored private var inks: [String: [Bool]?] = [:]
    /// Commits that drew the TUI of a card whose chat is picked.
    @ObservationIgnored private var tuis = 0

    private struct Sample: Equatable {
        let ink: [Bool]?
        let fading: Bool
        let small: Bool
        /// Bottom-left based: a held view keeps its top left while its card's size changes.
        let topLeft: CGPoint
    }

    func install() {
        if Self.isOn {
            afterCommit { _ in self.turned() }
        }
    }

    private func turned() {
        guard let pages = WindowPages.windows.first, let window = pages.window, let page = pages.current
        else { return }
        // The tab's page after the overview counts as a change, even to the same tab.
        guard !pages.overview else {
            finish()
            shown = nil
            return
        }
        let tab = (page: page.id, tab: page.selectedTab?.id ?? "")
        let now = ProcessInfo.processInfo.systemUptime
        if shown.map({ $0 != tab }) ?? true {
            finish()
            shown = tab
            start = now
            // Its record ends with a turn after 1.5 s, also in an idle app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.turned() }
        }
        guard now - start < 1.5 else { return finish() }
        let panes = page.store.panes.filter { $0.tabID == page.selectedTab?.id && !page.floats($0) }
        for terminalID in Set(panes.compactMap(\.terminalID)) {
            guard let terminal = pages.terminals.terminals([terminalID]).first else { continue }
            let sample = sample(terminal.view, in: window), id = ObjectIdentifier(terminal)
            if sample != nil, page.store.chats[terminalID]?.showsChat == true {
                tuis += 1
            }
            if samples[id]?.last != .some(sample) {
                samples[id, default: []].append(sample)
            }
        }
    }

    private func sample(_ view: PaneSurfaceView, in window: NSWindow) -> Sample? {
        guard view.window === window, view.superview is SettlingHost else { return nil }
        let ink = (view.picture as? IOSurface).flatMap { surface in
            let key = "\(ObjectIdentifier(surface)) \(IOSurfaceGetSeed(surface))"
            if let ink = inks[key] {
                return ink
            }
            let ink = Self.ink(surface)
            inks[key] = ink
            return ink
        }
        let still = view.still.flatMap { $0 !== view.layer && $0.superlayer != nil && $0.contentsGravity == .resize
            ? $0 : nil
        }
        return Sample(ink: ink, fading: view.layer?.animation(forKey: "reveal") != nil,
                      small: still?.small(in: view) == true,
                      topLeft: view.convert(view.bounds, to: nil).integral.topLeft)
    }

    private func finish() {
        guard let shown, !samples.isEmpty else { return }
        var bad = tuis, frames = 0, codes = String(repeating: "t", count: tuis)
        for list in samples.values {
            guard let first = list.first, let last = list.last ?? nil else { continue }
            frames = max(frames, list.count)
            for sample in list {
                guard let sample else {
                    bad += 1
                    codes += "-"
                    continue
                }
                let blank = sample.ink.map { !$0.contains(true) && last.ink?.contains(true) == true } ?? true
                let code = blank ? "0" : sample.small ? "s" : sample.fading ? "f"
                    : !Self.same(sample.ink, first?.ink) && !Self.same(sample.ink, last.ink) ? "p"
                    : sample.topLeft != last.topLeft ? "j" : ""
                if !code.isEmpty {
                    bad += 1
                    codes += code
                }
                if code == "j", !codes.contains("(") {
                    codes += "(\(Int(sample.topLeft.x - last.topLeft.x)),\(Int(sample.topLeft.y - last.topLeft.y)))"
                }
            }
        }
        recorded += (recorded.isEmpty ? "" : "; ") + "\(shown.tab) \(bad)/\(frames) \(codes)"
        samples = [:]
        inks = [:]
        tuis = 0
    }

    private static func ink(_ surface: IOSurface) -> [Bool]? {
        guard !surface.emptied, surface.bytesPerElement == 4, surface.width > 0,
              surface.height > 0 else { return nil }
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self), row = surface.bytesPerRow
        let pixel = { (column: Int, line: Int) in
            let byte = base + line * row + column * 4
            return Int(byte[0]) + Int(byte[1]) + Int(byte[2]) + Int(byte[3])
        }
        let background = pixel(1, 1)
        let columns = 48, lines = 32, dots = 4, width = surface.width, height = surface.height
        return (0 ..< columns * lines).map { cell in
            (0 ..< dots * dots).contains { dot in
                let column = ((cell % columns) * dots + dot % dots) * width / (columns * dots)
                let line = ((cell / columns) * dots + dot / dots) * height / (lines * dots)
                return abs(pixel(column, line) - background) > 60
            }
        }
    }

    /// A few cells apart is the same picture: a cursor.
    private static func same(_ one: [Bool]?, _ two: [Bool]?) -> Bool {
        guard let one, let two else { return one == nil && two == nil }
        return zip(one, two).count { $0 != $1 } <= 8
    }
}

private extension CGRect {
    var topLeft: CGPoint {
        CGPoint(x: minX, y: maxY)
    }
}
