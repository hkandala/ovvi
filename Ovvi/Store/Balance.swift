import Foundation
import HerdrKit

/// Settings ▸ General ▸ Balance splits automatically: on (the default), each run of side-by-side or stacked panes a
/// pane opens or closes in gets equal shares, as Balance Splits gives them; off, herdr halves a split pane and a
/// closed pane's neighbor takes its place.
extension HostStore {
    static var balances: Bool {
        // `bool(forKey:)` reads a launch argument's "NO" too.
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "balanceSplits") == nil || defaults.bool(forKey: "balanceSplits")
    }

    /// Inside the write that opened it, before herdr's next snapshot can show it at herdr's half.
    func opened(_ pane: HerdrKit.Pane, _ client: any Multiplexer) async throws {
        if Self.balances {
            try await balance(pane.tabID, client, around: pane.id)
        }
    }

    /// herdr's tree from before the close tells which run the pane was in.
    func close(pane paneID: String, _ client: any Multiplexer) async throws {
        let left = Self.balances ? try await client.snapshot().trees.lazy.compactMap { tabID, tree in
            tree.closing(paneID).map { (tab: tabID, evened: $0.evened) }
        }.first : nil
        try await client.close(pane: paneID)
        if let left {
            for change in left.evened {
                try await client.setRatio(tab: left.tab, path: change.path, ratio: change.ratio)
            }
        }
    }

    /// The tab shows the run evened as the pane goes, ahead of herdr: one motion, not herdr's close and then the
    /// balance (`Ahead.layout`).
    func holdBalanced(_ close: Close) {
        guard Self.balances, let id = close.paneID, let tab = pane(id).flatMap({ tab($0.tabID) }),
              let left = tab.tree?.closing(id) else { return }
        ahead.layout = Ahead.NewLayout(tabID: tab.id, pane: id, tree: left.tree.applying(left.evened))
    }

    /// A pane that closed on its own (its shell exited) or from another client, or moved out: its run evens once
    /// herdr shows it gone. One the app closes evens in its own write; a replaced one leaves its place to the new one.
    func balanceLeft(_ old: Snapshot?, _ new: Snapshot) {
        guard Self.balances, let old else { return }
        for (tabID, tree) in old.trees {
            guard let now = new.trees[tabID] else { continue }
            let gone = Set(tree.paneIDs).subtracting(now.paneIDs).subtracting(ahead.closing)
                .subtracting(ahead.replacing.keys)
            guard gone.count == 1, let left = gone.first.flatMap(tree.closing), !left.evened.isEmpty,
                  left.tree.places(like: now, renaming: [:]) else { continue }
            Task {
                await write { client in
                    // Not a tab that changed since.
                    guard try await client.snapshot().trees[tabID]?.places(like: now, renaming: [:]) == true
                    else { return }
                    for change in left.evened {
                        try await client.setRatio(tab: tabID, path: change.path, ratio: change.ratio)
                    }
                }
            }
        }
    }
}
