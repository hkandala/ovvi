import HerdrKit
import SwiftUI

/// A match scrolls herdr's viewport to it, which every client of the pane shares.
@MainActor @Observable
final class Find {
    let paneID: String
    var query = "" {
        // The field writes the same text back when it takes the keyboard again (a second ⌘F).
        didSet {
            if query != oldValue {
                search(last: true)
            }
        }
    }

    private(set) var matches: [Int] = []
    private(set) var current: Int?
    private(set) var shown: [Hit] = []
    private(set) var shownCurrent: Int?
    @ObservationIgnored var stale = false
    @ObservationIgnored private var lines: [String] = []
    /// The screen's blank rows under its last text, which herdr's recent text leaves out but its offset counts.
    @ObservationIgnored private var blank = 0
    @ObservationIgnored private var rows = 0
    @ObservationIgnored private let store: HostStore
    @ObservationIgnored private var target: Int?
    @ObservationIgnored private var lastFrame: ContinuousClock.Instant?
    @ObservationIgnored private var working = false
    /// Set by its page: a read or step that ends later must not scroll herdr's shared viewport again.
    @ObservationIgnored private var closed = false

    init(paneID: String, store: HostStore) {
        self.paneID = paneID
        self.store = store
    }

    var count: String {
        query.isEmpty ? "" : "\(current.map { $0 + 1 } ?? 0) of \(matches.count)"
    }

    func read() async {
        guard let client = store.client else { return }
        do {
            // 5000: herdr's buffer; a text cut at 5000 lines cannot tell its blank rows.
            let text = try await client.recent(paneID, lines: 5000)
            let scroll = try await client.pane(paneID).scroll
            lines = Self.lines(text)
            rows = scroll?.viewportRows ?? 0
            if scroll?.offsetFromBottom == 0 {
                // herdr's visible text also leaves the blank rows out.
                blank = try await max(rows - Self.lines(client.screen(paneID)).count, 0)
            } else {
                let total = (scroll?.maxOffsetFromBottom ?? 0) + rows
                blank = lines.count < 5000 ? max(total - lines.count, 0) : 0
            }
            stale = false
            search(last: false)
        } catch {
            guard !closed else { return }
            store.show(Notice(text: error.localizedDescription))
        }
    }

    func step(_ offset: Int) async {
        if stale {
            await read()
        }
        guard !matches.isEmpty else { return }
        current = ((current ?? 0) + offset + matches.count) % matches.count
        show()
    }

    private func search(last: Bool) {
        let query = query.lowercased()
        matches = query.isEmpty ? [] : lines.indices.flatMap { index in
            Array(repeating: index, count: lines[index].ranges(of: query).count)
        }
        current = matches.isEmpty ? nil : last ? matches.count - 1 : min(current ?? .max, matches.count - 1)
        if current == nil {
            shown = []
            shownCurrent = nil
        }
        show()
    }

    private var distance: Int? {
        current.map { lines.count - 1 - matches[$0] + blank }
    }

    private func show() {
        if let distance {
            scroll(max(distance - rows / 2, 0))
        }
    }

    /// ponytail: columns count characters, so a line with wide characters (CJK, emoji) ahead of a match puts its
    /// highlight off; measure cell widths if that matters.
    private func locate(_ client: any Multiplexer) async {
        // Taken ahead of the reads: a query changed meanwhile drops the result (its own scroll locates again).
        let query = query.lowercased(), distance = distance
        guard let distance, !query.isEmpty, let screen = try? await client.screen(paneID),
              let scroll = try? await client.pane(paneID).scroll, let offset = scroll.offsetFromBottom
        else {
            shown = []
            shownCurrent = nil
            return
        }
        guard self.query.lowercased() == query else { return }
        let screenRows = Self.lines(screen)
        shown = screenRows.indices.flatMap { row in
            screenRows[row].ranges(of: query).map { range in
                Hit(row: row, column: screenRows[row].distance(from: screenRows[row].startIndex,
                                                               to: range.lowerBound),
                    length: query.count)
            }
        }
        let expected = (scroll.viewportRows ?? rows) - 1 - (distance - offset)
        shownCurrent = shown.indices.min { abs(shown[$0].row - expected) < abs(shown[$1].row - expected) }
    }

    /// herdr's text ends with a newline; the empty piece after it is not a line.
    private static func lines(_ text: String) -> [String] {
        var lines = text.lowercased().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    struct Hit {
        let row, column, length: Int
    }

    func close() {
        closed = true
        scroll(0)
    }

    private func scroll(_ offset: Int) {
        guard !closed || offset == 0 else { return }
        target = offset
        work()
    }

    /// Placed 0.3 s after the last frame of a burst, at most 1 s on: agent TUIs redraw all the time.
    func screenChanged() {
        lastFrame = .now
        work()
    }

    /// Not a `store.write`: not queued behind other writes between keystrokes, and `locate`'s `pane.get` is the read
    /// after it.
    private func work() {
        guard !working, let client = store.client else { return }
        working = true
        Task {
            while target != nil || lastFrame != nil {
                if let offset = target {
                    target = nil
                    do {
                        try await client.scroll(paneID, offsetFromBottom: offset)
                    } catch {
                        store.show(Notice(text: error.localizedDescription))
                    }
                } else {
                    let began = ContinuousClock.now
                    while target == nil, let last = lastFrame, .now - last < .milliseconds(300),
                          .now - began < .seconds(1)
                    {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if target != nil {
                        continue
                    }
                }
                lastFrame = nil
                if target == nil {
                    await locate(client)
                }
            }
            working = false
        }
    }
}
