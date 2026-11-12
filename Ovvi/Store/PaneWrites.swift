import Foundation
import HerdrKit

extension HostStore {
    /// herdr splits only right and down, so a swap puts the new pane first, and halves the split pane, 50 / 25 / 25:
    /// with Balance splits on, the run is evened after, 33 / 33 / 33.
    /// The pane may be an earlier split's stand-in: its write, ahead of this one, makes herdr's.
    func split(_ paneID: String, _ direction: SplitNode.Direction, before: Bool,
               standIn: String) async -> HerdrKit.Pane?
    {
        // herdr's pane may still show as its stand-in, until the snapshot after its split.
        let shown = ahead.splitPanes.first { $0.value == paneID }?.key ?? paneID
        let tab = workspaces.flatMap(\.tabs).first { $0.tree?.paneIDs.contains(shown) == true }
        if let tab, let tree = tab.tree {
            ahead.layout = Ahead.NewLayout(tabID: tab.id, pane: standIn, tree: tree.split(
                shown, direction, new: standIn, before: before, even: Self.balances,
            ))
            redraw()
        }
        // herdr's `handle_pane_split` (src/app/api/panes.rs) starts it in the split pane's folder; an earlier split's
        // stand-in has its chooser's.
        let source = ahead.splitPanes[paneID] ?? paneID
        let chooser = choose(standIn: standIn, cwd: pane(source)?.cwd ?? chooser(paneID)?.cwd)
        var made: HerdrKit.Pane?, closedLate = false
        let done = await write { client in
            let paneID = ahead.splitPanes[paneID] ?? paneID
            // ponytail: a header × on an earlier stand-in herdr has not made drops the quick splits of it (with
            // herdr's error as the notice when it closes as herdr makes it); split the closed card's own target if
            // that window (under a second) ever matters.
            guard !Ahead.isStandIn(paneID), !ahead.closing.contains(standIn),
                  let new = try await client.split(paneID, direction, cwd: nil) else { return }
            // Hidden while the split settles: a snapshot read ahead of the split has no such pane, and one read ahead
            // of the close has it.
            if ahead.closing.contains(standIn) {
                closedLate = true
                ahead.splitPanes[standIn] = new.id
                ahead.closing.insert(new.id)
                do {
                    try await client.close(pane: new.id)
                } catch {
                    ahead.closing.remove(new.id)
                    throw error
                }
                return
            }
            made = new
            chooser.made(new)
            // Here, not after `write`: the next write may start first.
            ahead.splitPanes[standIn] = new.id
            if before {
                try await client.swap(paneID, direction == .right ? .right : .down)
            }
            try await opened(new, client)
        }
        // With no pane, the stand-in goes at once: an idle session may never send two more snapshots.
        if made == nil {
            drop(chooser)
        }
        if ahead.layout?.pane == standIn {
            ahead.layout?.after = closedLate ? 1 : 0
            if !done || made == nil && !closedLate {
                ahead.layout = nil
                redraw()
            }
        }
        return made
    }

    /// Inside a write: herdr's tree, which the writes ahead of it change.
    func balance(_ tabID: String, _ client: any Multiplexer, around paneID: String? = nil) async throws {
        guard let tree = try await client.snapshot().trees[tabID] else { return }
        for change in paneID.map({ tree.evened(around: $0) }) ?? tree.evened() {
            try await client.setRatio(tab: tabID, path: change.path, ratio: change.ratio)
        }
    }

    func setRatio(tab tabID: String, path: [Bool], ratio: Double) async -> Bool {
        await write { try await $0.setRatio(tab: tabID, path: path, ratio: ratio) }
    }

    func resize(_ paneID: String, _ heading: Heading) async {
        await write { try await $0.resize(paneID, heading, amount: 0.05) }
    }

    func swap(_ paneID: String, _ heading: Heading) async {
        await write { try await $0.swap(paneID, heading) }
    }

    func swap(_ paneID: String, with targetID: String) async {
        await write { try await $0.swap(paneID, with: targetID) }
    }

    /// With no target herdr would split the tab's focused pane. herdr splits only right or down, so a left or top edge
    /// swaps after; it refuses a move into the pane's own tab, so the pane goes to a new tab first.
    func place(_ paneID: String, in tabID: String, beside targetID: String? = nil,
               _ edge: Heading = .right) async -> HerdrKit.Pane?
    {
        var placed: HerdrKit.Pane?
        let targetID = targetID ?? tab(tabID)?.tree?.paneIDs.last
        await write { client in
            var id = paneID, done: String?
            do {
                if pane(paneID)?.tabID == tabID, let workspaceID = workspace(of: tabID)?.id {
                    guard let away = try await client.move(pane: id, to: .newTab(workspaceID: workspaceID))
                    else { throw HerdrError.failed("herdr named no pane") }
                    id = away.id
                    done = "Moved the pane to a new tab"
                }
                let split: SplitNode.Direction = edge == .left || edge == .right ? .right : .down
                guard let moved = try await client.move(pane: id, to: .tab(tabID, beside: targetID, split: split))
                else { throw HerdrError.failed("herdr named no pane") }
                placed = moved
                if let targetID, edge == .left || edge == .up {
                    done = "Moved the pane beside the card"
                    try await client.swap(moved.id, with: targetID)
                }
                done = nil
                try await opened(moved, client)
            } catch {
                throw done.map { HerdrError.failed("\($0): herdr refused the next step") } ?? error
            }
        }
        return placed
    }

    /// A move to another workspace gives the pane a new id.
    func move(_ paneID: String, to destination: Destination) async -> HerdrKit.Pane? {
        var moved: HerdrKit.Pane?
        await write { moved = try await $0.move(pane: paneID, to: destination) }
        return moved
    }

    /// herdr 0.9.5's `tab.move` stays inside a workspace, so the panes move one by one (`SplitNode.rebuild`), each to a
    /// new pane id. The tree is herdr's when the write's turn comes: a write ahead of it may change the tab.
    func move(tab tabID: String, to workspaceID: String?) async -> [(old: String, new: HerdrKit.Pane)] {
        guard let tab = tab(tabID),
              tab.tree?.paneIDs.contains(where: Ahead.isStandIn) == false else { return [] }
        let label = tab.label.allSatisfy(\.isNumber) ? nil : tab.label
        var moved: [(old: String, new: HerdrKit.Pane)] = []
        await write { client in
            guard let tree = try await client.snapshot().trees[tabID]
            else { throw HerdrError.failed("herdr has no such tab") }
            do {
                guard let first = try await client.move(pane: tree.paneIDs[0], to: workspaceID.map {
                    .newTab(workspaceID: $0, label: label)
                } ?? .newWorkspace(tabLabel: label))
                else { throw HerdrError.failed("herdr named no pane") }
                moved = [(tree.paneIDs[0], first)]
                for step in tree.rebuild {
                    guard let beside = moved.first(where: { $0.old == step.beside })?.new.id,
                          let pane = try await client.move(
                              pane: step.paneID,
                              to: .tab(first.tabID, beside: beside, split: step.direction, ratio: step.ratio),
                          ) else { throw HerdrError.failed("herdr named no pane") }
                    moved.append((step.paneID, pane))
                }
            } catch {
                throw moved.isEmpty ? error : HerdrError.failed("Moved part of the tab: herdr refused the next step")
            }
        }
        return moved
    }

    func rename(pane paneID: String, label: String) async {
        let label = label.trimmingCharacters(in: .whitespaces)
        guard label != pane(paneID)?.label ?? "" else { return }
        await write { try await $0.rename(pane: paneID, label: label.isEmpty ? nil : label) }
    }

    func move(tab tabID: String, by offset: Int) {
        guard let tabs = workspace(of: tabID)?.tabs, let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs.indices.contains(index + offset) else { return }
        // herdr inserts ahead of the tab at the index, so one place right is two on.
        move(tab: tabID, to: index + (offset > 0 ? 2 : -1))
    }

    func move(tab tabID: String, to index: Int) {
        // herdr has no such tab yet.
        guard !Ahead.isStandIn(tabID) else { return }
        var asked: [String]?
        if let workspace = workspace(of: tabID) {
            var ids = workspace.tabs.map(\.id).filter { !Ahead.isStandIn($0) }
            if let from = ids.firstIndex(of: tabID) {
                ids.remove(at: from)
                ids.insert(tabID, at: min(from < index ? index - 1 : index, ids.count))
                ahead.order = Ahead.NewOrder(workspaceID: workspace.id, ids: ids)
                ahead.beside.removeAll { $0.workspaceID == workspace.id }
                asked = ids
                redraw()
            }
        }
        Task {
            let done = await write { try await $0.move(tab: tabID, to: index) }
            // Not a later move's order.
            guard let asked, ahead.order?.ids == asked else { return }
            ahead.order?.after = 0
            if !done {
                ahead.order = nil
                redraw()
            }
        }
    }

    /// One place up or down among `groups`: the sidebar's pinned or unpinned ones.
    func move(workspace workspaceID: String, by offset: Int, in groups: [[Workspace]]) {
        guard let index = groups.firstIndex(where: { $0.first?.id == workspaceID }),
              groups.indices.contains(index + offset) else { return }
        let before = offset < 0 ? groups[index - 1].first?.id : groups.indices.contains(index + 2)
            ? groups[index + 2].first?.id : nil
        move(workspaces: groups[index].map(\.id), before: before)
    }

    func move(workspaces workspaceIDs: [String], before workspaceID: String?) {
        var ids = workspaces.map(\.id).filter { !workspaceIDs.contains($0) }
        ids.insert(contentsOf: workspaceIDs, at: workspaceID.flatMap(ids.firstIndex) ?? ids.count)
        let asked = ids
        ahead.rows = Ahead.NewOrder(workspaceID: nil, ids: ids)
        redraw()
        Task {
            let done = await write { try await $0.move(workspaces: workspaceIDs, before: workspaceID) }
            // Not a later move's order.
            guard ahead.rows?.ids == asked else { return }
            ahead.rows?.after = 0
            if !done {
                ahead.rows = nil
                redraw()
            }
        }
    }
}

extension Page {
    var standIn: String? {
        selectedTab.flatMap { Ahead.isStandIn($0.id) ? $0.id : nil }
    }

    func close(_ close: HostStore.Close, discarded: Set<String> = []) {
        // herdr's pane for a split's stand-in, which still shows under the stand-in's id: herdr's is closed.
        let close = close.paneID.flatMap { store.ahead.splitPanes[$0] }.map(HostStore.Close.pane) ?? close
        // The same close again (a second ⇧⌘W while herdr is asked) would ask twice; another close goes on.
        let key = String(describing: close)
        // A pane a running replace takes: herdr closes it already.
        guard !asking.contains(key), close.paneID.flatMap({ store.ahead.replacing[$0] }) == nil else { return }
        // ponytail: it steps back ahead of a question too, so a cancelled one leaves the prior card lit; a split card
        // runs only its shell that soon.
        if let id = close.paneID, id == newest.map({ store.ahead.splitPanes[$0.id] ?? $0.id }) {
            closedNewest()
        }
        let before = (selectedWorkspaceID, selectedTabIDs)
        if let (pane, card) = store.panes(closedBy: close).lazy.compactMap({ pane in
            pane.terminalID.flatMap { self.terminals.plugins[$0] }.map { (pane, $0) }
        }).first(where: { $0.1.web.dirty && !discarded.contains($0.1.terminalID) }) {
            if !floats(pane), let workspace = store.workspace(of: pane.tabID) {
                select(workspace, tab: pane.tabID)
            }
            let shown = (selectedWorkspaceID, selectedTabIDs)
            return card.leave { [weak self] card in
                guard let self else { return }
                if selectedWorkspaceID == shown.0, selectedTabIDs == shown.1 {
                    (selectedWorkspaceID, selectedTabIDs) = before
                }
                self.close(close, discarded: discarded.union([card.terminalID]))
            }
        }
        guard let asked = store.ask(close) else { return }
        let hidden = (selectedWorkspaceID, selectedTabIDs)
        asking.insert(key)
        Task {
            // Only a question writes the dialog: a close that asks nothing leaves another close's dialog up.
            if let asked = await asked.value {
                closing = asked
                if selectedWorkspaceID == hidden.0, selectedTabIDs == hidden.1 {
                    (selectedWorkspaceID, selectedTabIDs) = before
                }
            }
            asking.remove(key)
        }
    }

    func split(_ paneID: String, _ direction: SplitNode.Direction, before: Bool = false) async {
        Latency.shared.split()
        zoomedPaneID = nil
        // ⌘D can read the keyboard card ahead of the snapshot that makes the prior split's pane it.
        let target = newest.flatMap { newest in
            let old = store.pane(paneID)?.terminalID.map { $0 == newest.from } == true
            return paneID == keyboardPane?.id || old ? newest.id : nil
        } ?? paneID
        if let newest {
            // A claim the prior split's pane made would end this split's turn on landing (`tookKeyboard`).
            movedTerminal = nil
            keyboardTabID = selectedTab?.id
            if let from = newest.from {
                terminals.focus(from)
            }
        }
        let standIn = Ahead.standIn()
        splitsBefore = newest.map { splitsBefore + [$0.id] } ?? []
        newest = (standIn, newest?.from ?? terminals.keyboardTerminalID)
        let new = await store.split(target, direction, before: before, standIn: standIn)
        guard newest?.id == standIn else {
            if let new {
                splitsBefore = splitsBefore.map { $0 == standIn ? new.id : $0 }
                new.terminalID.map(use)
            }
            return
        }
        newest = new.map { ($0.id, newest?.from) }
        follow(new, new?.terminalID, select: false)
    }

    func closePane(_ pane: HostStore.Pane?) {
        let lit = newest.flatMap { store.pane($0.id) == nil && pane?.id == keyboardPane?.id ? $0.id : nil }
        if let id = lit ?? pane?.id ?? standIn {
            close(.pane(id))
        }
    }

    private func closedNewest() {
        guard let newest else { return }
        let shown = selectedTab?.tree?.paneIDs ?? []
        var id: String?
        while id == nil, let before = splitsBefore.popLast() {
            let pane = store.ahead.splitPanes[before] ?? before
            id = shown.contains { $0 == pane || store.ahead.splitPanes[$0] == pane } ? pane : nil
        }
        self.newest = id.map { ($0, newest.from) }
        guard let id, !Ahead.isStandIn(id) else { return }
        if let pane = store.pane(id), shown.contains(id) {
            go(to: pane)
        } else {
            store.pane(id)?.terminalID.map(use)
            keyboardTabID = nil
        }
    }
}

extension Page {
    func closeTabs(besides tabID: String, right: Bool) {
        guard let tabs = store.workspace(of: tabID)?.tabs.map(\.id), let index = tabs.firstIndex(of: tabID)
        else { return }
        let others = right ? Array(tabs[(index + 1)...]) : tabs.filter { $0 != tabID }
        if !others.isEmpty {
            close(.otherTabs(others, right: right))
        }
    }
}
