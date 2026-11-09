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
        guard let row = Chooser.fixedRow(UserDefaults.standard.string(forKey: Chooser.opensKey) ?? "") else { return }
        let shown = WindowPages.windows.filter { $0.current?.store === self },
            page = (shown.first { $0.window?.isKeyWindow == true } ?? shown.first)?.current
        guard !Chooser.missing(row, page?.terminals.pages?.agents) else { return }
        pick(chooser, row, page: page)
    }
}
