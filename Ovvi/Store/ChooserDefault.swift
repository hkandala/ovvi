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

    /// Named keys as the terminal sends them, the rest as their text: libghostty would send its text later than the
    /// keys.
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
                NSPasteboard.general.string(forType: .string).map { terminal.type("\u{1B}[200~" + $0 + "\u{1B}[201~") }
            } else if let text = event.characters,
                      // Not AppKit's function-key characters (Home, End, Page Up and Down, forward delete).
                      !text.unicodeScalars.contains(where: { (0xF700 ... 0xF8FF).contains($0.value) })
            {
                terminal.type(text)
            }
        }
    }

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
