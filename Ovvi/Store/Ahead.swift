import Foundation
import HerdrKit

struct Ahead {
    /// Split stand-ins stay while a split shows: the latest split's tree has the earlier ones. herdr never gives a
    /// closed id to a new one while its server runs.
    var closing: Set<String> = []
    /// In the order asked.
    var tabs: [NewTab] = []
    /// A split or a close in one tab, shown ahead of herdr, its run evened as the write will even it.
    var layout: NewLayout?
    var splitPanes: [String: String] = [:]
    var arrived: [String: String] = [:]
    /// Not every starting pane: one another client made may run a program already.
    var fresh: Set<String> = []
    var toClose: [String] = []
    var replacing: [String: Replacing] = [:]
    var replaced: [String: Replacing] = [:]
    var cards: [String: String] = [:]
    var order: NewOrder?
    var rows: NewOrder?
    var beside: [Beside] = []
    var moving: [Moving] = []

    struct NewTab {
        let id: String, workspaceID: String
        var known: Set<String>
        var closed = false
        var made: String?
    }

    struct NewLayout {
        /// The split's stand-in, or the closed pane.
        let tabID: String, pane: String, tree: SplitNode
        var after: Int?
    }

    static func standIn() -> String {
        "new.\(UUID().uuidString)"
    }

    static func isStandIn(_ id: String) -> Bool {
        id.hasPrefix("new.")
    }

    /// No other stand-in may take the tab.
    mutating func made(_ standIn: String, _ id: String) {
        arrived[standIn] = id
        fresh.insert(id)
        if tabs.first(where: { $0.id == standIn })?.closed == true {
            closing.insert(id)
            toClose.append(id)
        }
        tabs.removeAll { $0.id == standIn }
        for index in tabs.indices {
            tabs[index].known.insert(id)
        }
        for index in beside.indices {
            beside[index].known.insert(id)
        }
    }

    struct Shown {
        var workspaces: [Workspace]
        var tabs: [Tab]
        var panes: [HerdrKit.Pane]
        var trees: [String: SplitNode]
    }

    mutating func show(_ snapshot: Snapshot) -> Shown {
        let ids = Set(snapshot.workspaces.map(\.id) + snapshot.tabs.map(\.id) + snapshot.panes.map(\.id))
        forget(ids)
        arrived = [:]
        replaced = replacing.filter { !ids.contains($0.key) }
        keepCards(ids)
        replacing = replacing.filter { ids.contains($0.key) }
        let hidden = hidden(snapshot.panes)
        tabs.removeAll { standIn in !snapshot.workspaces.contains { $0.id == standIn.workspaceID } }
        for id in tabs.map(\.id) {
            // Read again: `made` adds to the others' known tabs.
            guard let standIn = tabs.first(where: { $0.id == id }), let tab = snapshot.tabs.first(where: { tab in
                standIn.made.map { $0 == tab.id }
                    ?? (tab.workspaceID == standIn.workspaceID && !standIn.known.contains(tab.id)
                        && snapshot.panes.contains { $0.tabID == tab.id && !hidden.contains($0.id) })
            }) else { continue }
            made(id, tab.id)
        }
        var trees = snapshot.trees.compactMapValues { $0.removing(hidden) }
        if let layout {
            let now = snapshot.trees[layout.tabID]
            let shown = layout.tree.removing(closing.union(splitPanes.filter { closing.contains($0.value) }.keys))
            // After the write, herdr's tree takes over once it places the panes where the split shows them: one read
            // ahead of the swap or the balance would move the cards a second time. Else the second snapshot after the
            // write (reads are serial: at most one began before the write's end): herdr may keep a ratio its own way,
            // or another client changed the tab. Not during the write: a stand-in closed meanwhile stays in `closing`
            // only while the split lives.
            let same = trees[layout.tabID].flatMap { now in shown?.places(like: now, renaming: splitPanes) } == true
            if now == nil || layout.after.map({ $0 > 0 || same }) == true {
                self.layout = nil
            } else {
                trees[layout.tabID] = shown
                self.layout?.after = layout.after.map { $0 + 1 }
            }
        }
        if layout == nil {
            splitPanes = [:]
        }
        // herdr closes a tab with its last pane, and a workspace with its last tab.
        let emptied = Set(snapshot.trees.keys).subtracting(trees.keys)
        var tabs = snapshot.tabs.filter {
            !closing.contains($0.id) && !closing.contains($0.workspaceID) && !emptied.contains($0.id)
        }
        let space = order?.workspaceID
        tabs = placed(Self.ordered(tabs, by: &order, id: \.id) { $0.workspaceID == space }, herdr: snapshot.tabs)
        let left = Set(tabs.map(\.workspaceID)), had = Set(snapshot.tabs.map(\.workspaceID))
        let workspaces = Self.ordered(snapshot.workspaces.filter {
            !closing.contains($0.id) && (left.contains($0.id) || !had.contains($0.id))
        }, by: &rows, id: \.id) { _ in true }
        let shownTabs = Set(tabs.map(\.id))
        let panes = snapshot.panes.filter { !hidden.contains($0.id) && shownTabs.contains($0.tabID) }
        for standIn in self.tabs where !standIn.closed && workspaces.contains(where: { $0.id == standIn.workspaceID }) {
            tabs.append(Tab(id: standIn.id, workspaceID: standIn.workspaceID, label: ""))
            trees[standIn.id] = .leaf(paneID: standIn.id)
        }
        return Shown(workspaces: workspaces, tabs: tabs, panes: panes, trees: trees)
    }

    /// Closing and replaced panes, and labeled ones on their way into a split, which go once a snapshot has them
    /// landed. A ⌘T's stand-in never takes a tab with only hidden panes.
    private mutating func hidden(_ panes: [HerdrKit.Pane]) -> Set<String> {
        let hidden = closing.union(replacing.flatMap { $1.hidden(panes, old: $0) })
            .union(moving.flatMap { $0.hidden(panes) })
        moving.removeAll { new in new.landed && panes.contains { $0.label == new.label && $0.tabID == new.tabID } }
        return hidden
    }

    /// A pane closed as herdr makes it is in no snapshot read ahead of the split.
    private mutating func forget(_ ids: Set<String>) {
        let made = Set(splitPanes.values)
        closing = closing.filter { ids.contains($0) || layout != nil && (Self.isStandIn($0) || made.contains($0)) }
        fresh.formIntersection(ids)
        fresh.formUnion(made.filter(ids.contains))
    }
}

extension HostStore {
    /// Asks herdr, not the panes' last answers: a program may have started since.
    func ask(_ request: Close) -> Task<Closing?, Never>? {
        guard let client else { return nil }
        let ids = closeIDs(request), standIns = ids.filter(Ahead.isStandIn)
        if !ids.isEmpty, standIns.count == ids.count {
            closeStandIns(standIns)
            return nil
        }
        let asked = panes(closedBy: request)
        let action = closing(request)
        // ponytail: a program typed in a new tab or split in its first seconds hides too, and comes back with the
        // question.
        let clear = asked.allSatisfy {
            $0.program?.isShell == true || $0.plugin != nil && $0.program?.isPlaceholder == true
                || $0.starting && (ahead.fresh.contains($0.tabID) || ahead.fresh.contains($0.id))
        }
        if clear {
            hide(request)
        }
        let starting = Set(asked.filter(\.starting).map(\.id))
        return Task {
            let running = await programs(asked.map(\.id), starting: starting,
                                         placeholders: Set(asked.filter { $0.plugin != nil }.map(\.id)), client)
            guard running.isEmpty else {
                if clear {
                    unhide(request)
                }
                return Closing(close: request, running: running.sorted())
            }
            closeStandIns(standIns)
            await close(request, action)
            return nil
        }
    }

    private func closeStandIns(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        ahead.closing.formUnion(ids)
        for index in ahead.tabs.indices where ids.contains(ahead.tabs[index].id) {
            ahead.tabs[index].closed = true
        }
        redraw()
    }

    /// 8 at a time: a big workspace is not 30 herdr runs at once. A starting shell runs short-lived programs (`ls`,
    /// `sort`), so a starting pane is asked again for up to 0.8 s. ponytail: a slower startup (a cold nvm) still asks,
    /// naming what it runs. Any process can label a pane, so only a browser pane's placeholder counts as no program.
    func programs(_ paneIDs: [String], starting: Set<String>, placeholders: Set<String>,
                  _ client: any Multiplexer) async -> Set<String>
    {
        await withTaskGroup(of: String?.self) { group in
            var rest = paneIDs[...]
            func next() {
                guard let id = rest.popFirst() else { return }
                group.addTask {
                    let ask = {
                        try await client.program(id).flatMap {
                            $0.isShell || placeholders.contains(id) && $0.isPlaceholder ? nil : $0.title
                        }
                    }
                    do {
                        var name = try await ask()
                        for _ in 0 ..< (starting.contains(id) ? 4 : 0) where name != nil {
                            try await Task.sleep(for: .milliseconds(200))
                            name = try await ask()
                        }
                        return name
                    } catch {
                        return "A program"
                    }
                }
            }
            for _ in 0 ..< 8 {
                next()
            }
            var names = Set<String>()
            for await name in group {
                if let name {
                    names.insert(name)
                }
                next()
            }
            return names
        }
    }

    func panes(closedBy close: Close) -> [Pane] {
        let tabs = tabIDs(close)
        return panes.filter { pane in close.paneID.map { $0 == pane.id } ?? tabs.contains(pane.tabID) }
    }

    func tabIDs(_ close: Close) -> [String] {
        switch close {
        case .pane: []
        case let .tab(id): [id]
        case let .otherTabs(ids, _): ids
        case let .workspace(id):
            (workspaces.filter { $0.id == id } + worktrees(of: id)).flatMap(\.tabs).map(\.id)
        }
    }

    func close(_ close: Close) async {
        await self.close(close, closing(close))
    }

    private func close(_ close: Close, _ action: @escaping (any Multiplexer) async throws -> Void) async {
        hide(close)
        if await !write(action) {
            unhide(close)
        } else if let id = close.paneID, ahead.layout?.pane == id {
            ahead.layout?.after = 0
        }
    }

    /// Reads what shows, so it runs ahead of `hide`.
    private func closing(_ close: Close) -> (any Multiplexer) async throws -> Void {
        keepingClosedPages(close, closer(close))
    }

    private func closer(_ close: Close) -> (any Multiplexer) async throws -> Void {
        switch close {
        case let .pane(id):
            let state = pane(id)?.plugin?.statePath(session: session), machine = machine
            let split = pane(id).flatMap { tab($0.tabID)?.tree?.closing(id) } != nil
            return { client in
                try await self.close(pane: id, inSplit: split, client)
                if let state {
                    await machine.exec().remove(home: state)
                }
            }
        case let .tab(id): return { try await $0.close(tab: id) }
        case let .otherTabs(asked, _):
            // Not ones closed meanwhile: their close fails the rest. All at once: one by one, 20 tabs take seconds.
            let others = asked.filter { workspace(of: $0) != nil && !Ahead.isStandIn($0) }
            return { client in
                try await withThrowingTaskGroup { group in
                    for other in others {
                        group.addTask { try await client.close(tab: other) }
                    }
                    try await group.waitForAll()
                }
            }
        case let .workspace(id):
            // herdr refuses to close a repository's workspace with open worktrees unless the group goes too.
            let group = workspaces.contains { $0.id == id } && !worktrees(of: id).isEmpty
            return { try await $0.close(workspace: id, group: group) }
        }
    }

    func hide(_ close: Close) {
        ahead.closing.formUnion(closeIDs(close))
        holdBalanced(close)
        redraw()
    }

    func unhide(_ close: Close) {
        ahead.closing.subtract(closeIDs(close))
        if let id = close.paneID, ahead.layout?.pane == id {
            ahead.layout = nil
        }
        redraw()
    }

    /// herdr closes a workspace's worktrees with it.
    private func closeIDs(_ close: Close) -> [String] {
        switch close {
        case let .pane(id), let .tab(id): [id]
        case let .otherTabs(ids, _): ids
        case let .workspace(id): [id] + worktrees(of: id).map(\.id)
        }
    }

    func standIn(in workspaceID: String) -> String {
        let id = Ahead.standIn()
        // A beside tab herdr named that no snapshot has yet is not this stand-in's either.
        let herdrs = (last?.tabs ?? []).filter { $0.workspaceID == workspaceID }.map(\.id)
        let known = herdrs + ahead.beside.compactMap(\.tab)
        ahead.tabs.append(Ahead.NewTab(id: id, workspaceID: workspaceID, known: Set(known)))
        redraw()
        return id
    }

    func dropStandIn(_ id: String) {
        ahead.tabs.removeAll { $0.id == id }
        redraw()
    }

    func madeTab(_ standIn: String, _ id: String) {
        for index in ahead.tabs.indices {
            if ahead.tabs[index].id == standIn {
                ahead.tabs[index].made = id
            } else {
                ahead.tabs[index].known.insert(id)
            }
        }
    }

    func closeArrived() {
        let ids = ahead.toClose
        ahead.toClose = []
        for id in ids {
            Task { await close(.tab(id)) }
        }
    }
}
