import HerdrKit
import SwiftUI

struct SidebarPage: View {
    let page: Page
    let pages: WindowPages
    let filter: String
    var bottom: CGFloat = 0
    var openSession: () -> Void = {}
    private var settings = AppSettings()
    typealias Row = (workspace: HostStore.Workspace, parent: HostStore.Workspace?)
    @AppStorage(Page.openShelves, store: .agents) private var opened = ""
    @Environment(\.spaceOrder) private var windowOrder
    @State private var held: [String]?
    @State private var hovering = false
    @State private var leaves = 0

    @State private var frames = RowFrames()
    @State private var drop = RowsDrop.State()
    @State private var plus = false
    @State private var position = ScrollPosition(idType: String.self)

    var body: some View {
        let store = page.store
        let pinned = store.pins, all = store.groups
        let spaceDrag: String? = if case let .workspace(id) = page.dragging {
            id
        } else {
            nil
        }
        let top = all.filter { pinned.contains($0[0].id) }
        let rest = sorted(all.filter { !pinned.contains($0[0].id) })
        let rowsDrop = RowsDrop(page: page, frames: frames, state: $drop, reorders: filter.isEmpty, shown: top + rest,
                                pinned: pinned, order: spaceOrder)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(store.title).truncationMode(.middle)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                    .accessibilityIdentifier("sidebar.header")
                    .frame(height: 28)
                    .allowsHitTesting(false)
                Spacer(minLength: gap)
                sortMenu
                IconButton(symbol: "plus", help: "New Space", key: .newWorkspace) { Task { await page.newWorkspace() } }
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
                    let rows = rows(in: top + rest)
                    // The line under the pinned spaces, when unpinned ones follow.
                    let line = rows.last { pinned.contains(($0.parent ?? $0.workspace).id) }?.workspace.id
                    let lined = rows.contains { !pinned.contains(($0.parent ?? $0.workspace).id) } ? line : nil
                    ForEach(Array(rows.enumerated()), id: \.element.workspace.id) { index, row in
                        let id = row.workspace.id, hasAgents = runsAgents(row.workspace)
                        let isPinned = pinned.contains((row.parent ?? row.workspace).id),
                            section = isPinned ? top : rest
                        let shown = hasAgents && (!folds(id) || !filter.isEmpty) ? agents(of: row.workspace) : []
                        WorkspaceRow(workspace: row.workspace, parent: row.parent, page: page, frames: frames,
                                     guideBelow: rows.indices.contains(index + 1)
                                         && rows[index + 1].parent != nil,
                                     ends: spaceOrder == .recent && !isPinned ? (id, id)
                                         : (section.first?.first?.id, section.last?.first?.id),
                                     pinned: isPinned,
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
                            // Outside the drag's slide, so a moving row reports its place.
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: {
                                frames.rows[id] = $0
                            }
                            // A dragged row keeps its target (content frames hold through a scroll) for its slide and
                            // landing.
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
                            // On the middle of a gap twice the rows'.
                            .padding(.bottom, lined == id ? WorkspaceRow.gap : 0)
                            .overlay(alignment: .bottom) {
                                // Hidden while a space is dragged: the rows slide across its place.
                                if lined == id, spaceDrag == nil {
                                    Rectangle().fill(.primary.opacity(0.14)).frame(height: 1).offset(y: 0.5)
                                        .accessibilityIdentifier("sidebar.pinned-line")
                                }
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
            // Outside the fade's mask, over the header's bottom padding.
            .overlay(alignment: .top) {
                if pinned.isEmpty, filter.isEmpty, let spaceDrag, all.contains(where: { $0[0].id == spaceDrag }) {
                    pinLine
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    if frames.point == nil {
                        hovering = true
                        let pinned = store.pins
                        held = held ?? sorted(store.groups.filter { !pinned.contains($0[0].id) }).map(\.[0].id)
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
        var rows: [String: CGRect] = [:]
        var top: CGFloat = 0
        var targets: [String: CGRect] = [:]
        var point: CGPoint?
        var scrolling = false
        /// The selected row, asked into view before the lazy stack made it.
        var wanted: String?
        /// One hover for the list: a hover region in each row costs every scroll frame a hit test of each (half the
        /// frames at 200 spaces). Each target observes its own light: one value all observe lights every made button
        /// again.
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

        func aim() {
            let point = scrolling ? nil : point.map { CGPoint(x: $0.x, y: $0.y + top) }
            pointer = point.flatMap { point in targets.first { $0.value.contains(point) }?.key }
        }
    }
}

private extension SidebarPage {
    /// While a space is dragged and none is pinned: the line's place, over the gap above the rows; a drop at the
    /// list's top (`RowsDrop.pinZone`) pins it.
    private var pinLine: some View {
        Rectangle().fill(drop.pinning ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.14)))
            .frame(height: drop.pinning ? 2 : 1)
            .padding(.horizontal, Sidebar.rowInsets.leading)
            .offset(y: -4)
            .allowsHitTesting(false)
            .accessibilityIdentifier("sidebar.pin-line")
    }

    private var spaceOrder: SpaceOrder {
        SpaceOrder(rawValue: windowOrder.wrappedValue) ?? settings.spaceOrder
    }

    /// Recent: the group whose agent changed state last first, held still under the pointer.
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
        if settings.showClosed {
            Button(opened.hasLine(page.archivedKey) ? "Hide Archived Sessions" : "Show Archived Sessions") {
                withAnimation(motion) {
                    opened = opened.togglingLine(page.archivedKey)
                }
            }
        }
        Divider()
        Button("Detach Session") { pages.close(page) }.disabled(!pages.canDetach)
    }

    var sortMenu: some View {
        Menu {
            Picker(
                "Sort Spaces",
                selection: Binding { spaceOrder } set: { windowOrder.wrappedValue = $0.rawValue }.animation(motion),
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
        .accessibilityValue(spaceOrder == .manual ? "Manual" : "Recent")
        .accessibilityIdentifier("sidebar.sort")
    }

    var motion: Animation? {
        Animation.reduced ? nil : .easeOut(duration: 0.2)
    }
}

@Observable
final class RowLight {
    var lit = false
}
