import AppKit
import HerdrKit
import SwiftUI

extension WindowPages {
    func toggleOverview() {
        if overview {
            closeOverview()
        } else {
            overview = true
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
        showTerminals()
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

    func tileCards(_ page: Page, _ tab: String) -> [(String, String)] {
        let panes = (page.store.tabPanes[tab] ?? []).filter { !page.floats($0) }
        let zoomed = panes.filter { $0.id == page.zoomedPaneID }
        return (zoomed.isEmpty ? panes : zoomed).compactMap { pane in
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
}
