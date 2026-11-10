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
        var spring: Task<Void, Never>?
    }

    let page: Page
    let frames: SidebarPage.RowFrames
    @Binding var state: State
    let reorders: Bool
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
            let imageY = pointY - DragSource.grabbed.y + (frames.rows[id]?.height ?? 0) / 2
            let blocks = blocks(id)
            // The lazy stack makes the rows in view: one not made lies above them, or below.
            let made = blocks.firstIndex { middle($0) != nil } ?? 0
            let index = blocks.indices.count { index in middle(blocks[index]).map { $0 < imageY } ?? (index < made) }
            if state.slot != index {
                withAnimation(.slide) { state.slot = index }
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

    func performDrop(info: DropInfo) -> Bool {
        let shifted = page.dragging.flatMap { dragging in
            if case let .workspace(id) = dragging {
                (frames.rows[id]?.minY ?? 0) + shift(id)
            } else {
                nil
            }
        }
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
            guard let slot = dropped.slot, let shifted,
                  let from = blocks.firstIndex(where: { $0.contains { $0.id == id } }) else { return false }
            // Its own place or the next is no move. The new order shows in this same update, as the slide ends.
            if slot != from, slot != from + 1 {
                page.store.move(workspaces: blocks[from].map(\.id), before: before(slot, blocks))
            }
            DragSource.land(page)
            land(blocks[from].map(\.id), info.location.y + frames.top - DragSource.grabbed.y - shifted)
        default:
            return false
        }
        return true
    }

    func shift(_ id: String) -> CGFloat {
        guard case let .workspace(dragged) = page.dragging, let slot = state.slot else { return 0 }
        let blocks = blocks(dragged)
        guard let from = blocks.firstIndex(where: { $0.contains { $0.id == dragged } }),
              let index = blocks.firstIndex(where: { $0.contains { $0.id == id } }) else { return 0 }
        // A snapshot during the drag may have closed workspaces.
        let place = min(slot > from ? slot - 1 : slot, blocks.count - 1)
        if index == from {
            return place > from ? blocks[from + 1 ... place].map(height).reduce(0, +)
                : -blocks[place ..< from].map(height).reduce(0, +)
        }
        return from < index && index <= place ? -height(blocks[from])
            : place <= index && index < from ? height(blocks[from]) : 0
    }

    private func blocks(_ id: String) -> [[HostStore.Workspace]] {
        let groups = page.store.groups
        if let group = groups.first(where: { $0.dropFirst().contains { $0.id == id } }) {
            return group.dropFirst().map { [$0] }
        }
        return groups
    }

    private func height(_ block: [HostStore.Workspace]) -> CGFloat {
        block.compactMap { frames.rows[$0.id]?.height }.reduce(0, +) + 2 * CGFloat(block.count)
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
