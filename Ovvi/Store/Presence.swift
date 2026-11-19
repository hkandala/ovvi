import AppKit
import HerdrKit

extension HostStore {
    private static var quitting = false
    private static let refresh = Task { @MainActor in
        while await (try? Task.sleep(for: .seconds(10))) != nil {
            all.forEach { $0.markOpen(refresh: true) }
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
                page.zoomedPaneID.map { [$0] } ?? Array(page.shownTerminals.values)
            })
    }

    var floatingPanes: Set<String> {
        Set(windows.filter(\.visible).flatMap(\.withFloats).filter { $0.store === self }
            .flatMap { page in panes.filter(page.floats).map(\.id) })
    }

    /// The session's one open mark while a window of this app shows it: on its first space, as herdr keeps no
    /// metadata for a session. A mark lasts 30 s, so an app that crashed stops claiming the session. One write after
    /// the other, so a quick close and open cannot land out of order.
    func markOpen(refresh: Bool = false) {
        _ = (Self.refresh, Self.inputs, Self.input) // starts the lazy statics; the idle clock from the first page shown
        guard let client else { return }
        let open = Self.quitting || windows.isEmpty ? nil : workspaces.first?.id
        let old = openMarked
        guard open != old || refresh && open != nil else { return }
        openMarked = open
        // The new space first, so the session never shows none; none queued ahead of the quit.
        marking = Task { [marking] in
            await marking?.value
            if let open, !Self.quitting {
                try? await client.mark(workspace: open, open: true)
            }
            if let old, old != open {
                try? await client.mark(workspace: old, open: false)
            }
        }
    }

    /// At most 1 s. A tool that sees the mark after the quit would ask an app that is gone.
    static func unmarkAll() async {
        quitting = true
        all.forEach { $0.markOpen() }
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
    func markOpen() {
        withFloats.forEach { $0.store.markOpen() }
    }
}
