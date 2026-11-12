import Foundation
import HerdrKit

/// Settings ▸ General ▸ Balance splits automatically: on (the default), each run of side-by-side or stacked panes a
/// pane opens or closes in gets equal shares, as Balance Splits gives them; off, herdr halves a split pane and a
/// closed pane's neighbor takes its place. Best effort: a balance herdr refuses never fails the open or the close.
extension HostStore {
    static var balances: Bool {
        // `bool(forKey:)` reads a launch argument's "NO" too.
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "balanceSplits") == nil || defaults.bool(forKey: "balanceSplits")
    }

    /// Inside the write that opened it, before herdr's next snapshot can show it at herdr's half.
    func opened(_ pane: HerdrKit.Pane, _ client: any Multiplexer) async {
        if Self.balances {
            try? await balance(pane.tabID, client, around: pane.id)
        }
    }

    /// herdr's tree from before the close tells which run the pane was in; a pane alone in its tab needs no read.
    func close(pane paneID: String, inSplit: Bool, _ client: any Multiplexer) async throws {
        let left = Self.balances && inSplit ? try? await client.snapshot().trees.lazy.compactMap { tabID, tree in
            tree.closing(paneID).map { (tab: tabID, evened: $0.evened) }
        }.first : nil
        try await client.close(pane: paneID)
        if let left {
            for change in left.evened {
                try? await client.setRatio(tab: left.tab, path: change.path, ratio: change.ratio)
            }
        }
    }

    /// The tab shows the run evened as the pane goes, ahead of herdr: one motion, not herdr's close and then the
    /// balance (`Ahead.layout`). Not over another tab's split still in its write.
    func holdBalanced(_ close: Close) {
        guard Self.balances, let id = close.paneID, let tab = pane(id).flatMap({ tab($0.tabID) }),
              ahead.layout.map({ $0.tabID == tab.id }) ?? true, let left = tab.tree?.closing(id) else { return }
        ahead.layout = Ahead.NewLayout(tabID: tab.id, pane: id, tree: left.tree.applying(left.evened))
    }

    /// A pane that another client opened, or that closed on its own (its shell exited), from another client or by a
    /// move out: its run evens once herdr shows it. The app's own opens and closes even in their own write (a snapshot
    /// read during it no longer matches by this write's turn); a replaced pane leaves its place to the new one.
    func balanceOthers(_ old: Snapshot?, _ new: Snapshot) {
        guard Self.balances, let old,
              Set(old.panes.map { "\($0.id) \($0.tabID)" }) != Set(new.panes.map { "\($0.id) \($0.tabID)" })
        else { return }
        for (tabID, now) in new.trees {
            guard let tree = old.trees[tabID] else { continue }
            let gone = Set(tree.paneIDs).subtracting(now.paneIDs), added = Set(now.paneIDs).subtracting(tree.paneIDs)
            let evened = if added.isEmpty, gone.count == 1, let id = gone.first,
                            !ahead.closing.contains(id), ahead.replacing[id] == nil,
                            let left = tree.closing(id), left.tree.places(like: now, renaming: [:])
            {
                left.evened
            } else if gone.isEmpty, added.count == 1, let id = added.first {
                now.evened(around: id)
            } else {
                [(path: [Bool], ratio: Double)]()
            }
            guard !evened.isEmpty else { continue }
            Task {
                // Not a write of the user's: no notice, none cleared.
                try? await request { client in
                    // Not a tab that changed since.
                    guard try await client.snapshot().trees[tabID]?.places(like: now, renaming: [:]) == true
                    else { return }
                    for change in evened {
                        try await client.setRatio(tab: tabID, path: change.path, ratio: change.ratio)
                    }
                }
            }
        }
    }
}
