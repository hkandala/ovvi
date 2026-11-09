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

    /// The row a new pane picks; nil: the chooser, also for an id no row has now (a plugin removed since).
    static var fixed: Row? {
        let id = UserDefaults.standard.string(forKey: opensKey) ?? ""
        return id.isEmpty ? nil : fixedRows.first { $0.id == id }
    }
}

extension HostStore {
    /// A new pane's chooser makes Settings' pick at once, so its list never shows. Not while ⌥ is down (the way to the
    /// chooser), nor for an agent the window's machine does not have: the chooser shows it dimmed. A plugin opens
    /// through the key window's page of this session, else any window's.
    func pickDefault(_ chooser: Chooser) {
        // ponytail: ⌥ is read as the pane is made, a moment after the key or click (a task later); read it from the
        // event if a quick ⌥ release ever loses it.
        guard let row = Chooser.fixed, !NSEvent.modifierFlags.contains(.option) else { return }
        let shown = WindowPages.windows.filter { $0.current?.store === self },
            page = (shown.first { $0.window?.isKeyWindow == true } ?? shown.first)?.current
        guard !Chooser.missing(row, page?.terminals.pages?.agents) else { return }
        pick(chooser, row, page: page)
    }
}
