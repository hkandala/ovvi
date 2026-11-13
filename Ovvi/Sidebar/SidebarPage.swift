import HerdrKit
import SwiftUI

struct SidebarPage: View {
    let page: Page
    let pages: WindowPages
    let filter: String
    let bottom: CGFloat
    let openSession: () -> Void
    private var settings = AppSettings()
    typealias Row = (workspace: HostStore.Workspace, parent: HostStore.Workspace?)
    /// A row, or the place under the pinned spaces: the line, or the pin region while a space is dragged.
    enum Item: Identifiable {
        case row(Row), pins

        var id: String {
            if case let .row(row) = self {
                row.workspace.id
            } else {
                PinRegion.id
            }
        }
    }

    @AppStorage(Page.foldsAndShelves, store: .sidebar) private var opened = ""
    @State private var hovering = false
    @State private var leaves = 0

    @State private var frames = RowFrames()
    @State private var drop = RowsDrop.State()
    /// The dropped row's way from its place to the drag image's, which the rows' motion takes to 0.
    @State private var landing: (ids: [String], offset: CGFloat)?
    /// The order's changes with a motion and without, for the tests (`recordMotion`).
    @State private var moves = (animated: 0, still: 0)
    @State private var plus = false
    @State private var position = ScrollPosition(idType: String.self)

    var body: some View {
        let store = page.store
        let pinned = store.pins, all = store.groups, groups = page.sidebarGroups
        let spaceDrag: String? = if case let .workspace(id) = page.dragging {
            id
        } else {
            nil
        }
        let top = groups.filter { pinned.contains($0[0].id) }, rest = groups.filter { !pinned.contains($0[0].id) }
        // Not for a worktree, which goes with its repository; nothing to drag in while only the pinned ones show.
        let region = filter.isEmpty && !store.onlyPinned && all.contains { $0[0].id == spaceDrag }
        let items = items(top, rest, region: region)
        // Not the filter's: typed, its rows come and go at once. "pins" is the line's place: a pin or unpin at the
        // groups' border moves no row in the list.
        let order = top.flatMap { $0.map(\.id) } + ["pins"] + rest.flatMap { $0.map(\.id) } + [spaceDrag ?? ""]
        let rowsDrop = RowsDrop(page: page, frames: frames, state: $drop, reorders: filter.isEmpty,
                                shown: top + (region ? [[]] : []) + rest, pinned: pinned, order: spaceOrder,
                                land: land)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(store.title).truncationMode(.middle)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                    .accessibilityIdentifier("sidebar.header")
                    .frame(height: 28)
                    .allowsHitTesting(false)
                Spacer(minLength: gap)
                SortMenu(page: page, order: spaceOrder)
                IconButton(symbol: "plus", help: "New Space", key: .hotkey("space.new")) {
                    Task { await page.newWorkspace() }
                }
                .disabled(store.state != .live)
                .accessibilityIdentifier("sidebar.new-workspace")
                .overlay {
                    if plus, page.dragging != nil {
                        DropIndicator(radius: 7)
                    }
                }
                .onDrop(of: [.ovviDrag], delegate: PaneDrop(page: page, target: .move(.newWorkspace()),
                                                            over: $plus))
                .clearsDrop(page) { plus = false }
            }
            .padding(.leading, Sidebar.rowInsets.leading + WorkspaceRow.textInset)
            .padding(.trailing, Sidebar.rowInsets.trailing)
            .padding(.bottom, 7)
            // Behind the row: on the row, a menu takes the row's frame for the name when it is the row's only element.
            .background { Color.clear.contentShape(.rect).contextMenu { sessionMenu } }
            ScrollView {
                // Lazy: at hundreds of spaces and agents an eager stack makes and lays out every row in each update.
                LazyVStack(alignment: .leading, spacing: WorkspaceRow.gap) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case let .row(row):
                            let next = items.indices.contains(index + 1) ? items[index + 1] : nil
                            self.row(row, top: top, rest: rest, guideBelow: next.map {
                                if case let .row(row) = $0 {
                                    row.parent != nil
                                } else {
                                    false
                                }
                            } ?? false, rowsDrop: rowsDrop)
                        case .pins:
                            pins(region: region)
                                .offset(y: rowsDrop.shift(PinRegion.id))
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: {
                                    frames.rows[PinRegion.id] = $0
                                }
                                .onDisappear { frames.rows[PinRegion.id] = nil }
                        }
                    }
                    if drop.ghost, page.dragging != nil {
                        DropRow(title: "New Space", lit: true)
                    }
                    if items.isEmpty, !store.workspaces.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: "No matching spaces", compact: true)
                            .frame(maxWidth: .infinity)
                    }
                }
                // Every move of the rows (a sort, a pin, Move Up, herdr's order, Show Only Pinned Spaces, a drag's
                // start and drop) in one motion.
                .transaction(value: order) { transaction in
                    if SettlingHost.record {
                        let animated = transaction.animation != nil
                        Task { animated ? (moves.animated += 1) : (moves.still += 1) }
                    }
                }
                .animation(motion, value: order)
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
            .contextMenu { sessionMenu }
            .scrollIndicators(.never)
            // Only asked, never told: the scroll view's writes make the page and the rows in view again.
            .scrollPosition(.constant(position))
            // The lazy stack finds a row not made yet by its own id only, and drops an ask for its fade's room made
            // before the row is: the row asks for that room as it appears.
            .onChange(of: page.selectedWorkspaceID ?? "", initial: true) { _, id in
                frames.wanted = frames.rows[id] == nil ? id : nil
                let target = frames.wanted == nil ? "into view \(id)" : id
                withTransaction(\.animation, nil) { position.scrollTo(id: target) }
                // A new page's first ask can be dropped.
                Task {
                    if frames.wanted == id {
                        position.scrollTo(id: id)
                    }
                }
            }
            .onDrop(of: [.ovviDrag], delegate: rowsDrop)
            .clearsDrop(page) {
                drop.spring?.cancel()
                drop = RowsDrop.State()
            }
            .fadesScrolledEdges(end: 18 + bottom)
            .testValue("sidebar.moves", "Moves", "\(moves.animated) \(moves.still)", shown: SettlingHost.record)
            .background {
                if SettlingHost.record {
                    LitValue(lit: frames.lit)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    if frames.point == nil {
                        hovering = true
                        page.sortHold = page.sortHold ?? unpinnedOrder()
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
                if !Task.isCancelled, !hovering, page.sortHold != nil {
                    page.sortHold = nil
                }
            }
            // A hold from the old sort would keep its order: the menu's pick leaves the pointer over the list, so the
            // hold never clears.
            .onChange(of: spaceOrder) {
                page.sortHold = nil
                if hovering {
                    page.sortHold = unpinnedOrder()
                }
            }
            // Gone under the pointer (another page, the sidebar hidden), it never sees the pointer leave.
            .onDisappear { page.sortHold = nil }
        }
    }
}

private extension SidebarPage {
    /// At the drag image in the drop's update, outside the rows' motion; then to its place in that motion, so with the
    /// rows' own move it goes from the image to its new place on one curve.
    func land(_ ids: [String], _ offset: CGFloat) {
        guard let motion else { return }
        withTransaction(\.disablesAnimations, true) { landing = (ids, offset) }
        DispatchQueue.main.async {
            withAnimation(motion) { landing = nil }
        }
    }

    /// `Page.spaceOrder`, read through the view's own settings so a change in Settings redraws the list.
    private var spaceOrder: SpaceOrder {
        page.store.order ?? settings.spaceOrder
    }

    func row(_ row: Row, top: [[HostStore.Workspace]], rest: [[HostStore.Workspace]], guideBelow: Bool,
             rowsDrop: RowsDrop) -> some View
    {
        let id = row.workspace.id, hasAgents = runsAgents(row.workspace)
        let isPinned = page.store.pins.contains((row.parent ?? row.workspace).id), section = isPinned ? top : rest
        let shown = hasAgents && (!folds(id) || !filter.isEmpty) ? agents(of: row.workspace) : []
        return WorkspaceRow(workspace: row.workspace, parent: row.parent, page: page, frames: frames,
                            guideBelow: guideBelow,
                            ends: spaceOrder == .recent && !isPinned ? (id, id)
                                : (section.first?.first?.id, section.last?.first?.id),
                            pinned: isPinned, agents: shown, hasAgents: hasAgents,
                            fold: filter.isEmpty ? { fold(id) } : nil)
            .equatable()
            .overlay {
                if drop.over == id, page.dragging != nil {
                    DropIndicator()
                }
            }
            .opacity(page.lifted == .workspace(id) ? 0.4 : 1)
            .offset(y: rowsDrop.shift(id) + (landing.map { $0.ids.contains(id) ? $0.offset : 0 } ?? 0))
            // Outside the drag's slide and the drop's glide, so a moving row reports its place.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: {
                frames.rows[id] = $0
                // Moved under a still pointer: a snapshot, a fold, the filter, a reorder.
                frames.aim()
            }
            // A dragged row keeps its target (content frames hold through a scroll) for its slide and landing.
            .onDisappear {
                if page.dragging != .workspace(id) {
                    frames.rows[id] = nil
                }
            }
            .background {
                Color.clear.id("into view \(id)").padding(.top, -18).padding(.bottom, -18 - bottom)
                    .onAppear {
                        if frames.wanted == id {
                            frames.wanted = nil
                            position.scrollTo(id: "into view \(id)")
                        }
                    }
            }
    }

    /// The pin region while a space is dragged, lit while the drop would pin; else the line on the middle of a gap
    /// twice the rows'.
    @ViewBuilder
    func pins(region: Bool) -> some View {
        if region {
            DropRow(title: "Pin Space", lit: drop.region)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel("Pin Space")
                .accessibilityValue(drop.region ? "lit" : "")
                .accessibilityIdentifier("sidebar.pin-region")
        } else {
            Color.clear.frame(height: 0).overlay {
                Rectangle().fill(.primary.opacity(0.14)).frame(height: 1)
                    .accessibilityIdentifier("sidebar.pinned-line")
            }
        }
    }

    /// The rows with the place under the pinned ones: the pin region while a space is dragged, else the line while
    /// unpinned ones follow (not while only the pinned ones show).
    func items(_ top: [[HostStore.Workspace]], _ rest: [[HostStore.Workspace]], region: Bool) -> [Item] {
        let pinned = rows(in: top).map(Item.row), others = rows(in: rest).map(Item.row)
        let line = !pinned.isEmpty && !others.isEmpty && !page.store.onlyPinned
        return pinned + (region || line ? [.pins] : []) + others
    }

    /// The unpinned groups' ids in the current sort.
    func unpinnedOrder() -> [String] {
        let pinned = page.store.pins
        return page.sorted(page.store.groups.filter { !pinned.contains($0[0].id) }).map(\.[0].id)
    }

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

    private func fold(_ workspace: String) {
        withAnimation(motion) {
            opened = opened.togglingLine(page.foldKey(workspace))
        }
    }

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

    @ViewBuilder var sessionMenu: some View {
        Button("New Space") { Task { await page.newWorkspace() } }
            .disabled(page.store.state != .live)
        Button("Open Session…", action: openSession)
        if settings.showArchived {
            Button(opened.hasLine(page.archivedKey) ? "Hide Archived Sessions" : "Show Archived Sessions") {
                withAnimation(motion) {
                    opened = opened.togglingLine(page.archivedKey)
                }
            }
        }
        Button(page.store.onlyPinned ? "Show All Spaces" : "Show Only Pinned Spaces") {
            afterMenu { page.store.onlyPinned.toggle() }
        }
        .disabled(page.store.pins.isEmpty)
        Divider()
        Button("Detach Session") { pages.close(page) }.disabled(!pages.canDetach)
    }

    var motion: Animation? {
        Animation.reduced ? nil : .easeOut(duration: 0.2)
    }
}

/// Its own view: inside the sidebar's body, each change there (an agent's state) made the menu again and closed it.
private struct SortMenu: View {
    let page: Page
    let order: SpaceOrder

    var body: some View {
        Menu {
            Picker(
                "Sort Spaces",
                selection: Binding { order } set: { order in afterMenu { page.store.order = order } },
            ) {
                Text("Manual").tag(SpaceOrder.manual)
                Text("Recent").tag(SpaceOrder.recent)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // As tall as the `+`'s glyph, which is shorter at the same size.
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeStyle(radius: 7))
        .fixedSize()
        .help("Sort Spaces")
        .accessibilityLabel("Sort Spaces")
        .accessibilityValue(order == .manual ? "Manual" : "Recent")
        .accessibilityIdentifier("sidebar.sort")
    }
}
