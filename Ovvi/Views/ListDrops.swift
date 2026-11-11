import HerdrKit
import SwiftUI

/// Its own tab's capsule is not a target: herdr refuses `same_tab`.
struct TrackDrop: DropDelegate {
    let tabs: [HostStore.Tab]
    let page: Page
    let slot: CGFloat
    @Binding var over: Int?
    @Binding var spring: Task<Void, Never>?
    let springLoad: (String) -> Void
    let land: (_ tab: String, _ offset: CGFloat, _ under: String) -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        switch page.dragging {
        case .pane: true
        case let .tab(id): tabs.contains { $0.id == id }
        default: false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // A late update after the drag ended.
        guard page.dragging != nil else { return nil }
        if let id = page.dragging?.paneID {
            let index = min(max(Int(info.location.x / max(slot, 1)), 0), tabs.count - 1)
            guard tabs.indices.contains(index), page.store.pane(id)?.tabID != tabs[index].id else {
                dropExited(info: info)
                return DropProposal(operation: .forbidden)
            }
            if over != index {
                withAnimation(.highlight) { over = index }
                spring?.cancel()
                let tabID = tabs[index].id
                spring = springTask(page) { springLoad(tabID) }
            }
        } else if case let .tab(id) = page.dragging, let from = tabs.firstIndex(where: { $0.id == id }) {
            let image = (info.location.x - DragSource.grabbed.x) / max(slot, 1)
            let place = min(max(Int(image.rounded()), 0), tabs.count - 1)
            // herdr inserts ahead of the tab at the index.
            let index = place >= from ? place + 1 : place
            if over != index {
                withAnimation(.slide) { over = index }
            }
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        spring?.cancel()
        withAnimation(page.dragging?.paneID == nil ? .slide : .highlight) { over = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        spring?.cancel()
        defer { over = nil }
        guard let over else { return false }
        switch page.dragging {
        case let .pane(id):
            // A snapshot during the drag may have closed tabs.
            guard tabs.indices.contains(over) else { return false }
            Task { await page.drop(id, on: .tab(tabs[over].id)) }
        case let .tab(id):
            guard let from = tabs.firstIndex(where: { $0.id == id }) else { return false }
            // herdr inserts ahead of the tab at the index; its own place or the next is no move.
            if over != from, over != from + 1 {
                // The new order shows in this same update, as the drag's slide ends: no slide back first.
                page.store.move(tab: id, to: over)
            }
            DragSource.land(page)
            let order = page.store.workspace(of: id)?.tabs.map(\.id) ?? [id]
            let place = order.firstIndex(of: id) ?? from
            land(id, info.location.x - DragSource.grabbed.x - CGFloat(place) * slot,
                 order[min(max(Int(info.location.x / max(slot, 1)), 0), order.count - 1)])
        default:
            return false
        }
        return true
    }
}

struct MenuRowDrop: ViewModifier {
    struct Target {
        let page: Page
        let destination: Destination
        /// It is there, hidden, through the whole drag: macOS 27 finds no drop target added after the drag entered the
        /// window.
        let shown: Bool
    }

    let target: Target?
    @State private var over = false

    func body(content: Content) -> some View {
        // Only during a drag: a drop target on the row at other times costs it the pointer's light (one CI run in two).
        if let target, target.page.dragging != nil {
            content
                .overlay {
                    if over {
                        DropIndicator(radius: 8)
                    }
                }
                .onDrop(of: [.ovviDrag], delegate: PaneDrop(
                    page: target.page, target: .move(target.destination), over: $over,
                    enabled: target.shown,
                ))
        } else {
            content
        }
    }
}

/// The place under the pinned spaces while a space is dragged: a drop there pins it, last of the pinned ones.
enum PinRegion {
    static let id = "sidebar.pin-region"
}

struct RowsDrop: DropDelegate {
    struct State {
        var over: String?
        var ghost = false
        /// A dragged space's place among `blocks`: before the one at it.
        var slot: Int?
        /// A dragged space over the pin region.
        var region = false
        var spring: Task<Void, Never>?
    }

    let page: Page
    let frames: SidebarPage.RowFrames
    @Binding var state: State
    let reorders: Bool
    /// The groups as the sidebar shows them: the pinned ones first, then the pin region (empty) while it shows.
    let shown: [[HostStore.Workspace]]
    let pinned: Set<String>
    let order: SpaceOrder
    let land: (_ rows: [String], _ offset: CGFloat) -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        switch page.dragging {
        case .pane, .tab: true
        case .workspace: reorders
        case nil: false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // A late update after the drag ended.
        guard page.dragging != nil else { return nil }
        let pointY = info.location.y + frames.top
        if case let .workspace(id) = page.dragging {
            let imageY = pointY - DragSource.grabbed.y + DragSource.size.height / 2
            let blocks = blocks(id)
            // The lazy stack makes the rows in view: one not made lies above them, or below.
            let made = blocks.firstIndex { rect($0) != nil } ?? 0
            let index = blocks.indices.count { index in rect(blocks[index]).map { $0.midY < imageY } ?? (index < made) }
            // By the pointer, wherever it holds the row.
            let region = blocks.contains(where: \.isEmpty) && frames.rows[PinRegion.id].map {
                ($0.minY - WorkspaceRow.gap / 2 ... $0.maxY + WorkspaceRow.gap / 2).contains(pointY)
            } == true
            let slot = region ? nil : place(id, index, blocks)
            if state.slot != slot || state.region != region {
                withAnimation(.slide) { (state.slot, state.region) = (slot, region) }
            }
            return DropProposal(operation: region || slot != nil ? .move : .forbidden)
        }
        let pane = page.dragging?.paneID != nil
        let ghost = pointY > frames.rows.values.map(\.maxY).max() ?? 0
        if ghost != state.ghost {
            withAnimation(.highlight) { state.ghost = ghost }
        }
        let home: HostStore.Workspace? = if case let .tab(id) = page.dragging {
            page.store.workspace(of: id)
        } else {
            nil
        }
        let row = state.ghost ? nil : page.store.workspaces.first { workspace in
            frames.rows[workspace.id].map { pointY >= $0.minY && pointY < $0.maxY + 2 } ?? false && workspace !== home
        }
        if row?.id != state.over {
            withAnimation(.highlight) { state.over = row?.id }
            state.spring?.cancel()
            if let row, pane {
                state.spring = springTask(page) { page.select(row) }
            }
        }
        return DropProposal(operation: row == nil && !state.ghost ? .forbidden : .move)
    }

    func dropExited(info _: DropInfo) {
        state.spring?.cancel()
        withAnimation(state.slot == nil ? .highlight : .slide) { state = State() }
    }

    func performDrop(info: DropInfo) -> Bool {
        let dropped = state
        // Where the dragged row shows now, ahead of the slide's end.
        let now: CGFloat = if case let .workspace(id) = page.dragging {
            (frames.rows[id]?.minY ?? 0) + shift(id)
        } else {
            0
        }
        state.spring?.cancel()
        state = State()
        switch page.dragging {
        case let .pane(id):
            guard let target: DropTarget = dropped.ghost ? .move(.newWorkspace())
                : dropped.over.map({ .move(.newTab(workspaceID: $0)) }) else { return false }
            Task { await page.drop(id, on: target) }
        case let .tab(id):
            guard dropped.ghost || dropped.over != nil else { return false }
            Task { await page.drop(tab: id, on: dropped.over) }
        case let .workspace(id):
            let blocks = blocks(id)
            guard let from = blocks.firstIndex(where: { $0.contains { $0.id == id } }),
                  let slot = dropped.region ? blocks.firstIndex(where: \.isEmpty) : dropped.slot else { return false }
            if shown.contains(where: { $0.first?.id == id }) {
                dropSpace(blocks, from: from, slot: slot)
            } else if slot != from, slot != from + 1 {
                // Its own place or the next is no move.
                page.store.move(workspaces: blocks[from].map(\.id), before: before(slot, blocks))
            }
            DragSource.land(page)
            // As a tab's capsule: from the drop's image into its place, while the other rows move as for any order.
            land(blocks[from].map(\.id), info.location.y + frames.top - DragSource.grabbed.y - now)
        default:
            return false
        }
        return true
    }

    /// A space's slot: on its own side when the pin region does not show (Show Only Pinned Spaces); nil for an unpinned
    /// space among the
    /// unpinned ones in Recent, which orders them itself; a pinned one dropped there goes where Recent puts it, so its
    /// gap opens first of them.
    private func place(_ id: String, _ index: Int, _ blocks: [[HostStore.Workspace]]) -> Int? {
        guard shown.contains(where: { $0.first?.id == id }) else { return index }
        guard let region = blocks.firstIndex(where: \.isEmpty) else {
            let pins = blocks.count { pinned.contains($0[0].id) }
            return pinned.contains(id) ? min(index, pins) : order == .recent ? nil : max(index, pins)
        }
        guard index > region, order == .recent else { return index }
        return pinned.contains(id) ? region + 1 : nil
    }

    /// Pinned or not by its side of the pin region, then before the next of that side, which herdr may hold anywhere;
    /// last of the pinned ones, right after the last (not at herdr's end); unpinned in Recent, where Recent puts it.
    private func dropSpace(_ blocks: [[HostStore.Workspace]], from: Int, slot: Int) {
        let id = blocks[from][0].id, place = slot > from ? slot - 1 : slot
        var list = blocks
        list.insert(list.remove(at: from), at: place)
        let pinning = list.firstIndex(where: \.isEmpty).map { place < $0 } ?? pinned.contains(id)
        if pinning != pinned.contains(id) {
            page.togglePin(id)
        }
        guard slot != from, slot != from + 1, pinning || order == .manual else { return }
        var before = list.indices.contains(place + 1) ? list[place + 1].first.flatMap {
            pinned.contains($0.id) == pinning ? $0.id : nil
        } : nil
        if before == nil, pinning {
            // The only pinned one keeps herdr's place.
            guard place > 0, let last = list[place - 1].first?.id else { return }
            let groups = page.store.groups.filter { $0[0].id != id }
            guard let after = groups.firstIndex(where: { $0[0].id == last }),
                  page.store.groups.firstIndex(where: { $0[0].id == id }) != after + 1 else { return }
            before = groups.indices.contains(after + 1) ? groups[after + 1][0].id : nil
        }
        page.store.move(workspaces: blocks[from].map(\.id), before: before)
    }

    /// How far a row, or the pin region, moves for the dragged one's gap: its place in the list as the drop would leave
    /// it, less its place now.
    func shift(_ id: String) -> CGFloat {
        guard case let .workspace(dragged) = page.dragging, let slot = state.slot else { return 0 }
        let blocks = blocks(dragged)
        guard let from = blocks.firstIndex(where: { $0.contains { $0.id == dragged } }),
              let index = blocks.firstIndex(where: { id == PinRegion.id ? $0.isEmpty : $0.contains { $0.id == id } })
        else { return 0 }
        var list = Array(blocks.indices)
        list.remove(at: from)
        // A snapshot during the drag may have closed workspaces.
        list.insert(from, at: min(slot > from ? slot - 1 : slot, list.count))
        let top = { (order: [Int]) in order.prefix { $0 != index }.map { height(blocks[$0]) }.reduce(0, +) }
        return top(list) - top(Array(blocks.indices))
    }

    /// A worktree's: its repository's other worktrees; else the spaces as the sidebar shows them.
    private func blocks(_ id: String) -> [[HostStore.Workspace]] {
        let groups = page.store.groups
        if let group = groups.first(where: { $0.dropFirst().contains { $0.id == id } }) {
            return group.dropFirst().map { [$0] }
        }
        return shown
    }

    /// A block's rows, or the pin region's, as laid out (before any slide).
    private func rect(_ block: [HostStore.Workspace]) -> CGRect? {
        block.isEmpty ? frames.rows[PinRegion.id]
            : block.compactMap { frames.rows[$0.id] }.reduce(CGRect?.none) { $0?.union($1) ?? $1 }
    }

    /// A block's rows with the gap after each: how far the others move for it.
    private func height(_ block: [HostStore.Workspace]) -> CGFloat {
        guard !block.isEmpty else { return (frames.rows[PinRegion.id]?.height ?? 0) + WorkspaceRow.gap }
        return block.compactMap { frames.rows[$0.id]?.height }.reduce(0, +) + WorkspaceRow.gap * CGFloat(block.count)
    }

    private func before(_ slot: Int, _ blocks: [[HostStore.Workspace]]) -> String? {
        if blocks.indices.contains(slot) {
            return blocks[slot].first?.id
        }
        let all = page.store.workspaces
        guard let last = blocks.last?.last, page.store.parent(of: last) != nil,
              let index = all.firstIndex(where: { $0 === last }), all.indices.contains(index + 1)
        else { return nil }
        return all[index + 1].id
    }
}

extension Page {
    func drop(_ paneID: String, on target: DropTarget) async {
        guard let pane = store.pane(paneID) else { return }
        let terminalID = pane.terminalID
        switch target {
        case let .card(targetID, nil):
            await store.swap(paneID, with: targetID)
            go(to: pane)
        case let .card(targetID, edge?):
            guard let tabID = store.pane(targetID)?.tabID else { return }
            await follow(store.place(paneID, in: tabID, beside: targetID, edge), terminalID)
        case let .tab(tabID):
            await follow(store.place(paneID, in: tabID), terminalID)
        case let .move(destination):
            await move(pane, to: destination)
        }
    }

    func drop(tab tabID: String, on workspaceID: String?) async {
        let keyboard = keyboardCard(tabID)
        let moved = await store.move(tab: tabID, to: workspaceID)
        let pane = moved.first { $0.old == keyboard?.id }?.new ?? moved.first?.new
        follow(pane, pane?.terminalID)
    }
}
