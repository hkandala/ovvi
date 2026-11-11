import AppKit
import HerdrKit

extension HostStore {
    private static var quitting = false
    private static let refresh = Task { @MainActor in
        while await (try? Task.sleep(for: .seconds(10))) != nil {
            all.forEach { $0.markShown(refresh: true) }
        }
    }

    private static var input = ContinuousClock.now
    private static let inputs: Any? = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) {
        MainActor.assumeIsolated { input = .now }
        return $0
    }

    var away: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return ContinuousClock.now - Self.input > .seconds(60) || session?["CGSSessionScreenIsLocked"] as? Bool == true
            || !onScreen
    }

    var inView: Set<String> {
        floatingPanes
            .union(windows.filter(\.visible).compactMap(\.current).filter { $0.store === self }.flatMap { page in
                let zoomed = page.zoomedPaneID.flatMap { pane($0)?.tabID == page.selectedTab?.id ? $0 : nil }
                return zoomed.map { [$0] } ?? Array(page.shownTerminals.values)
            })
    }

    var floatingPanes: Set<String> {
        Set(windows.filter(\.visible).flatMap(\.withFloats).filter { $0.store === self }
            .flatMap { page in panes.filter(page.floats).map(\.id) })
    }

    /// A mark lasts 30 s, so an app that crashed stops claiming its panes. One batch after the other, so a quick hide
    /// and show of a pane cannot land out of order.
    func markShown(refresh: Bool = false) {
        _ = (Self.refresh, Self.inputs, Self.input) // starts the lazy statics; the idle clock from the first page shown
        guard let client else { return }
        let shown = Self.quitting ? [] : inView
        let changes = (refresh ? shown : shown.subtracting(marked)).map { ($0, true) }
            + marked.subtracting(shown).map { ($0, false) }
        marked = shown
        let open = Self.quitting || windows.isEmpty ? [] : Set(workspaces.map(\.id))
        let opens = (refresh ? open : open.subtracting(openMarked)).map { ($0, true) }
            + openMarked.subtracting(open).map { ($0, false) }
        openMarked = open
        guard !changes.isEmpty || !opens.isEmpty else { return }
        // The panes first: a tool reads `ovvi-shown` at each click, and the workspaces' marks, one call each (an ssh
        // trip on a remote machine), can be many. At quit all at once: one by one, ten took the whole 1 s (a herdr run
        // is about 0.1 s on a busy Mac), and the wait cut the rest. An earlier batch stops at the quit after its
        // current mark, so the quit's marks land after it and soon.
        let quitting = Self.quitting
        marking = Task { [marking] in
            await marking?.value
            guard quitting else {
                for (pane, shown) in changes where !Self.quitting {
                    try? await client.mark(pane, shown: shown)
                }
                for (workspace, open) in opens where !Self.quitting {
                    try? await client.mark(workspace: workspace, open: open)
                }
                return
            }
            await withTaskGroup { group in
                for (workspace, open) in opens {
                    group.addTask { try? await client.mark(workspace: workspace, open: open) }
                }
                for (pane, shown) in changes {
                    group.addTask { try? await client.mark(pane, shown: shown) }
                }
            }
        }
    }

    /// At most 1 s. A click in a marked pane after the quit would ask an app that is gone, and nothing would open.
    static func unmarkAll() async {
        quitting = true
        all.forEach { $0.markShown() }
        let marks = all.compactMap(\.marking)
        let (done, finish) = AsyncStream<Void>.makeStream()
        Task {
            for mark in marks {
                await mark.value
            }
            finish.yield()
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            finish.yield()
        }
        for await _ in done {
            break
        }
    }
}

extension WindowPages {
    func markShown() {
        withFloats.forEach { $0.store.markShown() }
    }
}
