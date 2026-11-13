import HerdrKit
import SwiftUI

extension Ahead {
    struct Replacing {
        let tabID: String
        let known: Set<String>
        let terminal: String?
        var made: HerdrKit.Pane?
        /// Hidden in the tab it is made in too: that tab shows for a snapshot, and its going takes the pane out of
        /// the keyboard history.
        var label: String?

        /// Not the replaced pane, which has the label of a card made again.
        func hidden(_ panes: [HerdrKit.Pane], old: String) -> [String] {
            panes
                .filter {
                    $0.id != old && ($0.tabID == tabID && !known.contains($0.id) || label != nil && $0.label == label)
                }
                .map(\.id)
        }
    }

    mutating func keepCards(_ ids: Set<String>) {
        cards = cards.filter { ids.contains($0.key) }.merging(replaced.compactMap { old, new in
            new.made.map { ($0.id, old) }
        }) { $1 }
    }
}

extension HostStore {
    /// herdr 0.9.5 has no respawn: the pane is split (herdr starts the new one in the pane's live folder) and closed,
    /// so the new one fills its place in the tree, at its size. `made` runs as herdr makes the new pane, ahead of the
    /// close.
    func replace(_ paneID: String, plugin: PluginManifest? = nil, label: PaneLabel? = nil, folder: String? = nil,
                 made: (HerdrKit.Pane) -> Void) async
    {
        guard let old = pane(paneID), let workspace = workspace(of: old.tabID) else { return }
        ahead.replacing[paneID] = Ahead.Replacing(tabID: old.tabID, known: Set(last?.panes.map(\.id) ?? []),
                                                  terminal: old.terminalID)
        let done = await write { client in
            var new: HerdrKit.Pane?
            var label = label, cwd = "~"
            if label == nil, let plugin {
                cwd = if let folder {
                    folder
                } else {
                    try await client.pane(paneID).cwd ?? old.cwd ?? "~"
                }
                label = await newLabel(plugin, arg: arg(plugin, in: cwd))
            }
            if let label {
                ahead.replacing[paneID]?.label = label.text
                // The label's path's folder survives a restart better than the folder it is asked from.
                if let tab = try await client.newTab(workspace: workspace.id, cwd: label.folder ?? cwd,
                                                     label: label.text, command: label.placeholder)
                {
                    do {
                        new = try await client.move(pane: tab, to: .tab(old.tabID, beside: paneID))
                    } catch {
                        try? await client.close(pane: tab)
                        throw error
                    }
                }
            } else {
                new = try await client.split(paneID, .right, cwd: nil)
            }
            guard let new else {
                throw HerdrError.failed("herdr named no pane")
            }
            ahead.replacing[paneID]?.made = new
            made(new)
            try await client.close(pane: paneID)
        }
        if !done {
            ahead.replacing[paneID] = nil
            redraw()
        }
    }
}

extension HostStore {
    /// herdr brings a card pane back from its saved session without a program when its saved folder is gone. Once per
    /// pane per launch, also after a failure: no remake on every snapshot.
    func remakeCard(_ pane: Pane, _ new: HerdrKit.Pane) {
        guard new.restoreError != nil, let label = PaneLabel(new.label), !pane.remade else { return }
        pane.remade = true
        Task { await replace(pane.id, label: label) { _ in } }
    }
}

struct Replacement {
    var button = "Replace Pane"
    var chooser = false
    var agent: Chooser.Agent?
    var plugin: PluginManifest?
    var folder: String?
}

extension Page {
    func replacePane(_ pane: HostStore.Pane?, _ replacement: Replacement? = nil) {
        let key = "replace \(pane?.id ?? "")", event = NSApp.currentEvent
        guard let pane, let client = store.client, store.ahead.replacing[pane.id] == nil, !asking.contains(key),
              event?.type != .keyDown || event?.isARepeat != true,
              newest.map({ store.pane($0.id) != nil || pane.id != keyboardPane?.id }) ?? true else { return }
        let replacement = replacement ?? Replacement(chooser: pane.agent != nil || pane.plugin != nil)
        asking.insert(key)
        Task {
            let running = await store.programs([pane.id], starting: pane.starting ? [pane.id] : [],
                                               placeholders: pane.plugin != nil ? [pane.id] : [], client)
            asking.remove(key)
            if running.isEmpty {
                await replace(pane.id, replacement)
            } else {
                closing = HostStore.Closing(close: .pane(pane.id), running: running.sorted(), replace: replacement)
            }
        }
    }

    func replace(_ paneID: String, _ replacement: Replacement) async {
        let old = store.pane(paneID)?.terminalID
        await store.replace(paneID, plugin: replacement.plugin, folder: replacement.folder) { new in
            if replacement.chooser {
                store.choose(new, starting: replacement.agent)
            }
            if old.flatMap({ floating[$0] }) == nil {
                follow(new, new.terminalID, select: false)
            }
        }
    }

    func zoomReplaced() {
        let zoomed = zoomedPanes.mapValues { store.ahead.replaced[$0]?.made?.id ?? $0 }
        if zoomed != zoomedPanes {
            zoomedPanes = zoomed
        }
    }

    /// In the snapshot that shows it, ahead of the replaced pane's window closing: it opens with its terminal drawn,
    /// and a float-only page keeps a float.
    func floatReplaced() {
        for replaced in store.ahead.replaced.values {
            guard let old = replaced.terminal, let pinned = floating[old], let new = replaced.made?.terminalID
            else { continue }
            floating[new] = pinned
            // Out of the way first: a new window over one of its group at the same place is cascaded 29 pt off.
            let window = FloatFrames.windows.object(forKey: old as NSString)
            window?.orderOut(nil)
            FloatFrames.open(
                Floating(session: id, terminalID: new),
                over: terminals.pages?.window,
                frame: window?.frame,
                with: WindowPages.openWindow,
            )
        }
    }
}
