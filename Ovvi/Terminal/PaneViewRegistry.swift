import AppKit
import GhosttyTerminal
import HerdrKit

/// Keyed by `terminal_id`, so that SwiftUI never destroys a terminal when its tab goes out of view.
/// ponytail: keyed by terminal id alone; herdr's ids (`term_` and 14 hex digits, from the clock) did not
/// repeat across sessions. Key by session too if they ever do.
@MainActor
final class PaneViewRegistry {
    /// Each terminal kept out of view keeps its surface, about 6 MB (libghostty frees the swap chain while it does not
    /// draw and makes it again in under a millisecond when shown), a copy of its last picture (17 MB for a full-window
    /// card on Retina) and a herdr run of 7 MB. On Retina: 405 MB with 16 terminals in splits, 653 MB with 33
    /// full-window tabs.
    static let spare = UserDefaults.standard.string(forKey: "spareTerminals").flatMap { Int($0) } ?? 25
    /// On critical memory pressure the kept cards out of view go down to half the bounds. Not on a warning: macOS sent
    /// one every 30 minutes at normal pressure with 43 % of 32 GB free, and each dropped web cards that the next
    /// workspace switch made again (100–200 ms each).
    private static let pressure = {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { trim(terminals: spare / 2, web: spareWeb / 2) }
        }
        source.resume()
        return source
    }()

    static var recent: [PaneTerminal] = []
    weak var pages: WindowPages?
    var terminals: [String: PaneTerminal] = [:]
    var browsers: [String: Browser] = [:]
    var plugins: [String: Plugin] = [:]
    var landings: [String: String] = [:]
    var webInView: Set<String> = []
    var pictures: [(id: String, picture: CGImage)] = []
    var pageSize = CGSize.zero {
        didSet {
            guard pageSize != oldValue else { return }
            // Once the size settles: a sidebar's motion gives a size at every frame.
            SettlingHost.settle(&hiddenFitting) { [weak self] in self?.fitHidden() }
        }
    }

    private var hiddenFitting: Task<Void, Never>?
    var chatViews: [String: () -> CGImage?] = [:]
    private var shownIDs: Set<String> = []

    init() {
        _ = Self.pressure
    }

    func terminal(_ terminalID: String, pane paneID: String, client: any Multiplexer) -> PaneTerminal {
        if let terminal = terminals[terminalID] {
            // A moved pane keeps its terminal under a new pane id.
            terminal.paneID = paneID
            return terminal
        }
        let terminal = PaneTerminal(terminalID: terminalID, paneID: paneID, client: client)
        terminal.view.onKeyboard = claim(terminalID)
        terminal.view.onReturn = { [weak self] in self?.pages?.returned(terminalID) }
        terminal.onInput = { [weak self] in self?.pages?.input(terminalID) }
        terminal.watches = { [weak self] in self?.pages?.page(of: terminalID)?.watched ?? false }
        terminal.view.store = { [weak self] in self?.pages?.page(of: terminalID)?.store }
        terminal.view.openLink = { [weak self] link, how in
            Links.open(link, how: how, from: terminalID, page: self?.pages?.page(of: terminalID))
        }
        terminal.view.tileScale = { [weak self] in self?.pages?.tileScale ?? WindowPages.tile }
        terminals[terminalID] = terminal
        return terminal
    }

    func browser(_ pane: HostStore.Pane, _ label: PaneLabel, terminalID: String, store: HostStore) -> Browser {
        // Made again for another iid: its state file is another's.
        if let browser = browsers[terminalID], browser.label.iid == label.iid {
            // Only a change: Observation reports equal writes too, and every card body asks.
            if browser.paneID != pane.id {
                browser.paneID = pane.id
                browser.view.setAccessibilityIdentifier("browser.\(pane.id)")
            }
            return browser
        }
        let browser = Browser(terminalID: terminalID, paneID: pane.id, label: label, store: store)
        browser.view.onKeyboard = claim(terminalID)
        browser.view.pictured = { [weak self] in self?.noted(terminalID) }
        browser.view.shot.image = keptPicture(terminalID)
        browsers[terminalID] = browser
        return browser
    }

    func plugin(_ pane: HostStore.Pane, _ label: PaneLabel, terminalID: String, store: HostStore) -> Plugin? {
        if let plugin = plugins[terminalID], plugin.label.iid == label.iid, plugin.manifest == label.manifest {
            if plugin.paneID != pane.id {
                plugin.paneID = pane.id
            }
            return plugin
        }
        guard let manifest = label.manifest, manifest.entry != nil else { return nil }
        let plugin = Plugin(terminalID: terminalID, paneID: pane.id, label: label, manifest: manifest,
                            place: landings.removeValue(forKey: terminalID), store: store)
        plugin.web.view.onKeyboard = claim(terminalID)
        plugin.web.view.pictured = { [weak self] in self?.noted(terminalID) }
        plugin.web.view.shot.image = keptPicture(terminalID)
        plugin.web.bridge?.shown(webInView.contains(terminalID))
        plugin.web.open = { [weak self] opener, arg, place, how, background in
            guard let page = self?.pages?.page(of: terminalID) else { return }
            Task {
                await page.openFromPlugin(opener, arg: arg, at: place, from: terminalID, how: how,
                                          background: background)
            }
        }
        plugins[terminalID] = plugin
        return plugin
    }

    private func follow(_ alive: Set<String>) {
        pictures.removeAll { !alive.contains($0.id) }
        chatViews = chatViews.filter { alive.contains($0.key) }
        guard !browsers.isEmpty || !plugins.isEmpty else { return }
        let labels = Dictionary((pages?.withFloats ?? []).flatMap(\.store.panes).compactMap { pane in
            pane.terminalID.flatMap { id in pane.plugin.map { (id, $0) } }
        }, uniquingKeysWith: { first, _ in first })
        func kept(_ id: String, _ label: PaneLabel) -> Bool {
            alive.contains(id) && labels[id]
                .map { $0.iid == label.iid && $0.manifest?.id == label.manifest?.id } == true
        }
        browsers = browsers.filter { kept($0.key, $0.value.label) }
        plugins = plugins.filter { kept($0.key, $0.value.label) }
        for (terminalID, plugin) in plugins {
            if let label = labels[terminalID], label != plugin.label {
                plugin.follow(label)
            }
        }
        for (terminalID, browser) in browsers {
            if let label = labels[terminalID] {
                browser.follow(label.arg)
            }
        }
    }

    /// The newest holder: a view that had the keyboard earlier must not take it back when SwiftUI moves it to a new
    /// host (`viewWillMove`). A floating window's (alone in it) drops none.
    private func claim(_ terminalID: String) -> () -> Void {
        { [weak self] in
            guard let self, pages?.floats(terminalID) != true else { return }
            dropClaims(but: terminalID)
            pages?.current?.tookKeyboard(terminalID)
        }
    }

    func show(_ shown: [String: String], web: Set<String>, unvisited: [String: String] = [:], alive: Set<String>,
              client: (any Multiplexer)?)
    {
        let shown = shown.filter { !web.contains($0.key) }
        for id in alive.isEmpty ? [] : shownIDs.subtracting(shown.keys) {
            if let picture = chatViews[id]?() {
                keep(id, picture)
            }
        }
        shownIDs = Set(shown.keys)
        for (terminalID, terminal) in terminals where !alive.contains(terminalID) {
            terminal.close()
            terminals[terminalID] = nil
            Self.recent.removeAll { $0 === terminal }
            PaneTerminal.snapshots.removeAll { $0 === terminal }
        }
        follow(alive)
        let make = { (ids: [String: String]) in
            ids.compactMap { id, pane in client.map { self.terminal(id, pane: pane, client: $0) } ??
                self.terminals[id]
            }
        }
        let visited = make(shown), streaming = visited + make(unvisited)
        for terminal in terminals.values {
            let was = terminal.inView
            terminal.inView = streaming.contains { $0 === terminal }
            if was, !terminal.inView, !Self.recent.contains(where: { $0 === terminal }) {
                terminal.hide()
                terminal.view.dropPicture()
            }
        }
        Self.recent = Self.recent.filter { terminal in !visited.contains { $0 === terminal } } + visited
        streaming.forEach { $0.show() }
        guard !alive.isEmpty else {
            Self.recentWeb.removeAll { $0.registry === self }
            (browsers, plugins, webInView) = ([:], [:], [])
            return
        }
        showWeb(web)
    }

    func terminals(_ ids: Set<String>) -> [PaneTerminal] {
        ids.compactMap { terminals[$0] }
    }

    /// A view that left the window with the keyboard would take it back when its tab returns; this one wins instead.
    func focus(_ terminalID: String) {
        // A panel's keys: its close gives them to the keyboard card.
        guard pages?.panelOpen != true || pages?.floats(terminalID) == true else { return }
        dropClaims(but: terminalID)
        if let chat = pages?.page(of: terminalID)?.store.chats[terminalID], chat.showsChat, chat.live, !chat.drawer {
            chat.wantsKeyboard = true
            return
        }
        terminals[terminalID]?.view.takeKeyboard()
        browsers[terminalID]?.takeKeyboard()
        plugins[terminalID]?.web.view.takeKeyboard()
    }

    func dropClaims(but terminalID: String? = nil) {
        for (id, terminal) in terminals where id != terminalID && pages?.floats(id) != true {
            terminal.view.dropClaim()
        }
        for (id, browser) in browsers where id != terminalID && pages?.floats(id) != true {
            browser.dropClaim()
        }
        for (id, plugin) in plugins where id != terminalID && pages?.floats(id) != true {
            plugin.web.view.dropClaim()
        }
    }

    var keyboardTerminalID: String? {
        let views = terminals.mapValues { $0.view as NSView }.merging(browsers.mapValues(\.view)) { first, _ in first }
            .merging(plugins.mapValues(\.web.view)) { first, _ in first }
        return views.first { pages?.floats($0.key) != true && $0.value.window?.firstResponder === $0.value }?.key
    }
}

extension PaneViewRegistry {
    /// Hidden kept terminals take their card's size, so that their programs hear of a new window size at once and a
    /// switch to the tab shows no reflow.
    func fitHidden() {
        guard let pages, let page = pages.current, let workspace = page.selectedWorkspace, pageSize != .zero
        else { return }
        let area = TabPage.area(pageSize)
        for tab in workspace.tabs where tab.id != page.selectedTab?.id {
            let cards = tab.tree.map { Parts($0, in: area, held: [:]).cards } ?? []
            for (terminalID, paneID) in pages.tileCards(page, tab.id) {
                guard let view = terminals[terminalID]?.view, view.window == nil,
                      let card = page.zoomedPaneID == paneID ? area : cards.first(where: { $0.id == paneID })?.rect
                else { continue }
                let size = PaneCard.terminalSize(card.size, header: page.headerHeight(page.store.pane(paneID)))
                if view.frame.size != size {
                    view.terminal?.hold()
                    view.frame.size = size
                }
            }
        }
    }
}

extension WindowPages {
    var webInView: Set<String> {
        Set(withFloats.flatMap { page in
            page.store.panes.filter { $0.plugin != nil && (page === current && $0.tabID == page.selectedTab?.id
                    || page.floats($0)) }.compactMap(\.terminalID)
        })
    }
}
