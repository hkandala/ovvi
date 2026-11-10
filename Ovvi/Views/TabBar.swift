import HerdrKit
import SwiftUI

struct TabBar: View {
    static let width: CGFloat = 220
    static let height: CGFloat = 34
    static let inset: CGFloat = 2
    static let radius: CGFloat = 17

    let workspace: HostStore.Workspace
    let page: Page
    let plus: Bool
    @State private var end = false
    @State private var over: Int?
    @State private var spring: Task<Void, Never>?
    @State private var pulsing: String?
    @State private var space: CGFloat = 0
    @State private var hovered: String?
    @State private var landing: Landing?
    @State private var clicked: String?
    @State private var visible: ClosedRange<CGFloat> = 0 ... .infinity
    @State private var made = 0
    @Environment(\.look) private var look

    var body: some View {
        let tabs = workspace.tabs, count = CGFloat(tabs.count), width = Self.width
        let content = count * width + count - 1
        let hidden = (leading: visible.lowerBound > 0.5, trailing: visible.upperBound < content - 0.5)
        let selected = page.selectedIndex(in: workspace)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // Lazy: a workspace switch makes only the capsules in and near the row's view (SwiftUI makes about a
                // view's width ahead); each costs about 3 ms of the switch.
                LazyHStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        // One view per tab, so a scroll to its id shows the tab, not the divider ahead of it.
                        HStack(spacing: 0) {
                            if index > 0 {
                                let quiet = [index, index - 1].contains(selected)
                                    || [tab.id, tabs[index - 1].id].contains(hovered)
                                Rectangle().fill(look.divider).frame(width: 1, height: Self.height - 16)
                                    .opacity(quiet ? 0 : 1)
                            }
                            TabButton(tab: tab, workspace: workspace, page: page,
                                      hovering: hovered == tab.id, clicked: { clicked = tab.id })
                                .onHover { hovered = $0 ? tab.id : hovered == tab.id ? nil : hovered }
                                .overlay {
                                    if page.dragging?.paneID != nil, over == index {
                                        DropIndicator(radius: Self.radius)
                                    }
                                }
                                .background {
                                    if index == selected {
                                        Pill(shape: RoundedRectangle(cornerRadius: Self.radius - Self.inset,
                                                                     style: .continuous))
                                            .padding(.vertical, Self.inset).allowsHitTesting(false)
                                            .transition(.identity)
                                    }
                                }
                                .scaleEffect(pulsing == tab.id ? 1.04 : 1)
                                .opacity(page.lifted == .tab(tab.id) ? 0.4 : 1)
                                .offset(x: shift(index))
                                .lands(tab.id, landing, axis: .horizontal)
                        }
                        .onAppear {
                            if SettlingHost.record {
                                made += 1
                            }
                        }
                    }
                }
                // A container of its own: without it, a row of one tab that grows to two keeps the first capsule's
                // accessibility element with the whole row's frame (a click there lands between the capsules).
                .accessibilityElement(children: .contain)
                .onDrop(of: [.ovviDrag], delegate: TrackDrop(
                    tabs: tabs, page: page, slot: width + 1, over: $over, spring: $spring, springLoad: springLoad,
                    land: { tab, offset, under in
                        // Its capsule moved under the pointer with no hover event.
                        hovered = under
                        if !Animation.reduced {
                            landing = Landing(ids: [tab], offset: offset, count: (landing?.count ?? 0) + 1)
                        }
                    },
                ))
                .clearsDrop(page) {
                    spring?.cancel() // a late update after the drop may have started one
                    over = nil
                    end = false
                }
                .background {
                    Capsule().fill(look.track).opacity(tabs.count > 1 ? 1 : 0)
                }
                // Room for the Classic pill's shadow (radius 3.5, y 1.5): the scroll view clips.
                .padding(.vertical, 5)
            }
            .scrollIndicators(.never)
            // No rubber band while every tab fits: it cuts the end tab off at the edge.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onScrollGeometryChange(for: ClosedRange<CGFloat>.self) { geometry in
                geometry.contentOffset.x ... geometry.contentOffset.x + geometry.containerSize.width
            } action: {
                visible = $1
            }
            .fadeEdges(.horizontal, start: hidden.leading ? 24 : 0, end: hidden.trailing ? 24 : 0)
            .frame(width: max(min(content, space), 0))
            // minWidth 0: the row's free space, not the tabs' width; else the bar never shrinks.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            // After the tabs, not behind them: a `.forbidden` over the pane's own capsule would fall through to it.
            .overlay(alignment: .leading) {
                Color.clear.contentShape(.rect).gesture(WindowDragGesture())
                    .overlay(alignment: .leading) {
                        if end || plus, page.dragging != nil, content + 1 + width <= space {
                            DropIndicator(radius: Self.radius).frame(width: width, height: Self.height)
                                .padding(.leading, 1)
                        }
                    }
                    .onDrop(of: [.ovviDrag], delegate: PaneDrop(page: page,
                                                                target: .move(.newTab(workspaceID: workspace.id)),
                                                                over: $end))
                    .padding(.leading, min(content, space))
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { space = $0 }
            .onChange(of: page.selectedTabIDs[workspace.id], initial: true) { _, new in
                if let new, new != clicked {
                    withTransaction(\.animation, nil) { proxy.scrollTo(new) }
                    // A new tab's capsule lays out in this same update, and a scroll to it can miss: again once it has.
                    Task { proxy.scrollTo(new) }
                }
                clicked = nil
            }
        }
        .frame(height: Self.height + 10)
        .testValue("tabs.fades", "Tab Fades", [hidden.leading ? "leading" : nil, hidden.trailing ? "trailing" : nil]
            .compactMap(\.self).joined(separator: ", "))
        // The tests' count: the lazy row has no element for a tab out of view.
        .testValue("tabs.count", "Tab Count", "\(tabs.count)")
        .testValue("tabs.made", "Tabs Made", "\(made)", shown: SettlingHost.record)
        .onDisappear { spring?.cancel() }
    }

    private func shift(_ index: Int) -> CGFloat {
        guard case let .tab(id) = page.dragging, let slot = over,
              let from = workspace.tabs.firstIndex(where: { $0.id == id }) else { return 0 }
        let place = slot > from ? slot - 1 : slot
        return (Self.width + 1) * CGFloat(index == from ? place - from
            : from < index && index <= place ? -1 : place <= index && index < from ? 1 : 0)
    }

    private func springLoad(_ tabID: String) {
        clicked = tabID
        page.select(workspace, tab: tabID)
        guard !Animation.reduced else { return }
        withAnimation(.easeOut(duration: 0.1)) { pulsing = tabID }
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.1)) { pulsing = nil }
        }
    }
}
