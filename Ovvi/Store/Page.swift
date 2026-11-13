import AppKit
import HerdrKit
import Observation

@MainActor @Observable
final class Page: Identifiable {
    let store: HostStore
    let terminals: PaneViewRegistry
    /// The app's own selection, never herdr's focus.
    var selectedWorkspaceID: String? {
        didSet {
            newest = selectedWorkspaceID == oldValue ? newest : nil
            leaving(oldValue.flatMap { selectedWorkspaceID != $0 ? selectedTabIDs[$0] : nil })
            // The space in view is never hidden.
            if store.onlyPinned, selectedWorkspaceID != oldValue {
                store.showStates()
            }
            went(from: oldValue.flatMap { selectedTabIDs[$0] })
        }
    }

    var selectedTabIDs: [String: String] = [:] {
        didSet {
            for (workspace, tab) in oldValue where selectedTabIDs[workspace] != tab {
                newest = nil
                leaving(workspace == selectedWorkspaceID ? tab : nil)
                usedTabIDs[workspace, default: []].removeAll { $0 == tab }
                usedTabIDs[workspace, default: []].append(tab)
            }
            went(from: selectedWorkspaceID.flatMap { oldValue[$0] })
        }
    }

    @ObservationIgnored private var usedTabIDs: [String: [String]] = [:]
    /// The tabs shown, across spaces, oldest first; Go Back and Go Forward move `place` along it.
    @ObservationIgnored private var history: [String] = []
    @ObservationIgnored private var place = -1
    @ObservationIgnored private var tabOrder: [String: [String]] = [:]
    /// Each tab's zoomed card: tab id to pane id.
    var zoomedPanes: [String: String] = [:]
    /// The selected tab's zoomed card.
    var zoomedPaneID: String? {
        selectedTab.flatMap { zoomedPanes[$0.id] }
    }

    /// The unpinned spaces' order the sidebar holds still while the pointer is over its list (Recent).
    var sortHold: [String]?
    var dragging: Dragged?
    var lifted: Dragged?
    var closing: HostStore.Closing?
    var floating: [String: Bool] = [:] {
        didSet {
            if floating.isEmpty, !oldValue.isEmpty {
                terminals.pages?.dropFloatOnly(self)
            }
        }
    }

    var renamingPaneID: String?
    var find: Find?
    var findFocus = 0
    /// Observed: the tab's icon stack puts the latest in front.
    private var usedTerminals: [String] = []
    /// Observed: its card is lit.
    var newest: (id: String, from: String?)?
    /// Read only with a `newest`.
    @ObservationIgnored var splitsBefore: [String] = []
    @ObservationIgnored var keyboardTabID: String?
    /// A write does not wait for its snapshot.
    @ObservationIgnored var movedTerminal: String?
    @ObservationIgnored private var arriving: String?

    let id: String

    init(store: HostStore, terminals: PaneViewRegistry) {
        self.store = store
        id = store.session
        self.terminals = terminals
    }

    var watched: Bool {
        store.windows.first.map { $0.terminals !== terminals } ?? false
    }

    var selectedWorkspace: HostStore.Workspace? {
        store.workspaces.first { $0.id == selectedWorkspaceID }
    }

    var selectedTab: HostStore.Tab? {
        selectedWorkspace.flatMap { workspace in workspace.tabs.first { $0.id == selectedTabIDs[workspace.id] } }
    }

    /// The tab first: the history never gets the space's old tab, which the switch never shows.
    func select(_ workspace: HostStore.Workspace, tab tabID: String? = nil) {
        arriving = nil
        if let tabID {
            selectedTabIDs[workspace.id] = tabID
        }
        selectedWorkspaceID = workspace.id
    }

    /// -1 back, 1 forward, past the tabs closed since.
    func goInHistory(_ offset: Int) {
        var index = place + offset
        while history.indices.contains(index) {
            let id = history[index]
            if id != selectedTab?.id, let workspace = store.workspace(of: id) {
                place = index
                return select(workspace, tab: id)
            }
            index += offset
        }
    }

    /// A step through the history lands on `place` and adds nothing.
    private func went(from old: String?) {
        guard let new = selectedWorkspaceID.flatMap({ selectedTabIDs[$0] }), new != old,
              place < 0 || history[place] != new else { return }
        // ponytail: the last 100 tabs, enough to step back through by key.
        history = Array(history.prefix(place + 1).suffix(99)) + [new]
        place = history.count - 1
    }

    func settle() {
        let arrived = store.ahead.arrived
        if !arrived.isEmpty {
            usedTabIDs = usedTabIDs.mapValues { $0.map { arrived[$0] ?? $0 } }
            history = history.map { arrived[$0] ?? $0 }
            // Only a change: each set notifies every observer of the selection.
            let selected = selectedTabIDs.mapValues { arrived[$0] ?? $0 }
            if selected != selectedTabIDs {
                selectedTabIDs = selected
            }
        }
        for workspace in store.workspaces {
            let ids = workspace.tabs.map(\.id)
            switch selectedTabIDs[workspace.id] {
            case let selected? where ids.contains(selected):
                break
            case let gone? where tabOrder[workspace.id] != nil:
                let left = tabOrder[workspace.id]?.prefix { $0 != gone }.last(where: ids.contains)
                selectedTabIDs[workspace.id] = usedTabIDs[workspace.id]?.last(where: ids.contains) ?? left
                    ?? ids.first
            default:
                selectedTabIDs[workspace.id] = ids.contains(workspace.activeTabID) ? workspace.activeTabID
                    : ids.first
            }
            usedTabIDs[workspace.id]?.removeAll { !ids.contains($0) }
        }
        tabOrder = Dictionary(store.workspaces.map { ($0.id, $0.tabs.map(\.id)) }, uniquingKeysWith: { $1 })
        // A pane that moves to another workspace has a new id.
        if let find, store.pane(find.paneID) == nil {
            self.find = nil
        }
        zoomReplaced()
        // Gone, alone in its tab, or moved to another tab, by any window or client.
        let zoomed = zoomedPanes.filter { tab, id in !alone(id) && store.pane(id)?.tabID == tab }
        if zoomed != zoomedPanes {
            zoomedPanes = zoomed
        }
        if let id = arriving, let workspace = store.workspace(of: id) {
            select(workspace, tab: id)
        }
        if selectedWorkspace == nil {
            selectedWorkspaceID = store.workspaces.contains { $0.id == store.focusedWorkspaceID }
                ? store.focusedWorkspaceID : store.workspaces.first?.id
        }
    }

    var keyboardPane: HostStore.Pane? {
        if let zoomed = zoomedPaneID.flatMap(store.pane) {
            return zoomed
        }
        if let pane = newest.flatMap({ store.pane($0.id) }), pane.tabID == selectedTab?.id {
            return pane
        }
        // Not another tab's: its view keeps the keyboard until the shown tab's terminal takes it, and ⌘W would close
        // that tab's pane.
        if let id = terminals.keyboardTerminalID, let pane = store.terminalPane(id),
           pane.tabID == selectedTab?.id
        {
            return pane
        }
        return keyboardCard(selectedTab?.id)
    }

    /// Observed, unlike the first responder.
    func keyboardCard(_ tabID: String?) -> HostStore.Pane? {
        let panes = store.panes(in: tabID).filter { !floats($0) }
        let pane = usedTerminals.reversed().lazy.compactMap { id in panes.first { $0.terminalID == id } }.first
        return pane ?? panes.first(where: \.focused)
    }

    var shownTerminals: [String: String] {
        Dictionary(store.panes.compactMap { pane in
            pane.tabID == selectedTab?.id || floats(pane) ? pane.terminalID.map { ($0, pane.id) } : nil
        }, uniquingKeysWith: { first, _ in first })
    }

    func terminal(_ pane: HostStore.Pane) -> PaneTerminal? {
        guard let terminalID = pane.terminalID, let client = store.client, pane.plugin == nil || pane.placeholder
        else { return nil }
        return terminals.terminal(terminalID, pane: pane.id, client: client)
    }

    func tookKeyboard(_ terminalID: String) {
        if terminalID != newest?.from {
            newest = nil
        }
        if let pane = store.terminalPane(terminalID), !floats(pane) {
            use(terminalID)
        }
    }

    func shown(alive: Set<String>) {
        // Only what is alive at the last call: a split's new terminal joins the history ahead of a snapshot with it.
        let gone = self.alive.subtracting(alive)
        self.alive = alive
        let closed = usedTerminals.last.map(gone.contains) ?? false
        // Assigned, not edited in place: Observation skips an equal value, and removeAll notifies at each snapshot.
        usedTerminals = usedTerminals.filter { !gone.contains($0) }
        if closed || selectedTab?.id != keyboardTabID {
            focusKeyboardCard()
        }
    }

    @ObservationIgnored private var alive: Set<String> = []

    func use(_ terminalID: String) {
        usedTerminals.removeAll { $0 == terminalID }
        usedTerminals.append(terminalID)
    }

    func focusKeyboardCard() {
        guard let tab = selectedTab else { return }
        let tabPanes = store.panes(in: tab.id).filter { $0.terminalID != nil && !floats($0) }
        // Giving the keyboard to another card ahead of the snapshot would record that card as the tab's keyboard
        // card (`tookKeyboard`) for good.
        if let moved = movedTerminal, usedTerminals.last == moved {
            guard tabPanes.contains(where: { $0.terminalID == moved }) else { return }
            movedTerminal = nil
        }
        let pane = keyboardCard(tab.id) ?? tabPanes.first
        if let pane, let terminalID = pane.terminalID {
            keyboardTabID = tab.id
            // Made here if its card has not drawn yet: it takes the keyboard once it is in the window.
            _ = (terminal(pane), browser(pane), plugin(pane))
            terminals.focus(terminalID)
        }
    }

    func go(to pane: HostStore.Pane) {
        guard !floats(pane) else { return float(pane) }
        guard let workspace = store.workspace(of: pane.tabID) else { return }
        newest = nil
        select(workspace, tab: pane.tabID)
        if zoomedPanes[pane.tabID].map({ $0 != pane.id }) == true {
            zoomedPanes[pane.tabID] = nil
        }
        if let terminalID = pane.terminalID {
            use(terminalID)
        }
        focusKeyboardCard()
    }

    func step(_ offset: Int) {
        guard let workspace = selectedWorkspace, !workspace.tabs.isEmpty else { return }
        selectedTabIDs[workspace.id] = workspace.tabs.step(from: selectedIndex(in: workspace), by: offset)?.id
    }

    var sidebarWorkspaces: [HostStore.Workspace] {
        sidebarGroups.flatMap(\.self)
    }

    func stepWorkspace(_ offset: Int) {
        let workspaces = sidebarWorkspaces
        guard let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }),
              let workspace = workspaces.step(from: index, by: offset) else { return }
        select(workspace)
    }

    func stepCard(_ offset: Int) {
        guard let ids = selectedTab?.tree?.paneIDs.filter({ store.pane($0).map { !floats($0) } == true }),
              let from = keyboardPane,
              let index = ids.firstIndex(of: from.id),
              let pane = ids.step(from: index, by: offset).flatMap(store.pane) else { return }
        go(to: pane)
    }

    func zoom(_ paneID: String) {
        guard canZoom(paneID), let pane = store.pane(paneID) else { return }
        let zoomed = zoomedPanes[pane.tabID] != paneID
        zoomedPanes[pane.tabID] = zoomed ? paneID : nil
        if findHidden {
            dropFind()
        }
        if zoomed, let terminalID = pane.terminalID {
            terminals.focus(terminalID)
        }
    }

    func canZoom(_ paneID: String) -> Bool {
        zoomed(paneID) || !alone(paneID)
    }

    private func alone(_ paneID: String) -> Bool {
        let tab = store.pane(paneID)?.tabID
        return store.panes(in: tab).count < 2
    }

    @ObservationIgnored var asking: Set<String> = []
}

extension Page {
    func zoomed(_ paneID: String) -> Bool {
        zoomedPanes.values.contains(paneID)
    }

    /// From the tree: herdr's `pane.neighbor` waits on herdr and picks another.
    func moveKeyboard(_ heading: Heading) {
        let used = usedTerminals.compactMap { store.terminalPane($0)?.id }
        guard let from = keyboardPane, let id = selectedTab?.tree?.neighbor(of: from.id, heading, used: used),
              let pane = store.pane(id) else { return }
        go(to: pane)
    }

    func move(_ pane: HostStore.Pane, to destination: Destination) async {
        let terminalID = pane.terminalID
        await follow(store.move(pane.id, to: destination), terminalID)
    }

    func follow(_ moved: HerdrKit.Pane?, _ terminalID: String?, select: Bool = true) {
        guard let moved, floating[terminalID ?? ""] == nil else { return }
        if let terminalID {
            use(terminalID)
        }
        movedTerminal = terminalID
        arriving = select ? moved.tabID : arriving
        // Not hidden under the zoom of the tab it came to.
        if select, zoomedPanes[moved.tabID].map({ $0 != moved.id }) == true {
            zoomedPanes[moved.tabID] = nil
        }
        settle() // The snapshot after the move may have come in during the await.
        keyboardTabID = nil
        if moved.tabID == selectedTab?.id {
            focusKeyboardCard()
        }
    }

    /// Only on a live page: a stopped or reconnecting session's write can only fail.
    func newTab(in workspace: HostStore.Workspace? = nil) async {
        guard store.state == .live, let workspace = workspace ?? selectedWorkspace else { return }
        let tabs = [selectedTabIDs[workspace.id]] + (usedTabIDs[workspace.id] ?? []).reversed()
        let pane = (workspace.id == selectedWorkspaceID ? keyboardPane : nil)
            ?? tabs.lazy.compactMap { self.keyboardCard($0) }.first
        let standIn = store.standIn(in: workspace.id)
        let chooser = store.choose(standIn: standIn, cwd: pane?.cwd)
        select(workspace, tab: standIn)
        guard let made = await store.newTab(in: workspace.id, cwd: pane?.cwd, of: pane?.id) else {
            store.dropStandIn(standIn)
            store.drop(chooser)
            return
        }
        chooser.made(made)
        store.madeTab(standIn, made.tabID)
    }

    /// herdr reads `~` as the machine's home: a server launchd starts has another cwd.
    @discardableResult
    func newWorkspace(label: String? = nil, cwd: String = "~", fixed: Bool = true) async -> HerdrKit.Pane? {
        let pane = await store.newWorkspace(label: label, cwd: cwd, fixed: fixed)
        arriving = pane?.tabID ?? arriving
        return pane
    }
}

extension Page {
    func selectedIndex(in workspace: HostStore.Workspace) -> Int {
        workspace.tabs.firstIndex { $0.id == selectedTabIDs[workspace.id] } ?? 0
    }

    /// Ahead of SwiftUI hiding the kept page, which leaves the chats no picture to give.
    func leaving(_ tabID: String?) {
        for id in store.panes(in: tabID).compactMap(\.terminalID) {
            if let picture = terminals.chatViews[id]?() {
                terminals.keep(id, picture)
            }
        }
    }
}
