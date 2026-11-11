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

struct RowsDrop: DropDelegate {
    struct State {
        var over: String?
        var ghost = false
        var slot: Int?
        /// A space's drop lands among the pinned ones: above the line under them.
        var pinning = false
        var spring: Task<Void, Never>?
    }

    let page: Page
    let frames: SidebarPage.RowFrames
    @Binding var state: State
    let reorders: Bool
    /// The groups as the sidebar shows them, the pinned ones first.
    let shown: [[HostStore.Workspace]]
    let pinned: Set<String>
    let order: SpaceOrder

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
            let imageY = pointY - DragSource.grabbed.y + (frames.rows[id]?.height ?? 0) / 2
            let blocks = blocks(id)
            // The lazy stack makes the rows in view: one not made lies above them, or below.
            let made = blocks.firstIndex { middle($0) != nil } ?? 0
            let index = blocks.indices.count { index in middle(blocks[index]).map { $0 < imageY } ?? (index < made) }
            guard let (index, pinning) = shown.contains(where: { $0[0].id == id })
                ? section(id, index, pinning(pointY, imageY, blocks), blocks) : (index, false)
            else {
                if state.slot != nil || state.pinning {
                    withAnimation(.slide) { (state.slot, state.pinning) = (nil, false) }
                }
                return DropProposal(operation: .forbidden)
            }
            if state.slot != index || state.pinning != pinning {
                withAnimation(.slide) { (state.slot, state.pinning) = (index, pinning) }
            }
            return DropProposal(operation: .move)
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

    func performDrop(info _: DropInfo) -> Bool {
        let dropped = state
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
            guard let slot = dropped.slot,
                  let from = blocks.firstIndex(where: { $0.contains { $0.id == id } }) else { return false }
            let moves = slot != from && slot != from + 1
            if shown.contains(where: { $0[0].id == id }) {
                dropSpace(blocks, from: from, slot: slot, pinning: dropped.pinning, moves: moves)
            } else if moves {
                // Its own place or the next is no move. The new order shows in this same update, as the slide ends.
                page.store.move(workspaces: blocks[from].map(\.id), before: before(slot, blocks))
            }
            // No glide: AppKit's drag loop draws no animation frame for 0.3–0.5 s after a drop, so a glide showed as a
            // still frame and a jump. The row is already in the gap the slide opened.
            DragSource.land(page)
        default:
            return false
        }
        return true
    }

    /// A space's slot kept on its side of the line, and whether that side is the pinned one; nil for an unpinned space
    /// dropped among the unpinned ones in Recent, which orders them itself.
    private func section(_ id: String, _ index: Int, _ pinning: Bool,
                         _ blocks: [[HostStore.Workspace]]) -> (Int, Bool)?
    {
        let pins = blocks.prefix { pinned.contains($0[0].id) }.count
        guard order == .recent, !pinning else { return (pinning ? min(index, pins) : max(index, pins), pinning) }
        // Unpinned, it goes where Recent puts it: the gap opens under the pinned ones.
        return pinned.contains(id) ? (pins, false) : nil
    }

    /// With none pinned, a drop with the pointer this far into the list pins.
    static let pinZone: CGFloat = 8

    /// Pinned or not by where it lands, then before the next of that section, which herdr may hold anywhere; last of
    /// the pinned ones, right after the last (not at herdr's end); unpinned in Recent, where Recent puts it.
    private func dropSpace(_ blocks: [[HostStore.Workspace]], from: Int, slot: Int, pinning: Bool, moves: Bool) {
        let id = blocks[from][0].id, pins = pinning != pinned.contains(id)
        if pins {
            page.togglePin(id)
        }
        guard pins || moves, pinning || order == .manual else { return }
        var rest = blocks
        rest.remove(at: from)
        let section = rest.filter { pinned.contains($0[0].id) == pinning }
        let place = (slot > from ? slot - 1 : slot) - (pinning ? 0 : rest.count - section.count)
        var before = section.indices.contains(place) ? section[place][0].id : nil
        if before == nil, pinning {
            let groups = page.store.groups.filter { $0[0].id != id }
            guard let last = section.last?[0].id, let after = groups.firstIndex(where: { $0[0].id == last }),
                  page.store.groups.firstIndex(where: { $0[0].id == id }).map({ $0 != after + 1 }) ?? true
            else { return }
            before = groups.indices.contains(after + 1) ? groups[after + 1][0].id : nil
        }
        page.store.move(workspaces: blocks[from].map(\.id), before: before)
    }

    func shift(_ id: String) -> CGFloat {
        guard case let .workspace(dragged) = page.dragging, let slot = state.slot else { return 0 }
        let blocks = blocks(dragged)
        guard let from = blocks.firstIndex(where: { $0.contains { $0.id == dragged } }),
              let index = blocks.firstIndex(where: { $0.contains { $0.id == id } }) else { return 0 }
        // A snapshot during the drag may have closed workspaces.
        let place = min(slot > from ? slot - 1 : slot, blocks.count - 1)
        let gap = lineGap(blocks[index][0].id, dragged)
        if index == from {
            return gap + (place > from ? blocks[from + 1 ... place].map(height).reduce(0, +)
                : -blocks[place ..< from].map(height).reduce(0, +))
        }
        return gap + (from < index && index <= place ? -height(blocks[from])
            : place <= index && index < from ? height(blocks[from]) : 0)
    }

    /// What the line's gap (under the last pinned group, while unpinned ones follow) adds to a group's move when the
    /// drop pins or unpins: the unpinned ones lose it when no pinned one stays, or gain it with the first.
    private func lineGap(_ head: String, _ dragged: String) -> CGFloat {
        let was = pinned.contains(dragged), will = state.pinning
        guard was != will, shown.contains(where: { $0[0].id == dragged }) else { return 0 }
        let others = shown.count { pinned.contains($0[0].id) && $0[0].id != dragged }
        let rest = shown.count - 1 - others
        let before = others + (was ? 1 : 0) > 0 && rest + (was ? 0 : 1) > 0
        let after = others + (will ? 1 : 0) > 0 && rest + (will ? 0 : 1) > 0
        let gap = WorkspaceRow.gap
        if head == dragged {
            return (!will && after ? gap : 0) - (!was && before ? gap : 0)
        }
        return pinned.contains(head) ? 0 : (after ? gap : 0) - (before ? gap : 0)
    }

    /// A worktree's: its repository's other worktrees; else the spaces pinned like it, as the sidebar shows them.
    private func blocks(_ id: String) -> [[HostStore.Workspace]] {
        let groups = page.store.groups
        if let group = groups.first(where: { $0.dropFirst().contains { $0.id == id } }) {
            return group.dropFirst().map { [$0] }
        }
        return shown
    }

    /// Whether a drop lands above the line under the pinned spaces (the dragged row's middle above it); with none
    /// pinned, whether the pointer is within `pinZone` of the list's top, where the line stands while a space is
    /// dragged: the pointer cannot go above the list.
    private func pinning(_ pointY: CGFloat, _ imageY: CGFloat, _ blocks: [[HostStore.Workspace]]) -> Bool {
        let pins = blocks.prefix { pinned.contains($0[0].id) }.count
        guard pins > 0 else {
            return pointY < (blocks.first?.compactMap { frames.rows[$0.id]?.minY }.min() ?? -.infinity) + Self.pinZone
        }
        let bottom = blocks[pins - 1].compactMap { frames.rows[$0.id]?.maxY }.max() ?? -.infinity
        let top = blocks.indices.contains(pins) ? blocks[pins].compactMap { frames.rows[$0.id]?.minY }.min() : nil
        return imageY < top.map { (bottom + $0) / 2 } ?? bottom + WorkspaceRow.gap
    }

    /// A block's rows with the gap after each: how far the others move for it.
    private func height(_ block: [HostStore.Workspace]) -> CGFloat {
        block.compactMap { frames.rows[$0.id]?.height }.reduce(0, +) + WorkspaceRow.gap * CGFloat(block.count)
    }

    private func middle(_ block: [HostStore.Workspace]) -> CGFloat? {
        let rows = block.compactMap { frames.rows[$0.id] }
        guard let top = rows.map(\.minY).min(), let bottom = rows.map(\.maxY).max() else { return nil }
        return (top + bottom) / 2
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
