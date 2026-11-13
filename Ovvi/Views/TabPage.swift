import HerdrKit
import SwiftUI

struct TabPage: View {
    let tab: HostStore.Tab
    let page: Page
    /// Not by `accessibilityHidden(false)` when shown, which overrides the hidden ones inside (a zoom's cards under
    /// it).
    @Environment(\.pageHidden) private var hidden

    var body: some View {
        Group {
            if let tree = tab.tree {
                let zoomed = page.zoomedPanes[tab.id].flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                SplitLayout(tree: tree, zoomed: zoomed, page: page, tabID: tab.id)
                    .padding(Self.inset)
            } else {
                EmptyState(symbol: "rectangle.split.2x1", title: "No layout for this tab")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self, of: \.size) { page.terminals.pageSize = $0 }
        .accessibilityElement(children: hidden ? .ignore : .contain)
        .accessibilityIdentifier(hidden ? "" : "page.\(tab.id)")
    }

    static let inset = EdgeInsets(top: 4, leading: gap, bottom: gap, trailing: gap)

    static func area(_ size: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: size.width - inset.leading - inset.trailing,
               height: size.height - inset.top - inset.bottom)
    }
}

/// Drawn flat: each card and divider keeps its view (by pane id, or the split's path) whatever the tree does, so no
/// terminal view changes host.
private struct SplitLayout: View {
    let tree: SplitNode
    let zoomed: String?
    let page: Page
    let tabID: String
    /// Not a transition: `.move` and `.offset` transitions move nothing here, only their fade runs.
    @State private var placed: [(id: String, view: String)]?
    @State private var held: [[Bool]: Double] = [:]
    @State private var cards = (came: 0, went: 0)
    @Environment(\.pageHidden) private var hidden
    @Environment(\.look) private var look
    /// Passed on as `look` is: each card is drawn in its own hosting view.
    @Environment(\.pageReconnecting) private var reconnecting

    private var motion: Animation? {
        Animation.reduced ? nil : .easeOut(duration: MovingCard.slide)
    }

    var body: some View {
        let move = motion == nil || hidden ? 0 : tree.hashValue &+ (zoomed?.hashValue ?? 0)
        GeometryReader { geometry in
            let area = CGRect(origin: .zero, size: geometry.size)
            let parts = Parts(tree, in: area, held: held)
            let views = views(parts.cards.map(\.id))
            ZStack(alignment: .topLeading) {
                ForEach(parts.cards.map { (view: views[$0.id] ?? $0.id, card: $0) }, id: \.view) { _, card in
                    let away = zoomed != nil && zoomed != card.id
                    let entering = placed != nil && views[card.id] == nil && move != 0
                    let rect = zoomed == card.id ? area : card.rect
                    CardMotion(rect: rect, move: move, start: entering ? card.start : nil, hidden: hidden, id: card.id,
                               look: look,
                               content: PaneCard(id: card.id, page: page, away: away)
                                   .overlay { CardFlash(store: page.store, id: card.id) }
                                   .environment(\.look, look).environment(\.pageHidden, hidden)
                                   .environment(\.pageReconnecting, reconnecting))
                        .place(rect)
                        .transaction(value: move) { $0.animation = nil }
                        .opacity(page.lifted == .pane(card.id) ? 0.4 : 1)
                        .animation(motion) { $0.opacity(away ? 0 : 1) }
                        .zIndex(away ? 0 : 1)
                        .allowsHitTesting(!away)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                        .onAppear {
                            if SettlingHost.record {
                                cards.came += 1
                            }
                        }
                        .onDisappear {
                            if SettlingHost.record {
                                cards.went += 1
                            }
                        }
                }
                ForEach(parts.dividers, id: \.id) { divider in
                    let names = divider.beside.map { $0.flatMap(page.store.pane)?.cardTitle ?? "terminal" }
                    SplitDivider(divider: divider, held: $held[divider.path], page: page, tabID: tabID,
                                 label: "Divider between \(names[0]) and \(names[1])")
                        .place(divider.rect)
                        .opacity(zoomed == nil ? 1 : 0)
                        .allowsHitTesting(zoomed == nil)
                        .accessibilityHidden(zoomed != nil)
                        .zIndex(2)
                }
            }
        }
        .testValue("cards.\(tabID)", "Cards", "\(cards.came) \(cards.went)", shown: SettlingHost.record)
        .animation(motion, value: tree)
        .animation(motion, value: zoomed)
        .onChange(of: tree, initial: true) {
            let views = views(tree.paneIDs), moving = placed != nil && motion != nil && !hidden
            if moving {
                page.terminals.pages?.window?.holdStill()
            }
            placed = tree.paneIDs.map { ($0, views[$0] ?? $0) }
        }
    }

    private func views(_ ids: [String]) -> [String: String] {
        guard let placed else { return [:] }
        // Not `uniqueKeysWithValues`: a pane twice in herdr's tree must not crash the app.
        var views = Dictionary(placed.filter { ids.contains($0.id) }, uniquingKeysWith: { first, _ in first })
        for (new, old) in page.store.ahead.cards where ids.contains(new) {
            views[new] = placed.first { $0.id == old }?.view ?? views[new]
        }
        let gone = placed.filter { Ahead.isStandIn($0.id) && !ids.contains($0.id) }
        for (new, old) in zip(ids.filter { views[$0] == nil }, gone) {
            views[new] = old.view
        }
        return views
    }
}

private extension NSWindow {
    /// Not movable while the cards slide: at each frame of a layout change AppKit works out a movable window's drag
    /// region, for which SwiftUI walks every view under the title row (15–25 % of a split's frames).
    func holdStill() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        isMovable = false
        Task {
            try? await Task.sleep(for: .seconds(MovingCard.slide))
            isMovable = true
        }
    }
}

private extension View {
    /// By layout (`position`), not `.offset`: a layout change animates every view in it, the terminal's too. Not
    /// padding: it gives a card sliding in from the left a size below zero.
    func place(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}
