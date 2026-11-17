import HerdrKit
import SwiftUI

extension WindowPages {
    static let tile: CGFloat = 0.35

    func toggleOverview() {
        if overview {
            closeOverview()
        } else {
            overview = true
            Telemetry.used(.overview)
            terminals.takePictures(of: current?.shownTerminals.keys.map(\.self) ?? [])
            showTerminals()
        }
    }

    func closeOverview() {
        guard overview else { return }
        overview = false
        overviewTabs = [:]
        overviewScrolling = false
        overviewSettling?.cancel()
        overviewPhotographed = []
        showTerminals()
        // After the show: a card of the tab the overview opens stays.
        endPhoto()
        current?.focusKeyboardCard()
    }

    /// Each live card keeps a swap chain at its card's size, so a live tab costs about its page's pixels three times
    /// over (69 MB for a full window on Retina): at most 400 MB of tabs (16 tabs took 1.5 GB), and 16 cards (streams).
    /// A remote machine's cards share the relay's one SSH session: 6.
    func overviewCards(_ page: Page) -> [String: String] {
        let tabs = (overviewTabs[page.id] ?? []).reversed().map { tileCards(page, $0) }
        let drawn = { (tab: [(String, String)]) in self.pictured(page, tab) }
        let size = window.map { $0.contentLayoutRect.size.applying(.init(scaleX: $0.backingScaleFactor,
                                                                         y: $0.backingScaleFactor)) }
        let most = size.map { Int(400e6 / max($0.width * $0.height * 12, 1)) } ?? 16
        var cards: [String: String] = [:], taken = 0
        for tabCards in tabs.filter({ !drawn($0) }) {
            guard cards.isEmpty || cards.count + tabCards.count <= (machine.isRemote ? 6 : 16) && taken < most
            else { continue }
            cards.merge(tabCards) { first, _ in first }
            taken += 1
        }
        return cards
    }

    /// Kept on a herdr snapshot (4 a second while agents work), but for closed panes: choosing there makes and frees
    /// surfaces in the middle of a scroll.
    func overviewStreams(_ page: Page, snapshot: Bool) -> [String: String] {
        guard snapshot else { return overviewCards(page) }
        let kept = page.store.panes.compactMap { pane in
            pane.terminalID.flatMap { overviewLive.contains($0) ? ($0, pane.id) : nil }
        }
        return Dictionary(kept) { first, _ in first }
    }

    /// The panes a tile draws: its zoomed one, else all but the floated ones.
    func tilePanes(_ page: Page, _ tab: String) -> [HostStore.Pane] {
        let panes = (page.store.tabPanes[tab] ?? []).filter { !page.floats($0) }
        let zoomed = panes.filter { $0.id == page.zoomedPanes[tab] }
        return zoomed.isEmpty ? panes : zoomed
    }

    func tileCards(_ page: Page, _ tab: String) -> [(String, String)] {
        tilePanes(page, tab).compactMap { pane in
            (pane.plugin == nil || pane.placeholder) && page.shownChat(pane) == nil ? pane.terminalID
                .map { ($0, pane.id) } : nil
        }
    }

    func pictured(_ page: Page, _ cards: [(String, String)]) -> Bool {
        cards.allSatisfy { id, _ in page.terminals.terminals([id]).first?.pictured == true }
    }

    /// 150 ms after the last change: each live tile is a new surface and stream on the main thread, so none turns live
    /// while tiles keep coming (a scroll).
    func settleOverview() {
        guard overview else { return }
        overviewSettling?.cancel()
        // Not while the grid scrolls: its end settles (a surface made or freed mid-scroll drops frames).
        guard !overviewScrolling else { return }
        overviewSettling = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled, !overviewScrolling {
                showTerminals()
            }
        }
    }

    /// One at a time, in the tiles in view: a browser, plugin or chat card with no picture draws live in its tile
    /// until it takes one (`TilePhoto`), at most 10 s, and a web card made for it goes after. One already laid out
    /// takes its picture where it is: in a tile, its web view would leave its card.
    func photographNext() {
        guard overview, !overviewScrolling else { return }
        let waiting = current.map { page in
            page.store.state != .live ? [] : (overviewTabs[page.id] ?? []).reversed().flatMap { tab in
                tilePanes(page, tab).compactMap { pane in
                    pane.terminalID.flatMap { id in
                        !overviewPhotographed.contains(id) && terminals.picture(id) == nil
                            && (pane.browser != nil || pane.plugin?.manifest?.entry != nil
                                || page.shownChat(pane) != nil) ? id : nil
                    }
                }
            }
        } ?? []
        if let photo = overviewPhoto, waiting.contains(photo) {
            return
        }
        endPhoto()
        for id in waiting {
            guard let view = terminals.webView(id), !view.bounds.isEmpty else {
                overviewPhoto = id
                overviewPhotoTimeout = Task {
                    try? await Task.sleep(for: .seconds(10))
                    if !Task.isCancelled {
                        photographed(id)
                    }
                }
                return
            }
            overviewPhotographed.insert(id)
            view.takePicture()
        }
    }

    /// Its picture taken, or none in time.
    func photographed(_ id: String) {
        guard overviewPhoto == id else { return }
        overviewPhotographed.insert(id)
        endPhoto(pictured: true)
        photographNext()
    }

    /// Its tile scrolled out, another session shows or the overview closes: a card made only for its picture goes,
    /// with no picture unless it took one (one taken out of a window may be blank, and its tile would not try again).
    private func endPhoto(pictured: Bool = false) {
        guard let id = overviewPhoto else { return }
        overviewPhoto = nil
        overviewPhotoTimeout?.cancel()
        guard terminals.droppable(id) else { return }
        if pictured {
            terminals.drop(id)
        } else {
            (terminals.browsers[id], terminals.plugins[id]) = (nil, nil)
        }
    }
}
