import AppKit
import HerdrKit

extension Chooser {
    static var fixedRows: [Row] {
        [.terminal] + agents.indices.map(Row.start) + Registry.all.filter { $0.chooser != nil }.map { .plugin($0.id) }
    }

    static var fixed: Row? {
        fixedRow(AppSettings().newPaneOpens)
    }

    static func fixedRow(_ id: String) -> Row? {
        id.isEmpty ? nil : fixedRows.first { $0.id == id }
    }

    /// Read ahead of any await, while the key or click that makes the pane is still held.
    static var asked: Bool {
        NSEvent.modifierFlags.contains(.option)
    }
}

extension HostStore {
    func pickDefault(_ chooser: Chooser) {
        guard let row = Chooser.fixed else { return }
        let shown = WindowPages.windows.filter { $0.current?.store === self },
            page = (shown.first { $0.window?.isKeyWindow == true } ?? shown.first)?.current
        guard !Chooser.missing(row, page?.terminals.pages?.agents) else { return }
        pick(chooser, row, page: page)
    }
}

extension HostStore {
    func hold(_ chooser: Chooser) {
        chooser.holding = true
        Task {
            // ponytail: polled every 50 ms for up to 10 s; a callback from the focus if the wait ever shows.
            let clock = ContinuousClock(), begun = clock.now
            while keyboardTerminal(chooser) == nil, clock.now - begun < .seconds(10),
                  choosers.contains(where: { $0 === chooser })
            {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if let command = chooser.cdCommand, let id = chooser.paneID, choosers.contains(where: { $0 === chooser }) {
                await write { try await $0.sendInput(command, keys: ["enter"], pane: id) }
            }
            release(chooser)
        }
    }

    /// All as herdr's keys, characters too, in order: text goes by the terminal's stream and keys by herdr's API, so
    /// a key sent right after text could pass it (CI: arrows held after a typed line landed on the empty prompt).
    func release(_ chooser: Chooser) {
        drop(chooser)
        let held = chooser.held
        chooser.held = []
        guard !held.isEmpty else { return }
        guard let terminal = keyboardTerminal(chooser) else { return NSSound.beep() }
        for event in held {
            if let key = PaneSurfaceView.herdrKey(event) {
                terminal.keys([key])
            } else if event.modifierFlags.contains(.command) {
                // ⌘V, framed as libghostty frames a paste; herdr pastes it.
                // ponytail: by the stream, so a key held after it can pass it; an awaited paste if that shows.
                NSPasteboard.general.string(forType: .string).map { terminal.type("\u{1B}[200~" + $0 + "\u{1B}[201~") }
            } else if let text = event.characters,
                      // Not AppKit's function-key characters (Home, End, Page Up and Down, forward delete).
                      !text.unicodeScalars.contains(where: { (0xF700 ... 0xF8FF).contains($0.value) })
            {
                // herdr refuses a name of several scalars, and the whole call with it.
                terminal.keys(text.unicodeScalars.map { Self.named[$0] ?? String($0) })
            }
        }
    }

    /// herdr takes any one character as a key but these (the keypad's Enter is ETX).
    private static let named: [Unicode.Scalar: String] = [
        " ": "space", "\r": "enter", "\u{3}": "enter", "\t": "tab", "\u{7F}": "backspace",
    ]

    private func keyboardTerminal(_ chooser: Chooser) -> PaneTerminal? {
        guard let id = chooser.paneID, let view = NSApp.keyWindow?.firstResponder as? PaneSurfaceView,
              view.terminal?.paneID == id, view.store() === self else { return nil }
        return view.terminal
    }
}

extension WindowPages {
    /// In the login shell, so its `PATH` and aliases count.
    func findAgents() {
        guard agents == nil else { return }
        let commands = Chooser.agents.map(\.command)
        // The first `echo`: a startup file's text with no final newline would join the first agent's line. The end
        // marker: a shell that ran the loop.
        let script = "echo; for c in \(commands.joined(separator: " ")); do command -v $c >/dev/null && echo $c; done; "
            + "echo ovvi-end"
        Task {
            let lines = try? await machine.exec().output(["sh", "-c", #"exec "${SHELL:-sh}" -ilc "$1""#, "sh",
                                                          script], timeout: .seconds(3))
                .split(separator: "\n").map(String.init)
            if let lines, lines.last == "ovvi-end" {
                agents = Set(lines).intersection(commands)
            }
        }
    }
}
