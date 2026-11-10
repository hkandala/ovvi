import AppKit
import GhosttyTerminal
import HerdrKit
import Observation

@MainActor @Observable
final class PaneTerminal {
    private(set) var state = State.idle
    var hasKeyboard = false
    /// Off from a new surface's start and from each grid change until the grid settles, so that herdr's first frame
    /// (the last screen reflowed at the new size) never shows.
    var ready = false
    var snapshot: IOSurface?
    @ObservationIgnored var revealed = false
    @ObservationIgnored var settling: Task<Void, Never>?
    @ObservationIgnored var deadline: Task<Void, Never>?
    @ObservationIgnored private(set) var grid: InMemoryTerminalViewport?
    /// `grid` takes it in `resized`'s task, which a task for a stale grid must not replace.
    @ObservationIgnored private var latest: InMemoryTerminalViewport?
    @ObservationIgnored let view = PaneSurfaceView(frame: .zero)
    @ObservationIgnored var paneID: String
    @ObservationIgnored private let terminalID: String
    @ObservationIgnored private let client: any Multiplexer
    @ObservationIgnored private let session: InMemoryTerminalSession
    @ObservationIgnored private var pending: [Input] = []
    @ObservationIgnored private var draining: Task<Void, Never>?
    @ObservationIgnored private var paste: String?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var resizing: Task<Void, Never>?
    @ObservationIgnored var redrawing: Task<Void, Never>?
    @ObservationIgnored private(set) var lastFrame = ContinuousClock.now
    @ObservationIgnored private var stream: TerminalStream?
    @ObservationIgnored private(set) var observing = false
    @ObservationIgnored private var shown = false
    @ObservationIgnored private var retried: ContinuousClock.Instant?
    /// Counts streams, so a stream that is ending cannot change the state of the next one.
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored var watches: () -> Bool = { false }
    @ObservationIgnored var onInput: () -> Void = {}
    @ObservationIgnored var onFrame: (() -> Void)?
    @ObservationIgnored var inView = false {
        didSet {
            if inView != oldValue {
                inViewChanged()
            }
        }
    }

    init(terminalID: String, paneID: String, client: any Multiplexer) {
        self.terminalID = terminalID
        self.paneID = paneID
        self.client = client
        // libghostty writes on its own IO thread; a stream keeps the order.
        let (texts, text) = AsyncStream<String>.makeStream()
        let (sizes, size) = AsyncStream<InMemoryTerminalViewport>.makeStream()
        session = InMemoryTerminalSession(
            write: { text.yield(String(decoding: $0, as: UTF8.self)) },
            resize: { size.yield($0) },
            suppressesPixelOnlyResizes: true,
        )
        // Pastes leave libghostty framed, and herdr frames them again for the app's own mode. No cursor on the
        // empty surface ahead of herdr's first frame, which says whether it shows.
        session.receive(Self.modes)
        view.terminal = self
        // No surface until it streams (`show`): a card that never does costs no GPU memory.
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        tasks = [
            Task { for await text in texts {
                enqueue(.text(text))
            } },
            Task { for await size in sizes {
                resized(size)
            } },
        ]
    }

    /// The registry calls it on every snapshot: a failed stream opens again at most every 5 s, and only while herdr
    /// answers the page.
    func show() {
        guard shown else {
            shown = true
            view.rebuild()
            return open()
        }
        guard state.isFailed else { return }
        guard live else { return retried = nil }
        if retried.map({ .now - $0 >= .seconds(5) }) ?? true {
            retried = .now
            open()
        }
    }

    func pause() {
        guard shown else { return }
        shown = false
        pending = []
        paste = nil
        end()
    }

    func hide() {
        pause()
        view.free()
        // For the next surface: libghostty keeps what it receives meanwhile.
        session.receive(Self.modes)
    }

    func close() {
        hide()
        tasks.forEach { $0.cancel() }
    }

    func takeBack() {
        open(takeover: true)
    }

    func control(_ controls: Bool) {
        guard shown, observing == controls else { return }
        guard inView else { return pause() }
        // Keys this window had not sent yet do not go out at a later takeover.
        if !controls {
            pending = []
            paste = nil
        }
        open(observe: !controls, takeover: controls)
    }

    // MARK: Stream

    private func open(observe: Bool = false, takeover: Bool = false) {
        guard shown, let grid else { return }
        end()
        observing = observe || !takeover && watches()
        let generation = generation
        let previous = run
        run = Task {
            // The last stream ends first, so herdr never sees two of ours on one pane.
            await previous?.value
            guard generation == self.generation else { return }
            let stream: TerminalStream
            do {
                stream = try await client.terminal(terminalID, cols: Int(grid.columns), rows: Int(grid.rows),
                                                   observe: observing, takeover: takeover)
            } catch {
                if generation == self.generation {
                    state = .failed(error.localizedDescription)
                }
                return
            }
            // Ended while it opened: close it too; the loop below drains it until herdr exits.
            if generation == self.generation {
                self.stream = stream
            } else {
                stream.close()
            }
            for await event in stream.events where generation == self.generation {
                switch event {
                case let .frame(frame):
                    if state == .idle || state.isFailed {
                        started(frame)
                    }
                    // Ahead of libghostty's frame: drawing pauses.
                    if !ready {
                        settle()
                    }
                    session.receive(frame.bytes)
                    lastFrame = .now
                    onFrame?()
                case let .closed(reason):
                    self.stream = nil
                    closed(reason)
                }
            }
        }
    }

    private func started(_ frame: TerminalStream.Frame) {
        state = observing ? .watching : .live
        // The card may have changed size while the stream opened. Its latest size: a new surface's first guess (100×40
        // at 1x) may be `grid` while the real size waits in `resized`, and that one would be cancelled.
        if let latest, frame.width != latest.columns || frame.height != latest.rows {
            resized(latest)
        }
        drain()
    }

    /// The run goes on until herdr exits, so that the next `open` waits for the pane to be free; a stream still
    /// opening closes itself once open.
    private func end() {
        generation += 1
        stream?.close()
        stream = nil
        // A failed card keeps its panel while it opens again.
        if !state.isFailed {
            state = .idle
        }
    }

    private func closed(_ reason: TerminalStream.Closed) {
        // No frame yet: herdr refused the stream at open.
        let refused = state == .idle || state.isFailed
        state = .idle
        switch reason {
        case .held:
            // Takes over only if the user typed while a refused control opened. A new task: `open` waits for this
            // run to end.
            let takeover = refused && !pending.isEmpty
            if !takeover {
                pending = []
            }
            // Not when control moved between windows meanwhile (`control`).
            Task { [generation] in
                if generation == self.generation {
                    open(observe: !takeover, takeover: takeover)
                }
            }
        case .liveUpdate:
            Task { [generation, observing] in
                try? await Task.sleep(for: .seconds(1))
                if generation == self.generation {
                    open(observe: observing)
                }
            }
        case .ended:
            pending = []
        case let .failed(text):
            pending = []
            state = .failed(text)
        }
    }

    // MARK: Size and input

    /// The first grid waits for the layout to settle, so that the first stream opens at the card's real size, not at
    /// the surface's first guess (50×17), which makes an agent redraw twice. Later ones go at once: the host waits
    /// for the card's size to settle.
    private func resized(_ size: InMemoryTerminalViewport) {
        latest = size
        resizing?.cancel()
        resizing = Task {
            let first = grid == nil
            if first {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            grid = size
            if first {
                open()
            } else if state == .watching {
                // observe cannot resize: watch again at the new size.
                open(observe: true)
            } else if state == .live {
                resize(columns: Int(size.columns), rows: Int(size.rows))
            }
        }
    }

    /// libghostty writes a paste in pieces (start mark, text, end mark); herdr frames it for the
    /// app's paste mode only when one write is the whole `ESC[200~…ESC[201~`.
    private func enqueue(_ input: Input) {
        if case let .text(text) = input, paste != nil || text.hasPrefix("\u{1B}[200~") {
            let whole = (paste ?? "") + text
            paste = whole
            if let end = whole.range(of: "\u{1B}[201~") {
                paste = nil
                queue(.text(String(whole[..<end.upperBound])))
                if end.upperBound < whole.endIndex {
                    queue(.text(String(whole[end.upperBound...])))
                }
            }
        } else {
            queue(input)
        }
    }

    /// A bridge call takes about 60 ms, more than a held key's repeat, so keys that pile up
    /// meanwhile go as one call; text stays one write per piece, so a paste stays whole.
    /// ponytail: keys (main thread) and libghostty's text (its IO thread) are ordered only as
    /// they arrive here, microseconds apart; enough for typing.
    private func queue(_ input: Input) {
        guard !state.isFailed else { return }
        if case let (.keys(old)?, .keys(new)) = (pending.last, input) {
            pending[pending.count - 1] = .keys(old + new)
        } else {
            pending.append(input)
        }
        onInput()
        if state == .watching {
            takeBack()
        }
        drain()
    }

    /// One at a time: a key waits for herdr's answer, then the next text goes out.
    private func drain() {
        guard draining == nil else { return }
        draining = Task {
            while state == .live, let stream, !pending.isEmpty {
                switch pending.removeFirst() {
                case let .text(text):
                    stream.input(text)
                case let .keys(keys):
                    try? await client.sendKeys(keys, pane: paneID)
                }
            }
            draining = nil
        }
    }
}

extension PaneTerminal {
    func resize(columns: Int, rows: Int) {
        stream?.resize(cols: columns, rows: rows, cellWidth: Int(view.metrics?.cellWidthPixels ?? 0),
                       cellHeight: Int(view.metrics?.cellHeightPixels ?? 0))
    }

    func keys(_ keys: [String]) {
        enqueue(.keys(keys))
    }

    func type(_ text: String) {
        enqueue(.text(text))
    }

    func retry() {
        open()
    }

    var live: Bool {
        view.store()?.state == .live
    }

    func mouse(_ action: TerminalStream.MouseAction, _ button: TerminalStream.MouseButton,
               column: Int, row: Int, modifiers: Int)
    {
        if action == .down {
            onInput()
        }
        if state == .watching, action == .down {
            takeBack()
        } else if state == .live {
            stream?.mouse(action, button, column: column, row: row, modifiers: modifiers)
        }
    }

    func scroll(lines: Int, column: Int, row: Int, modifiers: Int) {
        if state == .live {
            stream?.scroll(lines: lines, column: column, row: row, modifiers: modifiers)
        }
    }

    enum State: Equatable {
        case idle
        case live
        case watching
        case failed(String)

        var isFailed: Bool {
            guard case .failed = self else { return false }
            return true
        }
    }

    enum Input {
        case text(String)
        case keys([String])
    }
}
