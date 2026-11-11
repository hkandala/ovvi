import Foundation
import HerdrKit

/// herdr adds a tab last, so the app moves it (`tab.move`).
extension Ahead {
    /// A labeled pane on its way into a split: herdr's split runs no command, so it comes as a new tab and moves. It
    /// hides by its label outside the split's tab until, after the move, a snapshot has it in the split.
    struct Moving {
        let tabID: String
        let label: String
        var landed = false

        func hidden(_ panes: [HerdrKit.Pane]) -> [String] {
            panes.filter { $0.label == label && $0.tabID != tabID }.map(\.id)
        }
    }

    struct Beside {
        let id = UUID(), workspaceID: String, after: String
        var known: Set<String>
        var tab: String?
        var answered: Int?
    }

    /// herdr's order shows from the third snapshot after its answer at the latest, so a move herdr puts elsewhere (a
    /// stale index, a drag, another client) never pins the tab.
    /// ponytail: a tab another client makes, or a ⌘T's stand-in claims, ahead of herdr naming the new one can take its
    /// place, and a redraw counts as a snapshot; name it from a tab event if that shows.
    mutating func placed(_ tabs: [Tab], herdr: [Tab]) -> [Tab] {
        beside.removeAll { $0.answered.map { $0 >= 2 } ?? false }
        for index in beside.indices where beside[index].tab == nil {
            let new = beside[index]
            if let tab = tabs.first(where: { $0.workspaceID == new.workspaceID && !new.known.contains($0.id) }) {
                name(new.id, tab.id)
            }
        }
        var tabs = tabs
        for new in beside {
            guard let from = tabs.firstIndex(where: { $0.id == new.tab }) else { continue }
            let tab = tabs.remove(at: from)
            tabs.insert(tab, at: tabs.firstIndex { $0.id == new.after }.map { $0 + 1 } ?? from)
        }
        let ids = tabs.map(\.id), shown = Set(ids)
        let done = herdr.map(\.id).filter(shown.contains) == ids
        // Only once the snapshot has it: herdr's answer can name it first.
        beside.removeAll { new in
            new.tab.map { shown.contains($0) && (done || !shown.contains(new.after)) } ?? false
        }
        for index in beside.indices {
            beside[index].answered = beside[index].answered.map { $0 + 1 }
        }
        return tabs
    }

    mutating func name(_ id: UUID, _ tab: String) {
        for index in beside.indices {
            if beside[index].id == id {
                beside[index].tab = tab
            } else {
                beside[index].known.insert(tab)
            }
        }
        for index in tabs.indices {
            tabs[index].known.insert(tab)
        }
    }
}

extension HostStore {
    /// Not a tab another new tab claimed: a second quick open starts ahead of the snapshot with the first one's tab.
    func placeBeside(_ after: String, in workspaceID: String) -> UUID {
        let herdrs = (last?.tabs ?? []).filter { $0.workspaceID == workspaceID }.map(\.id)
        let claimed = ahead.beside.compactMap(\.tab) + ahead.tabs.compactMap(\.made)
        let new = Ahead.Beside(workspaceID: workspaceID, after: after, known: Set(herdrs + claimed))
        ahead.beside.append(new)
        return new.id
    }

    func moveBeside(_ id: UUID, _ tab: String, after: String, in workspaceID: String, _ client: any Multiplexer) async {
        ahead.name(id, tab)
        // herdr inserts ahead of the tab at the index.
        let herdrs = (last?.tabs ?? []).filter { $0.workspaceID == workspaceID }.map(\.id)
        if let index = herdrs.firstIndex(of: after) {
            do {
                try await client.move(tab: tab, to: index + 1)
            } catch {
                dropBeside(id)
            }
        }
        if let index = ahead.beside.firstIndex(where: { $0.id == id }) {
            ahead.beside[index].answered = 0
        }
    }

    /// Right after the pane's tab, as an open from a card.
    func moveToNewTab(_ paneID: String) async -> HerdrKit.Pane? {
        guard let tabID = pane(paneID)?.tabID, let workspaceID = workspace(of: tabID)?.id else { return nil }
        var moved: HerdrKit.Pane?
        await write { client in
            // In the write's turn, as `newPane`: a queued ⌘T's tab is no tab of this move's.
            let placing = placeBeside(tabID, in: workspaceID)
            do {
                guard let pane = try await client.move(pane: paneID, to: .newTab(workspaceID: workspaceID))
                else { throw HerdrError.failed("herdr named no pane") }
                moved = pane
                await moveBeside(placing, pane.tabID, after: tabID, in: workspaceID, client)
            } catch {
                dropBeside(placing)
                throw error
            }
        }
        return moved
    }

    func dropBeside(_ id: UUID) {
        ahead.beside.removeAll { $0.id == id }
        redraw()
    }
}

enum PanePlace {
    case tab(after: String)
    case split(tab: String, pane: String, SplitNode.Direction)
}

extension HostStore {
    func newPane(_ client: any Multiplexer, in workspaceID: String, cwd: String, label: PaneLabel?,
                 _ place: PanePlace) async throws -> HerdrKit.Pane
    {
        switch place {
        case let .tab(after):
            let placing = placeBeside(after, in: workspaceID)
            do {
                let pane = try await newTab(client, in: workspaceID, cwd: cwd, label: label)
                await moveBeside(placing, pane.tabID, after: after, in: workspaceID, client)
                return pane
            } catch {
                dropBeside(placing)
                throw error
            }
        case let .split(tabID, target, direction):
            guard let label else {
                guard let pane = try await client.split(target, direction, cwd: cwd) else {
                    throw HerdrError.failed("herdr named no pane")
                }
                return pane
            }
            ahead.moving.append(Ahead.Moving(tabID: tabID, label: label.text))
            do {
                let pane = try await newTab(client, in: workspaceID, cwd: cwd, label: label)
                do {
                    let moved = try await client.move(pane: pane.id, to: .tab(tabID, beside: target, split: direction))
                    for index in ahead.moving.indices where ahead.moving[index].label == label.text {
                        ahead.moving[index].landed = true
                    }
                    return moved ?? pane
                } catch {
                    try? await client.close(pane: pane.id)
                    throw error
                }
            } catch {
                // Shown as herdr has it: a pane that did not close stays reachable.
                ahead.moving.removeAll { $0.label == label.text }
                redraw()
                throw error
            }
        }
    }

    private func newTab(_ client: any Multiplexer, in workspaceID: String, cwd: String, label: PaneLabel?)
        async throws -> HerdrKit.Pane
    {
        var pane: HerdrKit.Pane?
        if let label {
            // The label's path's folder survives a restart better than the folder it is asked from.
            if let id = try await client.newTab(workspace: workspaceID, cwd: label.folder ?? cwd, label: label.text,
                                                command: label.placeholder)
            {
                pane = try await client.pane(id)
            }
        } else {
            pane = try await client.newTab(workspace: workspaceID, cwd: cwd)
        }
        guard let pane else { throw HerdrError.failed("herdr named no pane") }
        return pane
    }
}
