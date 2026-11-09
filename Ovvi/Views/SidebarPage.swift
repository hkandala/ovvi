import HerdrKit
import SwiftUI

struct SidebarPage: View {
    let page: Page
    let pages: WindowPages
    let filter: String
    /// Room under the rows for what lies over the list's end (the page dots), which the end's fade runs under too.
    var bottom: CGFloat = 0
    typealias Row = (workspace: HostStore.Workspace, parent: HostStore.Workspace?)
    /// The folded spaces (`Page.foldKey`), with the open shelf; spaces start unfolded.
    @AppStorage(Page.openShelves, store: .agents) private var opened = ""
    /// Each workspace's agents in the order on screen while the pointer is over the rows: they hold still until it
    /// leaves, and 1 s more.
    @State private var held: [String: [String]]?
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
        let rowsDrop = RowsDrop(page: page, rows: frames, state: $drop, reorders: filter.isEmpty) { rows, offset in
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
            // The herdr session keeps running. Behind the row: on the row, a menu takes the row's frame for the name
            // when it is the row's only element.
            .background {
                Color.clear.contentShape(.rect)
                    .contextMenu { Button("Detach Session") { pages.close(page) }.disabled(pages.list.count < 2) }
            }
            if store.state == .live, store.workspaces.isEmpty {
                EmptyState(symbol: "square.dashed", title: "No Spaces", compact: true) {
                    Button("New Space") { Task { await page.newWorkspace() } }
                        .accessibilityIdentifier("new-workspace")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Lazy: at hundreds of spaces and agents an eager stack made and laid out every row in each update.
                    LazyVStack(alignment: .leading, spacing: WorkspaceRow.gap) {
                        let rows = rows, groups = store.groups
                        ForEach(Array(rows.enumerated()), id: \.element.workspace.id) { index, row in
                            let id = row.workspace.id, hasAgents = runsAgents(row.workspace)
                            let shown = hasAgents && (!folds(id) || !filter.isEmpty) ? agents(of: row.workspace) : []
                            WorkspaceRow(workspace: row.workspace, parent: row.parent, page: page,
                                         guideBelow: rows.indices.contains(index + 1)
                                             && rows[index + 1].parent != nil,
                                         ends: (groups.first?.first?.id, groups.last?.first?.id),
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
                                // Hidden by the filter, closed or out of the lazy stack: no stale target.
                                .onDisappear { frames.rows[id] = nil }
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
                .onScrollGeometryChange(for: CGFloat.self) { $0.visibleRect.minY } action: { frames.top = $1 }
                .scrollIndicators(.never)
                // Only asked, never told: the scroll view's writes made the page and the rows in view again.
                .scrollPosition(.constant(position))
                // The selected row and the fade's room round it (its background) into view, just enough, however
                // it was selected; again once laid out, for a row new in this update (a new page).
                // The lazy stack finds a row not made yet by its own id only.
                .onChange(of: page.selectedWorkspaceID ?? "", initial: true) { _, id in
                    withTransaction(\.animation, nil) { position.scrollTo(id: id) }
                    Task { position.scrollTo(id: "into view \(id)") }
                }
                .onDrop(of: [.ovviDrag], delegate: rowsDrop)
                .clearsDrop(page) {
                    drop.spring?.cancel()
                    drop = RowsDrop.State()
                }
                .fadesScrolledEdges(end: 18 + bottom)
                .onHover { inside in
                    hovering = inside
                    if inside {
                        held = held ?? Dictionary(uniqueKeysWithValues: store.workspaces.map { ($0.id, order($0)) })
                    } else {
                        leaves += 1
                    }
                }
                .task(id: leaves) {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled, !hovering, held != nil {
                        withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) {
                            held = nil
                        }
                    }
                }
            }
        }
    }

    /// The workspace's agent panes, newest change of state first (herdr's `state_change_seq`, herdr's order among
    /// equals), as held while the pointer is over the rows; with a filter, those whose title, agent or tab matches.
    /// Not observed: rows write their frames as the lazy stack makes them, and a body for each would make the rows in
    /// view again.
    final class RowFrames {
        /// In the rows' content.
        var rows: [String: CGRect] = [:]
        /// The visible part's top in the content: a drop's point in the scroll view plus this.
        var top: CGFloat = 0
    }

    private func agents(of workspace: HostStore.Workspace) -> [HostStore.Pane] {
        let now = order(workspace)
        let ids = held?[workspace.id].map { held in held.filter(now.contains) + now.filter { !held.contains($0) } }
            ?? now
        return ids.compactMap(page.store.pane).filter { pane in
            filter.isEmpty || [pane.agentTitle, pane.agentName, page.place(pane)].compactMap(\.self)
                .contains { $0.matches(filter) }
        }
    }

    /// By herdr's agent kind, which changes far less than the states: a folded row draws again for no state change.
    private func runsAgents(_ workspace: HostStore.Workspace) -> Bool {
        workspace.tabs.contains { page.store.panes(in: $0.id).contains { $0.agent != nil } }
    }

    private func order(_ workspace: HostStore.Workspace) -> [String] {
        workspace.tabs.flatMap { page.store.panes(in: $0.id).filter { $0.state != nil } }.enumerated()
            .sorted { ($0.element.changeSeq ?? -1, -$0.offset) > ($1.element.changeSeq ?? -1, -$1.offset) }
            .map(\.element.id)
    }

    private func folds(_ workspace: String) -> Bool {
        opened.hasLine(page.foldKey(workspace))
    }

    /// Folds or unfolds the space's agents, kept per machine and session across relaunches.
    private func fold(_ workspace: String) {
        withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) {
            opened = opened.togglingLine(page.foldKey(workspace))
        }
    }

    /// The rows that pass the filter by name or branch, or by an agent's, each with the workspace it sits under; a
    /// matching worktree keeps its repository's row.
    private var rows: [Row] {
        page.store.groups.flatMap { group -> [Row] in
            let shown = group.filter { workspace in
                workspace.label.matches(filter) || (workspace.git?.branch ?? "").matches(filter)
                    || !filter.isEmpty && !agents(of: workspace).isEmpty
            }
            guard let head = group.first, !shown.isEmpty else { return [] }
            return (shown.first === head ? shown : [head] + shown).map { Row($0, $0 === head ? nil : head) }
        }
    }
}
