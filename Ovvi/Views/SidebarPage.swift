import HerdrKit
import SwiftUI

struct SidebarPage: View {
    let page: Page
    let pages: WindowPages
    let filter: String
    /// Room under the rows for what lies over the list's end (the page dots), which the end's fade runs under too.
    var bottom: CGFloat = 0
    var openSession: () -> Void = {}
    private var settings = AppSettings()
    typealias Row = (workspace: HostStore.Workspace, parent: HostStore.Workspace?)
    /// The folded spaces (`Page.foldKey`), with the open shelf; spaces start unfolded.
    @AppStorage(Page.openShelves, store: .agents) private var opened = ""
    @AppStorage(SpaceOrder.key, store: .agents) private var spaceOrder = SpaceOrder.manual
    /// The groups' heads in the order on screen while the pointer is over the rows: in Recent they hold still until
    /// it leaves, and 1 s more.
    @State private var held: [String]?
    @State private var hovering = false
    @State private var leaves = 0

    /// The rows' frames, for drops; measured outside the slide and the glide, so a moving row reports its place.
    @State private var frames = RowFrames()
    @State private var drop = RowsDrop.State()
    /// The workspace dropped last: its rows glide into their place.
    @State private var landing: Landing?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A pane or a tab dragged over the header's `+`.
    @State private var plus = false
    @State private var position = ScrollPosition(idType: String.self)

    var body: some View {
        let store = page.store
        let reorders = filter.isEmpty && spaceOrder == .manual
        let rowsDrop = RowsDrop(page: page, frames: frames, state: $drop, reorders: reorders) { rows, offset in
            if !reduceMotion || Animation.forceMotion {
                landing = Landing(ids: rows, offset: offset, count: (landing?.count ?? 0) + 1)
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(store.title).truncationMode(.middle)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                    .accessibilityIdentifier("sidebar.header")
                    // The `+`'s height.
                    .frame(height: 28)
                    // A right-click on it reaches the row's menu.
                    .allowsHitTesting(false)
                Spacer()
                sortMenu
                IconButton(symbol: "plus", help: "New Space") { Task { await page.newWorkspace() } }
                    .disabled(store.state != .live)
                    .accessibilityIdentifier("sidebar.new-workspace")
                    // A new workspace, as the ghost row under the rows, which a full page has no room for.
                    .overlay {
                        if plus, page.dragging != nil {
                            DropIndicator(radius: 7)
                        }
                    }
                    .onDrop(of: [.ovviDrag], delegate: PaneDrop(page: page, target: .move(.newWorkspace()),
                                                                over: $plus))
                    .clearsDrop(page) { plus = false }
            }
            // On one edge: the space rows' names, the agents' tiles, the shelf's label.
            .padding(.leading, Sidebar.rowInsets.leading + WorkspaceRow.textInset)
            // The `+` ends where the rows do.
            .padding(.trailing, Sidebar.rowInsets.trailing)
            // Rex's first row sits 31.5 pt below the header's baseline.
            .padding(.bottom, 3)
            // Behind the row: on the row, a menu takes the row's frame for the name when it is the row's only element.
            .background { Color.clear.contentShape(.rect).contextMenu { sessionMenu } }
            ScrollView {
                // Lazy: at hundreds of spaces and agents an eager stack made and laid out every row in each update.
                LazyVStack(alignment: .leading, spacing: WorkspaceRow.gap) {
                    let groups = sorted(store.groups), rows = rows(in: groups)
                    ForEach(Array(rows.enumerated()), id: \.element.workspace.id) { index, row in
                        let id = row.workspace.id, hasAgents = runsAgents(row.workspace)
                        let shown = hasAgents && (!folds(id) || !filter.isEmpty) ? agents(of: row.workspace) : []
                        WorkspaceRow(workspace: row.workspace, parent: row.parent, page: page, frames: frames,
                                     guideBelow: rows.indices.contains(index + 1)
                                         && rows[index + 1].parent != nil,
                                     // In Recent no row moves: each is both ends.
                                     ends: spaceOrder == .recent ? (row.workspace.id, row.workspace.id)
                                         : (groups.first?.first?.id, groups.last?.first?.id),
                                     agents: shown, hasAgents: hasAgents,
                                     fold: filter.isEmpty ? { fold(id) } : nil)
                            .equatable()
                            .overlay {
                                if drop.over == id, page.dragging != nil {
                                    DropIndicator()
                                }
                            }
                            .opacity(page.lifted == .workspace(id) ? 0.4 : 1)
                            .offset(y: rowsDrop.shift(id))
                            .lands(id, landing, axis: .vertical)
                            // Its place in the list, outside the drag's slide and the drop's glide.
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: {
                                frames.rows[id] = $0
                            }
                            // Hidden by the filter, closed or out of the lazy stack: no stale target. A dragged
                            // row keeps its place (content frames hold through a scroll) for its slide and landing.
                            .onDisappear {
                                if page.dragging != .workspace(id) {
                                    frames.rows[id] = nil
                                }
                            }
                            .background {
                                Color.clear.id("into view \(id)").padding(.top, -18).padding(.bottom, -18 - bottom)
                            }
                    }
                    if drop.ghost, page.dragging != nil {
                        Text("New Space").foregroundStyle(.secondary).padding(.leading, WorkspaceRow.textInset)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .background { DropIndicator() }
                    }
                    if rows.isEmpty, !store.workspaces.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: "No matching spaces", compact: true)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(Sidebar.rowInsets)
                .padding(.bottom, bottom)
                // The content's own space, which a scroll does not move: no frame changes at every scroll frame.
                .coordinateSpace(.named("rows"))
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.visibleRect.minY } action: {
                frames.top = $1
                frames.aim()
            }
            .onScrollPhaseChange { _, phase in
                frames.scrolling = phase != .idle
                frames.aim()
            }
            // Under the rows; a row's own menu wins on the row.
            .contextMenu { sessionMenu }
            .scrollIndicators(.never)
            // Only asked, never told: the scroll view's writes made the page and the rows in view again.
            .scrollPosition(.constant(position))
            // The selected row and the fade's room round it (its background) into view, just enough, however
            // it was selected; again once laid out, for a row new in this update (a new page).
            // The lazy stack finds a row not made yet by its own id only.
            .onChange(of: page.selectedWorkspaceID ?? "", initial: true) { _, id in
                withTransaction(\.animation, nil) { position.scrollTo(id: "into view \(id)") }
                // A new page's first ask can be dropped; then the row may not be made yet.
                Task {
                    position.scrollTo(id: id)
                    await Task.yield()
                    position.scrollTo(id: "into view \(id)")
                }
            }
            .onDrop(of: [.ovviDrag], delegate: rowsDrop)
            .clearsDrop(page) {
                drop.spring?.cancel()
                drop = RowsDrop.State()
            }
            .fadesScrolledEdges(end: 18 + bottom)
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    if frames.point == nil {
                        hovering = true
                        held = held ?? sorted(store.groups).map(\.[0].id)
                    }
                    frames.point = point
                case .ended:
                    frames.point = nil
                    hovering = false
                    leaves += 1
                }
                frames.aim()
            }
            .task(id: leaves) {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled, !hovering, held != nil {
                    withAnimation(motion) {
                        held = nil
                    }
                }
            }
        }
    }

    /// Not observed: rows write their frames as the lazy stack makes them, and a body for each would make the rows in
    /// view again.
    final class RowFrames {
        /// The rows' frames in the content.
        var rows: [String: CGRect] = [:]
        /// The visible part's top in the content: a drop's point in the scroll view plus this.
        var top: CGFloat = 0
        /// The space headers' and agent lines' frames in the content, for the pointer.
        var targets: [String: CGRect] = [:]
        /// The pointer in the scroll view, while it is over it.
        var point: CGPoint?
        /// No light while the rows move under the pointer; again once they stop.
        var scrolling = false
        /// The space header or agent line under the pointer, found from the pointer's place: one hover for the list,
        /// where a hover region in each row cost every scroll frame a hit test of each (half the frames at 200
        /// spaces). Each target observes its own light: one value all observed lit every made button again.
        var pointer: String? {
            didSet {
                if pointer != oldValue {
                    oldValue.map { light($0).lit = false }
                    pointer.map { light($0).lit = true }
                }
            }
        }

        private var lights: [String: RowLight] = [:]

        /// ponytail: a light per target made, kept with the page (a few hundred); prune with the targets if it grows.
        func light(_ id: String) -> RowLight {
            let light = lights[id] ?? RowLight()
            lights[id] = light
            return light
        }

        /// The header or line under the pointer lights: after a move, a scroll, or a target that moved under it.
        func aim() {
            let point = scrolling ? nil : point.map { CGPoint(x: $0.x, y: $0.y + top) }
            pointer = point.flatMap { point in targets.first { $0.value.contains(point) }?.key }
        }
    }

    /// Recent: the group whose agent changed state last first (`Pane.changeSeq`; the user's look at a finish is no
    /// change), the rest in herdr's order; as held while the pointer is over the rows (a new group under them).
    private func sorted(_ groups: [[HostStore.Workspace]]) -> [[HostStore.Workspace]] {
        guard spaceOrder == .recent else { return groups }
        let place = Dictionary(uniqueKeysWithValues: (held ?? []).enumerated().map { ($1, $0) })
        return groups.map { group in
            let changed = group.flatMap(\.tabs).flatMap { page.store.panes(in: $0.id) }.compactMap(\.changeSeq).max()
            return (group, place[group[0].id] ?? .max, -(changed ?? -1))
        }
        .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
        .map(\.0)
    }

    /// The workspace's agent panes by tab, then by place in the tab (left and top first), never by state; with a
    /// filter, those whose title, agent or tab matches.
    private func agents(of workspace: HostStore.Workspace) -> [HostStore.Pane] {
        workspace.tabs.flatMap { tab -> [HostStore.Pane] in
            let panes = page.store.panes(in: tab.id).filter { $0.state != nil }
            let place = tab.tree?.paneIDs ?? []
            return place.compactMap { id in panes.first { $0.id == id } } + panes.filter { !place.contains($0.id) }
        }
        .filter { pane in
            filter.isEmpty || [pane.agentTitle, pane.agentName, page.place(pane)].compactMap(\.self)
                .contains { $0.matches(filter) }
        }
    }

    /// By herdr's agent kind, which changes far less than the states: a folded row draws again for no state change.
    private func runsAgents(_ workspace: HostStore.Workspace) -> Bool {
        workspace.tabs.contains { page.store.panes(in: $0.id).contains { $0.agent != nil } }
    }

    private func folds(_ workspace: String) -> Bool {
        opened.hasLine(page.foldKey(workspace))
    }

    /// Folds or unfolds the space's agents, kept per machine and session across relaunches.
    private func fold(_ workspace: String) {
        withAnimation(motion) {
            opened = opened.togglingLine(page.foldKey(workspace))
        }
    }

    /// The rows that pass the filter by name or branch, or by an agent's, each with the workspace it sits under; a
    /// matching worktree keeps its repository's row.
    private func rows(in groups: [[HostStore.Workspace]]) -> [Row] {
        groups.flatMap { group -> [Row] in
            let shown = group.filter { workspace in
                workspace.label.matches(filter) || (workspace.git?.branch ?? "").matches(filter)
                    || !filter.isEmpty && !agents(of: workspace).isEmpty
            }
            guard let head = group.first, !shown.isEmpty else { return [] }
            return (shown.first === head ? shown : [head] + shown).map { Row($0, $0 === head ? nil : head) }
        }
    }
}

private extension SidebarPage {
    /// The page header's and the empty sidebar's menu: the session's own actions, as the menu bar has them. Detach
    /// Session takes the page out of this window; the herdr session keeps running.
    @ViewBuilder var sessionMenu: some View {
        Button("New Space") { Task { await page.newWorkspace() } }
            .disabled(page.store.state != .live)
        Button("Open Session…", action: openSession)
        if settings.showClosed {
            Button(opened.hasLine(page.archivedKey) ? "Hide Archived Sessions" : "Show Archived Sessions") {
                withAnimation(motion) {
                    opened = opened.togglingLine(page.archivedKey)
                }
            }
        }
        Divider()
        Button("Detach Session") { pages.close(page) }.disabled(pages.list.count < 2)
    }

    var sortMenu: some View {
        Menu {
            Picker("Sort Spaces", selection: $spaceOrder.animation(motion)) {
                Text("Manual").tag(SpaceOrder.manual)
                Text("Recent").tag(SpaceOrder.recent)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "arrow.up.arrow.down").fontWeight(.medium).frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeStyle(radius: 7))
        .fixedSize()
        .help("Sort Spaces")
        .accessibilityLabel("Sort Spaces")
        .accessibilityValue(spaceOrder == .manual ? "Manual" : "Recent")
        .accessibilityIdentifier("sidebar.sort")
    }

    var motion: Animation? {
        reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)
    }
}

/// A space header's or an agent line's light under the pointer (`SidebarPage.RowFrames.pointer`).
@Observable
final class RowLight {
    var lit = false
}
