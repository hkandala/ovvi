import AppKit
import HerdrKit
import SwiftUI

@MainActor @Observable
final class WindowPages {
    var machine = Machine.thisMac
    private(set) var list: [Page] = []
    /// No selection, so a float never gives their cards the keyboard. ponytail: not saved.
    var floatOnly: [Page] = []
    @ObservationIgnored var floatPending: (page: Page, pane: String)?
    @ObservationIgnored var floatPendingForAgent = false
    var question: Question?
    private(set) var current: Page?
    let terminals = PaneViewRegistry()
    var agents: Set<String>?
    var visible = false
    var overview = false
    @ObservationIgnored var overviewTabs: [String: [String]] = [:]
    @ObservationIgnored var overviewSettling: Task<Void, Never>?
    private(set) var overviewLive: Set<String> = []
    @ObservationIgnored var tileScale = tile
    static let tile: CGFloat = 0.35
    @ObservationIgnored var overviewScrolling = false
    @ObservationIgnored var panelOpen = false
    @ObservationIgnored private var key = false
    @ObservationIgnored private var pending: String?
    @ObservationIgnored weak var window: NSWindow?

    /// The last key one first; added once its pages restore: SwiftUI makes a `@State` per view.
    static var windows: [WindowPages] = []
    @ObservationIgnored private var gone = false
    private static var folders: [URL] = []
    /// From the menu bar's commands: they exist with no window.
    static var openWindow: OpenWindowAction?
    static let mainScene = "main", floatScene = "float", aboutScene = "about", settingsScene = "settings"

    init() {
        terminals.pages = self
    }

    func returned(_ terminalID: String) {
        guard let page = current, let pane = page.store.terminalPane(terminalID)
        else { return }
        let store = page.store
        if page.find?.paneID == pane.id {
            page.find?.stale = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            await store.askProgram(pane.id, soon: true)
        }
    }

    func input(_ terminalID: String) {
        if let store = page(of: terminalID)?.store, store.windows.first !== self {
            control(store)
        }
    }

    func opened() {
        if !Self.windows.contains(where: { $0 === self }) {
            Self.windows.append(self)
        }
        findAgents()
        Self.runEarly()
    }

    func open(_ session: String, start: Bool = false) {
        // A late open (a start that finishes, a restore) after the window closes.
        guard !gone else { return }
        if let page = list.first(where: { $0.id == session }) {
            show(page)
            return
        }
        let page = floatOnly.firstIndex { $0.id == session }.map { floatOnly.remove(at: $0) } ?? {
            let store = HostStore.named(session, on: machine, start: start)
            store.windows.append(self)
            return Page(store: store, terminals: terminals)
        }()
        page.settle()
        list.append(page)
        show(page)
    }

    func show(_ page: Page) {
        if page !== current {
            page.keyboardTabID = nil
        }
        current = page
        showTerminals()
    }

    func neighbor(_ offset: Int) -> Page? {
        list.firstIndex { $0 === current }.map { $0 + offset }
            .flatMap { list.indices.contains($0) ? list[$0] : nil }
    }

    func step(_ offset: Int) {
        if let page = neighbor(offset) {
            show(page)
        }
    }

    func page(_ store: HostStore) -> Page? {
        list.first { $0.store === store }
    }

    func page(of terminalID: String) -> Page? {
        withFloats.first { $0.store.panes.contains { $0.terminalID == terminalID } }
    }

    func snapshotted(_ store: HostStore) {
        page(store)?.settle()
        if let page = withFloats.first(where: { $0.store === store }), store.state == .live {
            // herdr's panes, not the shown ones: a close shown at once may still come back (`Ahead`).
            let alive = page.floating.filter { id, _ in store.last?.panes.contains { $0.terminalID == id } ?? true }
            if alive.count < page.floating.count {
                page.floating = alive
            }
        }
        showTerminals(snapshot: true)
        showPending()
        showFloatPending()
        if Self.windows.first === self {
            openFolders()
        }
    }

    static func open(folders urls: [URL]) {
        folders += urls
        windows.first?.openFolders()
    }

    private func openFolders() {
        // ponytail: a Mac folder means nothing to a remote machine; they wait for a page of This Mac.
        guard let page = current, page.store.state == .live, !page.store.machine.isRemote, !Self.folders.isEmpty
        else { return }
        let urls = Self.folders
        Self.folders = []
        Task {
            for url in urls {
                await page.newWorkspace(cwd: url.path(percentEncoded: false))
            }
        }
    }

    var canDetach: Bool {
        list.count > 1
    }

    func close(_ page: Page) {
        guard canDetach, let index = list.firstIndex(where: { $0 === page }) else { return }
        page.dropFind()
        page.floating = [:]
        list.remove(at: index)
        if current === page {
            show(list[max(index - 1, 0)])
        }
        showTerminals()
        leave(page.store)
    }

    func closed() {
        gone = true
        Self.windows.removeAll { $0 === self }
        leaveAll()
        question?.answer(nil)
    }

    static func open(machine: Machine?, connect: Bool = false) {
        opening = openWindow == nil ? nil : (machine, connect)
        openWindow?(id: mainScene)
    }

    /// ponytail: one; a queue if two quick opens ever clash.
    static var opening: (machine: Machine?, connect: Bool)?

    private func leaveAll() {
        let pages = withFloats
        floatOnly = []
        for item in pages {
            item.dropFind()
            item.floating = [:]
        }
        terminals.show([:], web: [], alive: [], client: nil)
        pages.forEach { leave($0.store) }
        list = []
        // Its content goes too: nothing of the window may stream again.
        current = nil
    }

    func ask(_ text: String) async -> String? {
        question?.answer(nil)
        let id = UUID()
        return await withCheckedContinuation { continuation in
            // Once: a second click, or a late answer to a question a newer one replaces, does nothing.
            question = Question(id: id, text: text) { [weak self] answer in
                guard self?.question?.id == id else { return }
                self?.question = nil
                continuation.resume(returning: answer)
            }
        }
    }

    struct Question: Identifiable {
        let id: UUID
        let text: String
        /// Called once.
        let answer: (String?) -> Void
    }

    func leave(_ store: HostStore) {
        let controlled = store.windows.first === self
        store.windows.removeAll { $0 === self }
        store.markShown()
        // Unless another key window that shows the store sets them first.
        if key, !store.windows.contains(where: \.key) {
            store.lookingTabID = nil
        }
        if store.windows.isEmpty {
            Notifications.remove(store.panes, of: store)
            store.disconnect()
            HostStore.showBadge()
        } else if controlled {
            store.windows[0].control(store)
        }
    }

    func control(_ store: HostStore) {
        store.windows.removeAll { $0 === self }
        store.windows.insert(self, at: 0)
        let ids = Set(store.panes.compactMap(\.terminalID))
        for window in store.windows {
            window.terminals.terminals(ids).forEach { $0.control(window === self) }
        }
    }

    /// A window that stops being key leaves alone a store another window shows while key: the two calls come in
    /// either order.
    func look(key: Bool) {
        self.key = key
        if key {
            Self.windows.removeAll { $0 === self }
            Self.windows.insert(self, at: 0)
        }
        for page in list where key || !page.store.windows.contains(where: \.key) {
            let tabID = key && page === current ? page.selectedTab?.id : nil
            page.store.lookingTabID = tabID
            if let tabID {
                Notifications.remove(page.store.panes(in: tabID), of: page.store)
            }
        }
    }

    /// By the terminal: it outlives a pane id that changes.
    /// ponytail: switch the front window to the machine when such a click is missed.
    static func go(to id: String) {
        let parts = Notifications.parts(id)
        let machines = windows.filter { $0.machine.id == parts.first }
        guard let window = machines.first(where: { $0.list.contains { $0.id == parts.dropFirst().first } })
            ?? machines.first
        else {
            if windows.isEmpty, parts.count == 3 {
                ask(parts[0], parts[1]) { go(to: id) }
            }
            return
        }
        window.window?.makeKeyAndOrderFront(nil)
        window.pending = id
        window.showPending()
    }

    /// A snapshot hands the keyboard to a card only while no text field has it: typing in the palette or a rename
    /// field must not go on because a pane closed.
    func showTerminals(snapshot: Bool = false) {
        guard let current else { return }
        // A find bar whose card is out of view closes: herdr's viewport is shared, it must not stay scrolled. A
        // floated pane's stays in view.
        for page in withFloats where page.findHidden || page !== current
            && page.store.pane(page.find?.paneID ?? "").map(page.floats) != true
        {
            page.dropFind()
        }
        let alive = Set(withFloats.flatMap { $0.store.panes.compactMap(\.terminalID) })
        var shown = current.shownTerminals
        for page in withFloats where page !== current {
            for pane in page.store.panes where page.floats(pane) {
                if let id = pane.terminalID, page.terminal(pane) != nil {
                    shown[id] = pane.id
                }
            }
        }
        let unvisited = overview ? overviewStreams(current, snapshot: snapshot) : [:]
        overviewLive = overview ? Set(unvisited.keys).union(shown.keys) : []
        // herdr's, for the terminals: a close shown at once may come back (`Ahead`) with its picture.
        let kept = alive.union(withFloats.flatMap { ($0.store.last?.panes ?? []).compactMap(\.terminalID) })
        terminals.show(shown, web: webInView, unvisited: unvisited, alive: kept, client: current.store.client)
        if !overview, !panelOpen, !snapshot || !(window?.firstResponder is NSText) {
            current.shown(alive: alive)
        }
        markShown()
    }
}

extension WindowPages {
    func showPending() {
        guard let id = pending else { return }
        let parts = Notifications.parts(id)
        guard parts.count == 3 else {
            pending = nil
            return
        }
        guard let page = list.first(where: { $0.id == parts[1] }) else {
            open(parts[1])
            return
        }
        guard let pane = page.store.panes.first(where: { ($0.terminalID ?? $0.id) == parts[2] }) else {
            pending = page.store.state == .connecting ? id : nil
            return
        }
        pending = nil
        if overview {
            closeOverview()
        }
        show(page)
        page.go(to: pane)
    }
}

extension HostStore {
    func snapshotted(_ changes: [Seen.Change]) {
        for window in windows {
            // Ahead of its float windows closing: a replaced floated pane's new pane floats.
            window.withFloats.first { $0.store === self }?.floatReplaced()
            window.snapshotted(self)
        }
        if let page = windows.lazy.compactMap({ $0.page(self) }).first {
            Notifications.post(changes, page)
        }
    }
}

extension WindowPages {
    static var early: (() -> Void)?
    static var asked: (machine: String, session: String)?
    static var takeAsked: (() -> Void)?

    static func ask(_ machine: String, _ session: String, then click: @escaping () -> Void) {
        early = click
        asked = (machine, session)
        takeAsked?()
    }

    /// The new window whose Add Machine opened Settings.
    weak static var adding: WindowPages?

    /// A machine just added connects in the new window it came from while that one stays open and empty.
    static func added(_ machine: Machine) {
        guard let pages = adding, !pages.gone, pages.list.isEmpty else { return open(machine: machine, connect: true) }
        adding = nil
        pages.machine = machine
        pages.open(SessionPicker.throwaway ?? Session.defaultName)
        pages.opened()
        pages.window?.makeKeyAndOrderFront(nil)
        if let store = pages.current?.store {
            Task { await store.connect(in: pages) }
        }
    }

    static func runEarly() {
        guard let early else { return }
        self.early = nil
        asked = nil
        early()
    }
}

extension NSWindow {
    var panelOpen: Bool {
        WindowPages.windows.first { $0.window === self }?.panelOpen == true
    }
}
