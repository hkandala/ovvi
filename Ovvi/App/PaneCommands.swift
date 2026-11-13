import HerdrKit
import SwiftUI

extension CommandList {
    /// Actions ask `target` for the pane when they run: the menu bar can lag the last keyboard move.
    static func pane(_ page: Page?, tabs: Bool = true, _ target: @escaping @MainActor () -> HostStore.Pane?)
        -> [Command]
    {
        let pane = target(), zoomed = pane.map { page?.zoomed($0.id) == true } ?? false, fixed = Chooser.fixed != nil
        func act(_ title: String, _ hotkey: String? = nil, _ section: Command.Section = .pane,
                 symbol: String? = nil, enabled: Bool = true, id: String? = nil, heading: String? = nil,
                 _ run: @escaping (Page, HostStore.Pane) async -> Void) -> Command
        {
            let alternate = fixed && section == .pane && title.hasPrefix("Split") ? title + " and Choose…" : nil
            return Command(section: section, title: title, id: id, key: hotkey.flatMap { .hotkey($0) }, group: .panes,
                           symbol: symbol, heading: heading, keywords: "pane", enabled: pane != nil && enabled,
                           alternate: alternate, action: {
                               if let page, let pane = target() {
                                   Task { await run(page, pane) }
                               }
                           })
        }
        // Alone, herdr would close its tab, and the move beside would put the new one where it was.
        let alone = (page?.store.panes(in: pane?.tabID).count ?? 0) < 2
        // herdr refuses a move into the pane's own tab, and without a target it splits the tab's focused pane.
        let others = (tabs ? page?.sidebarWorkspaces ?? [] : []).flatMap { workspace in
            workspace.tabs.filter { $0.id != pane?.tabID }.map { other in
                act(page?.titleText(other) ?? other.label, nil, .paneMove, id: other.id, heading: workspace.label) {
                    await $0.drop($1.id, on: .tab(other.id))
                }
            }
        }
        return [
            act("Float Pane", "pane.float", symbol: "pip.enter") { $0.float($1) },
            act("Split Right", "pane.split-right", symbol: "rectangle.split.2x1") { await $0.split($1.id, .right) },
            act("Split Down", "pane.split-down", symbol: "rectangle.split.1x2") { await $0.split($1.id, .down) },
            act("Split Left", "pane.split-left", symbol: "rectangle.lefthalf.inset.filled") {
                await $0.split($1.id, .right, before: true)
            },
            act("Split Up", "pane.split-up", symbol: "rectangle.tophalf.inset.filled") {
                await $0.split($1.id, .down, before: true)
            },
            act(zoomed ? "Restore Pane" : "Zoom Pane", "pane.zoom", symbol: "plus.magnifyingglass",
                enabled: pane.map { page?.canZoom($0.id) == true } ?? false) { $0.zoom($1.id) },
            Command(section: .paneMove, title: "Move Pane to Tab", symbol: "arrow.right.square", keywords: "pane",
                    enabled: pane != nil, menu: [
                        act("New Tab", nil, .paneMove, symbol: "plus.square", enabled: !alone) { page, pane in
                            await page.follow(page.store.moveToNewTab(pane.id), pane.terminalID)
                        },
                        act("New Space", nil, .paneMove, symbol: "folder.badge.plus") {
                            await $0.move($1, to: .newWorkspace())
                        },
                    ] + others),
            Command(section: .paneMove, title: "Rename Pane…", symbol: "pencil", keywords: "pane",
                    enabled: pane != nil, name: pane.map { pane in
                        (pane.label ?? "", { await page?.store.rename(pane: pane.id, label: $0) })
                    }) { page?.renamingPaneID = target()?.id },
            // A plugin pane's label is its kind.
            act("Reset Pane Name", nil, .paneMove, symbol: "arrow.uturn.backward",
                enabled: pane?.label != nil && pane?.plugin == nil) { await $0.store.rename(pane: $1.id, label: "") },
        ] + pluginCard(pane?.terminalID.flatMap { page?.terminals.plugins[$0] }) + ends(page, pane, target)
    }

    private static func ends(_ page: Page?, _ pane: HostStore.Pane?,
                             _ target: @escaping @MainActor () -> HostStore.Pane?) -> [Command]
    {
        let replace = Command(section: .close, title: "Replace Pane", key: .hotkey("pane.replace"), group: .panes,
                              symbol: "arrow.clockwise.square", keywords: "pane restart new shell respawn reset",
                              enabled: pane != nil) { page?.replacePane(target()) }
        // A plugin card's ⌥⌘R is Reload Plugin.
        let redraw = pane?.plugin != nil ? [] : [
            Command(
                section: .close,
                title: "Redraw Terminal",
                key: .hotkey("terminal.redraw"),
                group: .panes,
                symbol: "arrow.trianglehead.2.clockwise",
                keywords: "pane refresh repaint rerender tui garbled",
                enabled: pane.map { page?.shownChat($0) == nil } == true,
                action: {
                    if let page, let pane = target(), pane.plugin == nil {
                        page.terminal(pane)?.redraw()
                    }
                },
            ),
        ]
        let terminal = pane?.agent == nil && pane?.plugin == nil ? [] : [
            Command(section: .close, title: "Open Terminal Here", group: .panes, symbol: "terminal",
                    keywords: "pane shell kind") { page?.replacePane(target(), Replacement(button: "Open Terminal")) },
        ]
        let plugins = Registry.all.filter { $0.chooser != nil && pane?.plugin?.manifest?.id != $0.id }.map { plugin in
            let keywords = ["pane kind", plugin.description.lowercased()] + plugin.keywords
            return Command(section: .close, title: "Open \(plugin.chooser ?? plugin.name) Here", group: .panes,
                           symbol: plugin.icon, keywords: keywords.joined(separator: " "), enabled: pane != nil,
                           action: {
                               if let page, let pane = target() {
                                   page.open(plugin, in: pane)
                               }
                           })
        }
        let agent = Command(section: .close, title: "Start Agent Here", group: .panes, symbol: "sparkles",
                            keywords: "pane kind " + Chooser.agents.map(\.name).joined(separator: " ").lowercased(),
                            enabled: pane != nil,
                            menu: Chooser.agents.map { agent in
                                Command(section: .close, title: agent.name, program: agent.command) {
                                    if let page, let pane = target() {
                                        page.start(agent, in: pane)
                                    }
                                }
                            })
        return redraw + [replace] + terminal + [agent] + plugins + [
            Command(section: .close, title: "Close Pane", id: "pane.close", key: .hotkey("pane.close"), group: .panes,
                    symbol: "xmark.square", keywords: "pane", enabled: pane != nil || page?.standIn != nil,
                    action: { page?.closePane(target()) }),
        ]
    }
}

extension CommandList {
    func floatingCommands(_ floating: Floating) -> [Command] {
        let terminalID = floating.terminalID
        guard let page = pages?.withFloats.first(where: { $0.id == floating.session }) else { return [] }
        let pane = page.store.terminalPane(terminalID)
        let terminal = pane.flatMap(page.terminal), editor = page.editor(pane)
        var main = self
        main.floating = nil
        let browser = pane.flatMap(page.browser)
        let steps = ["app.bigger": 1, "app.smaller": -1, "app.actual-size": 0]
        let sizes = main.all.filter { $0.section == .size || $0.id == "app.font-size" }.map { size in
            guard let browser, let step = size.id.flatMap({ steps[$0] }) else { return size }
            var zoom = size
            zoom.enabled = true
            zoom.action = { browser.view.zoom(step) }
            return zoom
        }
        func edit(_ title: String, _ action: Selector, _ symbol: String) -> Command {
            Command(section: .palette, title: title, group: .edit, symbol: symbol, enabled: terminal != nil) {
                if let terminal {
                    NSApp.sendAction(action, to: terminal.view, from: nil)
                }
            }
        }
        let list = [
            Command(section: .close, title: "Detach Pane", key: .hotkey("pane.close"), group: .panes,
                    symbol: "pip.exit", action: { page.floating[terminalID] = nil }),
            Command(section: .view, title: "Command Palette", id: "app.palette", key: .hotkey("app.palette"),
                    symbol: "command", enabled: palette != nil) { palette?.wrappedValue.toggle() },
            Command(section: .view, title: "Stay on Top", symbol: "pin", checked: page.floating[terminalID] == true,
                    setting: true) { page.floating[terminalID]?.toggle() },
        ] + Self.editorCommands(page: page, pane: pane, terminal: pane.map {
            $0.plugin == nil && page.store.chat($0)?.showsChat != true
        } == true) { editor }
            + [
                edit("Copy", #selector(NSText.copy(_:)), "doc.on.doc"),
                edit("Paste", #selector(NSText.paste(_:)), "doc.on.clipboard"),
            ] + Self.pane(page, tabs: false) { pane }.filter { $0.section == .close }.map {
                var command = $0
                command.key = command.id == "pane.close" ? .hotkey("tab.close") : command.key
                return command
            } + sizes + Self.browser(browser, chooser: pane.flatMap { page.store.chooser($0.id) })
        return list + Self.plugin(pane?.terminalID.flatMap { page.terminals.plugins[$0] }, besides: list)
    }
}
