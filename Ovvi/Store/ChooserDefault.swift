import AppKit
import HerdrKit

/// Settings ▸ General ▸ New panes open (ui/new-pane#a-fixed-pick): New Pane's chooser, or one of its rows that every
/// new pane picks at once.
extension Chooser {
    /// The defaults key: a row's id (`Row.id`: `terminal`, an agent's command, a plugin's id), empty for the chooser.
    static let opensKey = "newPaneOpens"

    /// The rows Settings offers: Terminal, every agent and every plugin with a chooser row, also one turned off in New
    /// Pane.
    static var fixedRows: [Row] {
        [.terminal] + agents.indices.map(Row.start) + Registry.all.filter { $0.chooser != nil }.map { .plugin($0.id) }
    }

    /// The setting's row (`fixedRow`).
    static var fixed: Row? {
        fixedRow(UserDefaults.standard.string(forKey: opensKey) ?? "")
    }

    /// The row of a setting's id; nil: the chooser, also for an id no row has now (a plugin removed since).
    static func fixedRow(_ id: String) -> Row? {
        id.isEmpty ? nil : fixedRows.first { $0.id == id }
    }

    /// ⌥ is down as the user makes a pane: it shows the chooser whatever the setting says. Read before any await, while
    /// the key or click that makes the pane is still held.
    static var asked: Bool {
        NSEvent.modifierFlags.contains(.option)
    }
}

extension HostStore {
    /// A new pane's chooser makes Settings' pick at once, so its list never shows; not for an agent the window's
    /// machine does not have: the chooser shows it dimmed. A plugin opens through the key window's page of this
    /// session, else any window's; with none, the chooser stays.
    func pickDefault(_ chooser: Chooser) {
        guard let row = Chooser.fixed else { return }
        let shown = WindowPages.windows.filter { $0.current?.store === self },
            page = (shown.first { $0.window?.isKeyWindow == true } ?? shown.first)?.current
        guard !Chooser.missing(row, page?.terminals.pages?.agents) else { return }
        pick(chooser, row, page: page)
    }
}

extension HostStore {
    /// Terminal's pick: the shell shows at once, and the chooser stays and holds the keys typed until the new terminal
    /// has the keyboard (herdr's pane, the snapshot that shows it, its focus), so none reaches the old card. Then the
    /// folder line's `cd`, and the held keys.
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
            // Not for a pane that closed meanwhile.
            if let command = chooser.cdCommand, let id = chooser.paneID, choosers.contains(where: { $0 === chooser }) {
                await write { try await $0.sendInput(command, keys: ["enter"], pane: id) }
            }
            release(chooser)
        }
    }

    /// The chooser goes. The keys it held go to its terminal when that has the keyboard (an agent's once it is ready),
    /// into the terminal's one queue of input in the order typed: named keys as the terminal sends them, the rest as
    /// their text (libghostty would send its text later than the keys). Else they are dropped with a beep.
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

    /// The chooser's terminal, when it has the key window's keyboard.
    private func keyboardTerminal(_ chooser: Chooser) -> PaneTerminal? {
        guard let id = chooser.paneID, let view = NSApp.keyWindow?.firstResponder as? PaneSurfaceView,
              view.terminal?.paneID == id, view.store() === self else { return nil }
        return view.terminal
    }
}

extension WindowPages {
    /// The window's one check for the agents on its machine (ui/new-pane#agent), in its login shell so its `PATH` and
    /// aliases count. Kept for the window's life: a new window sees an agent installed since. One that failed (a
    /// remote machine not connected yet, a shell that cannot run the loop) is asked again when the window connects.
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
