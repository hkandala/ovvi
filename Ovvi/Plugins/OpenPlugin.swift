import HerdrKit
import SwiftUI

enum Opening {
    case here, tab, side
}

extension Page {
    /// Waits for a snapshot that has the pane: herdr answers a split or a tab ahead of it, and a fast pick (⌘D, then 3)
    /// would find nothing to replace.
    func open(_ plugin: PluginManifest, _ chooser: Chooser) {
        guard chooser.starting == nil, chooser.opening == nil else { return }
        chooser.opening = plugin
        Task {
            defer {
                // Kept while the replace waits for its snapshot: else the replaced pane's shell shows until the new
                // pane takes its place.
                if chooser.paneID.map({ store.ahead.replacing[$0] == nil }) ?? true {
                    store.drop(chooser)
                }
            }
            let clock = ContinuousClock(), begun = clock.now
            while chooser.paneID.flatMap(store.pane).flatMap({ store.workspace(of: $0.tabID) }) == nil,
                  clock.now - begun < .seconds(10), store.choosers.contains(where: { $0 === chooser })
            {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let id = chooser.paneID {
                await replace(id, Replacement(plugin: plugin, folder: chooser.folder))
            }
        }
    }

    func open(_ plugin: PluginManifest, in pane: HostStore.Pane) {
        if let chooser = store.chooser(pane.id) {
            open(plugin, chooser)
        } else {
            replacePane(pane, Replacement(button: "Open \(plugin.chooser ?? plugin.name)", plugin: plugin))
        }
    }

    func openFromPlugin(_ plugin: PluginManifest, arg: String, at place: String? = nil, from source: String,
                        how: Opening, background: Bool = false) async
    {
        let file = arg.hasPrefix("file:"), path = file ? URL(string: arg)?.path ?? "" : arg
        if file || plugin.opens.folders || !plugin.opens.files.isEmpty, path.hasPrefix("/"),
           await store.there(path, from: "/") == nil
        {
            return store.notFound(path)
        }
        await open(plugin, arg: arg, at: place, from: source, how: how, background: background)
    }

    func open(_ plugin: PluginManifest, arg: String, at place: String? = nil, from source: String,
              how: Opening, background: Bool = false) async
    {
        if how == .here, let shown = terminals.plugins[source], shown.manifest.id == plugin.id {
            return shown.go(arg, at: place)
        }
        let card = store.terminalPane(source)
        guard let tabID = card?.tabID ?? selectedTab?.id, let workspace = store.workspace(of: tabID) else { return }
        let label = store.newLabel(plugin, arg: arg), cwd = card?.cwd ?? keyboardPane?.cwd ?? "~"
        guard label.fits else { return }
        // From a floating card, any gesture opens in a floating window of its own.
        let floats = floating[source] != nil
        var made: HerdrKit.Pane?
        await store.write { client in
            let spot = if how == .side, let card, !floats {
                PanePlace.split(tab: card.tabID, pane: card.id, .right)
            } else {
                PanePlace.tab(after: tabID)
            }
            let pane = try await store.newPane(client, in: workspace.id, cwd: cwd, label: label, spot)
            made = pane
            // ponytail: a card made from a snapshot ahead of this line misses its landing; hand it over in the label
            // if that shows.
            if let place, let terminalID = pane.terminalID {
                terminals.landings[terminalID] = place
            }
            if !background, !floats {
                follow(pane, pane.terminalID)
            }
        }
        if floats, let made {
            await floatNew(made)
        }
    }
}

extension HostStore {
    func arg(_ plugin: PluginManifest, in folder: String) async -> String {
        guard plugin.opens.folders || plugin.opens.git else { return "" }
        var root = folder
        if await gitRuns(), let repo = await Git.root(folder, exec: machine.exec()) {
            root = repo
        }
        return root.hasSuffix("/") ? root : root + "/"
    }
}
