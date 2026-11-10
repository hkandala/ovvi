import HerdrKit
import SwiftUI

/// Equatable: the overview's body runs again on every change of the live set, which would make every tile's body again.
struct OverviewPage: View, Equatable {
    let pages: WindowPages
    let page: Page
    let size: CGSize
    let side: CGFloat
    let columns: Int
    let open: (HostStore.Workspace, HostStore.Tab) -> Void
    @State private var scrolling = false

    var body: some View {
        ScrollView(.vertical) {
            let grid = Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
            VStack(alignment: .leading, spacing: 16) {
                Text(page.store.title).font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier("overview.title")
                LazyVGrid(columns: grid, alignment: .leading, spacing: 16) {
                    ForEach(page.sidebarWorkspaces) { workspace in
                        Section {
                            ForEach(workspace.tabs) { tab in
                                Tile(
                                    pages: pages,
                                    page: page,
                                    workspace: workspace,
                                    tab: tab,
                                    size: size,
                                ) { open(workspace, tab) }
                                    .equatable()
                            }
                        } header: {
                            Text(workspace.label).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 16)
                                .padding(.bottom, -4)
                                .accessibilityIdentifier("overview.workspace.\(workspace.id)")
                        }
                    }
                }
            }
            .padding(.horizontal, side)
            .padding(.vertical, 40)
            .shielded(scrolling)
        }
        .scrollIndicators(.never)
        .onScrollPhaseChange { _, phase in
            scrolling = phase.isScrolling
            pages.overviewScrolling = phase != .idle
            if phase == .idle {
                pages.settleOverview()
            }
        }
        // Another session shows: its tiles report no leaving, and would stay live out of view; a scroll that goes with
        // it never ends.
        .onDisappear {
            pages.overviewTabs[page.id] = nil
            pages.overviewScrolling = false
            pages.settleOverview()
        }
    }

    /// All but `open`, a closure made anew with the overview's body.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pages === rhs.pages && lhs.page === rhs.page && lhs.size == rhs.size && lhs.side == rhs.side
            && lhs.columns == rhs.columns
    }
}

extension View {
    /// SwiftUI looks for the tile under the pointer at every frame (a tenth of the main thread). Not
    /// `allowsHitTesting`, whose change makes every tile's body again, equatable or not (30–60 tiles, 20–40 ms at a
    /// scroll's start).
    func shielded(_ shielding: Bool) -> some View {
        overlay {
            if shielding {
                Color.clear.contentShape(.rect)
            }
        }
    }
}

/// Equatable: the page's body runs again when its grid starts or stops scrolling (30–70 tiles, 40 ms).
private struct Tile: View, Equatable {
    let pages: WindowPages
    let page: Page
    let workspace: HostStore.Workspace
    let tab: HostStore.Tab
    let size: CGSize
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.look) private var look

    var body: some View {
        let selected = page.selectedTabIDs[workspace.id] == tab.id
        let state = tab.agent?.state
        let loading = !pages.pictured(page, pages.tileCards(page, tab.id))
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                IconStack(panes: page.stack(tab))
                FadeText(text: page.titleLabel(tab)).fontWeight(.medium)
                Spacer(minLength: 0)
                if hovering {
                    IconButton(symbol: "xmark", help: "Close Tab", key: .closeTab, size: 22) {
                        page.close(.tab(tab.id))
                    }
                    .accessibilityIdentifier("overview.tab.\(tab.id).close")
                } else {
                    state?.label(look)
                }
            }
            .padding(.leading, 11)
            .padding(.trailing, 8)
            .frame(height: PaneCard.header)
            Miniature(tab: tab, page: page, size: size, live: pages.overviewLive)
                .overlay {
                    if loading {
                        Loader(id: "overview.tab.\(tab.id).loading")
                            .onAppear { Latency.shared.note("loader \(tab.id)") }
                    }
                }
                .onChange(of: loading) { pages.settleOverview() }
                .aspectRatio(size, contentMode: .fit)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { pages.tileScale = $0 / size.width }
                .padding([.horizontal, .bottom], gap)
        }
        .frame(maxWidth: .infinity)
        .background(CardSurface(keyboard: selected))
        .onScrollVisibilityChange(threshold: 0.01) { laidOut($0) }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(page.titleText(tab))
        .accessibilityValue(selected ? "selected" : "")
        .accessibilityIdentifier("overview.tab.\(tab.id)")
        .accessibilityAction(.default, open)
    }

    /// All but `open`, a closure made anew with the page's body.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pages === rhs.pages && lhs.page === rhs.page && lhs.workspace === rhs.workspace && lhs.tab === rhs.tab
            && lhs.size == rhs.size
    }

    private func laidOut(_ shown: Bool) {
        guard pages.overview else { return }
        pages.overviewTabs[page.id, default: []].removeAll { $0 == tab.id }
        if shown {
            pages.overviewTabs[page.id, default: []].append(tab.id)
        }
        pages.settleOverview()
    }
}
