import HerdrKit
import SwiftUI

struct PaneCard: View {
    static let header: CGFloat = 36
    static let inset: CGFloat = 10

    static func terminalSize(_ size: CGSize, header: CGFloat) -> CGSize {
        CGSize(width: max(size.width - 2 * inset, 1), height: max(size.height - header - gap, 1))
    }

    static let row: CGFloat = 32
    static let floatingTop: CGFloat = 4
    let id: String
    let page: Page
    let away: Bool
    @State private var hovering = false
    @State private var zone: Heading??
    @State private var size = CGSize.zero
    @State private var keptLit = false
    @Environment(\.appearsActive) private var active
    @Environment(\.look) private var look
    @Environment(\.pageHidden) private var hidden
    @Environment(\.chromeLink) private var chromeLink
    private var settings = AppSettings()

    var body: some View {
        let store = page.store
        let pane = store.pane(id)
        let zoomed = page.zoomedPaneID == id
        let terminal = pane.flatMap(page.terminal)
        // Not read in a kept page out of view: each split changes them (the shown tab's tree, its newest card, the
        // keyboard), which would run every kept card's body again at each change.
        let shown = hidden ? [] : page.selectedTab?.tree?.paneIDs ?? []
        let newest = hidden ? nil : page.newest.flatMap { newest in
            shown.contains(id) && shown.contains { $0 == newest.id || store.ahead.splitPanes[$0] == newest.id }
                ? newest.id : nil
        }
        let lit = hidden ? keptLit : newest.map { $0 == id || store.ahead.splitPanes[id] == $0 }
            ?? pane.map { page.keyboardCard($0.tabID) === $0 } ?? (id == page.standIn)
        // `CardChrome` draws its border.
        let bordered = lit && shown.count > 1 && page.zoomedPaneID == nil
        let floated = pane.map(page.floats) ?? false
        let follow = hovering && settings.followMouse && !away && active && !floated
        let content = page.watched ? 0.85 : 1
        let chooser = store.chooser(id), (browser, plugin) = page.cards(pane, make: !hidden)
        let chat = chooser == nil && !floated ? pane.flatMap(page.store.chat) : nil
        VStack(spacing: 0) {
            header(
                pane ?? store.parked[id],
                zoomed: zoomed,
                showsButtons: lit || hovering || zoomed,
                new: chooser != nil,
                chat: chat,
            )
            .opacity(content)
            // A ZStack, not a Group: a Group's modifiers go on each child, so the chooser's overlay would be made again
            // (a fade out and in) as the terminal comes, and dropped with no child (a stand-in's card).
            ZStack {
                if let pane, floated {
                    FloatedPlaceholder(page: page, pane: pane)
                } else if let browser {
                    BrowserCard(browser: browser, page: page)
                } else if let plugin {
                    PluginCard(plugin: plugin, page: page)
                } else if let pane, let label = pane.plugin, terminal == nil {
                    if let plugin = label.manifest {
                        if let picture = pane.terminalID.flatMap(page.terminals.picture) {
                            CardPicture(picture: picture, pane: pane)
                        } else {
                            PluginLoader(plugin: plugin)
                        }
                    } else {
                        MissingPlugin(label: label, pane: pane, page: page)
                    }
                } else if let pane, let chat = page.shownChat(pane) {
                    ChatView(chat: chat, page: page, terminal: terminal)
                        .background { pane.terminalID.map { ChatProbe(
                            terminalID: $0,
                            registry: page.terminals,
                            hidden: hidden,
                        ) } }
                } else if let terminal {
                    TerminalCard(terminal: terminal, watched: page.watched, alpha: chooser == nil ? content : 0)
                        .overlay {
                            if let find = page.find, find.paneID == id {
                                FindHighlights(find: find, terminal: terminal)
                            }
                        }
                        .padding(.horizontal, Self.inset).padding(.bottom, gap)
                        .contextMenu {
                            TerminalItems(view: terminal.view)
                            PaneItems(page: page, pane: pane)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).environment(\.litCard, lit)
            .overlay {
                NewPaneOverlay(chooser: floated ? nil : chooser, page: page, cardID: id)
                    .contextMenu { PaneItems(page: page, pane: pane) }
            }
            .overlay(alignment: .topTrailing) {
                if !floated, let find = page.find, find.paneID == id {
                    FindBar(find: find, page: page).padding(gap)
                }
            }
        }
        // The whole card, also with no terminal (a split's stand-in): else the empty content takes no room and the card
        // is a header-high band.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: [lit, bordered], initial: true) {
            if !hidden {
                keptLit = lit
                chromeLink?.card?.lit = (lit, bordered)
            }
        }
        // Not the view's task: a page that leaves at once (a quick switch) would cancel it. Hidden, it gets no hover
        // end.
        .onChange(of: hidden, initial: true) {
            if hidden {
                hovering = false
            } else {
                Task { await store.askProgram(id, soon: true) }
            }
        }
        .clipShape(CardSurface.shape)
        // The card's element is its background (a container would merge into a one-pane page's); `CardChrome` draws
        // the surface.
        .background {
            Color.clear.contentShape(CardSurface.shape)
                .readableText(terminal.map { $0.state.isFailed ? "failed" : $0.ready ? "" : "loading" } ?? "")
                .accessibilityLabel(page.cardLabel(pane))
                .accessibilityIdentifier("pane.\(id)")
                .accessibilityActions { PaneActions(page: page, pane: pane) }
                .contextMenu { PaneItems(page: page, pane: pane) }
        }
        .testValue("pane.\(id).border", "Active", "", shown: SettlingHost.record && bordered)
        .overlay(alignment: .topLeading) {
            if let zone, page.dragging != nil {
                let half = CGSize(width: size.width / 2, height: size.height / 2)
                DropIndicator()
                    .frame(width: zone == .left || zone == .right ? half.width : size.width,
                           height: zone == .up || zone == .down ? half.height : size.height)
                    // Padding, not an offset: the accessibility frame keeps to what is drawn.
                    .padding(.leading, zone == .right ? half.width : 0).padding(.top, zone == .down ? half.height : 0)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .background {
            // Only while the page shows: the drop target is an AppKit view of its own, which the page's opacity and
            // `allowsHitTesting` do not stop, so a kept page's, over the shown one, would take its cards' drags (files
            // too, and refuse them).
            if !hidden {
                Color.clear.contentShape(.rect)
                    .onDrop(of: [.ovviDrag], delegate: CardDrop(paneID: id, page: page, size: size, zone: $zone))
            }
        }
        .clearsDrop(page) { zone = nil }
        .onHover { hovering = $0 }
        .task(id: follow) {
            // A lit card waits too while a text field has the keys: a rename in another card holds them, and its end
            // gives them to that card.
            guard follow, !lit || NSApp.keyWindow?.firstResponder is NSText else { return }
            while await (try? Task.sleep(for: .milliseconds(150))) != nil {
                // Not once the page is on another tab (a palette pick): hover lasts until the mouse moves.
                guard let pane = store.pane(id), pane.tabID == page.selectedTab?.id else { return }
                // No button down, no open menu (hover stays on while one tracks), no text field typing.
                guard NSEvent.pressedMouseButtons == 0, RunLoop.main.currentMode != .eventTracking,
                      !(NSApp.keyWindow?.firstResponder is NSText) else { continue }
                if page.keyboardCard(pane.tabID) !== pane {
                    page.go(to: pane)
                }
                return
            }
        }
        .accessibilityHidden(away)
    }

    private func header(_ pane: HostStore.Pane?, zoomed: Bool, showsButtons: Bool, new: Bool, chat: Chat?)
        -> some View
    {
        let twoRows = page.twoRows(pane)
        let (browser, plugin) = twoRows ? page.cards(pane, make: !hidden) : (nil, nil)
        let agent = twoRows && pane?.plugin == nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                title(pane, new: new, browser: browser, agent: agent)
                if plugin?.dirty == true {
                    DirtyDot(paneID: id)
                }
                Spacer(minLength: 0)
                if showsButtons, pane != nil {
                    buttons(zoomed: zoomed)
                }
            }
            .frame(height: Self.header)
            if let browser {
                BrowserToolbar(browser: browser, page: page).frame(height: Self.row)
            } else if let plugin {
                PluginHeader(plugin: plugin, page: page).frame(height: Self.row)
            } else if agent, let pane {
                HStack(spacing: 6) {
                    ProgramGlyph(icon: pane.iconID, letter: pane.letter).allowsHitTesting(false)
                    let name = pane.agentLabel ?? pane.programName ?? ""
                    Text("\(name) \(Text(pane.folder ?? "").foregroundStyle(.secondary))")
                        .fontWeight(.regular).lineLimit(1).truncationMode(.middle).allowsHitTesting(false)
                    CardState(chat: chat, state: pane.state, paneID: id).padding(.leading, 4)
                    Spacer(minLength: 0)
                    AgentControl(pane: pane, chat: chat, page: page)
                }
                .frame(height: Self.row)
            }
        }
        .frame(height: page.headerHeight(pane), alignment: .top)
        .fontWeight(.medium)
        .padding(.leading, 11).padding(.trailing, 8)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background {
            // Simultaneous: a single tap beside the double one would wait out the double-click interval.
            Color.clear.contentShape(.rect).onTapGesture(count: 2) { page.zoom(id) }
                .simultaneousGesture(TapGesture().onEnded {
                    // A floated pane's placeholder raises its window by its button only, as its body does.
                    if let pane = page.store.pane(id), !page.floats(pane) {
                        page.go(to: pane)
                    }
                })
                .dragSource(.pane(id), page: page, previewSize: size)
        }
        .contextMenu { PaneItems(page: page, pane: pane) }
    }

    @ViewBuilder
    private func title(_ pane: HostStore.Pane?, new: Bool, browser: Browser?, agent: Bool) -> some View {
        if let browser {
            BrowserIcon(browser: browser)
        } else if !agent {
            ProgramGlyph(icon: pane?.iconID ?? "terminal", letter: pane?.letter).allowsHitTesting(false)
        }
        if page.renamingPaneID == id {
            RenameField(prompt: "Pane Name", initial: pane?.label ?? "", commit: { label in
                Task { await page.store.rename(pane: id, label: label) }
            }, end: { stopRenaming(pane) }, blur: { page.renamingPaneID = nil })
                .accessibilityIdentifier("pane.\(id).rename")
        } else {
            Group {
                if new {
                    Text("New Pane").lineLimit(1)
                } else if let pane, let label = pane.browser {
                    Text(page.browserTitle(pane, label) ?? "New Tab").lineLimit(1)
                } else if let pane, let label = pane.plugin {
                    Text(page.pluginTitle(pane, label)).lineLimit(1).truncationMode(.middle)
                } else if agent {
                    Text(pane?.agentTitle ?? pane?.programName ?? "").lineLimit(1)
                } else {
                    PaneTitle(pane: pane)
                }
            }
            .allowsHitTesting(false)
            .accessibilityIdentifier("pane.\(id).title")
        }
    }
}

private extension PaneCard {
    func buttons(zoomed: Bool) -> some View {
        let store = page.store
        return HStack(spacing: 2) {
            if !zoomed {
                IconButton(symbol: "pip.enter", help: "Float Pane", size: 22,
                           accent: store.pane(id).map(page.floats) == true, action: {
                               if let pane = store.pane(id) {
                                   page.float(pane)
                               }
                           })
                           .accessibilityIdentifier("pane.\(id).float")
                IconButton(symbol: "rectangle.split.2x1", help: "Split Right", key: .splitRight, size: 22) {
                    Task { await page.split(id, .right) }
                }
                .accessibilityIdentifier("pane.\(id).split-right")
                IconButton(symbol: "rectangle.split.1x2", help: "Split Down", key: .splitDown, size: 22) {
                    Task { await page.split(id, .down) }
                }
                .accessibilityIdentifier("pane.\(id).split-down")
            }
            IconButton(symbol: zoomed ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right", help: zoomed ? "Restore Pane" : "Zoom Pane", key: .zoom,
                size: 22,
                accent: zoomed) { page.zoom(id) }
                .accessibilityIdentifier("pane.\(id).zoom")
                .disabled(!page.canZoom(id))
            IconButton(symbol: "xmark", help: "Close Pane", key: .closePane, size: 22) {
                page.close(.pane(id))
            }
            .accessibilityIdentifier("pane.\(id).close")
        }
        .foregroundStyle(look.paneButton)
    }

    func stopRenaming(_ pane: HostStore.Pane?) {
        guard page.renamingPaneID == id else { return }
        page.renamingPaneID = nil
        if let pane {
            page.go(to: pane)
        }
    }
}

/// Their own view, so they are made when the menu opens, not in each card's body (300 tab titles per card, at every
/// change of one).
private struct PaneItems: View {
    let page: Page
    let pane: HostStore.Pane?

    var body: some View {
        CommandItems(commands: CommandList.pane(page) { pane }, sections: [.pane, .paneMove, .close])
    }
}

/// Move Pane to Tab ▸ flattened to New Tab and New Workspace: any accessibility client makes SwiftUI build them with
/// the card, and one per tab makes a switch to a big session 3 times slower.
private struct PaneActions: View {
    let page: Page
    let pane: HostStore.Pane?

    var body: some View {
        let commands = CommandList.pane(page, tabs: false) { pane }.filter(\.enabled).flatMap { command in
            command.menu.isEmpty ? [(command.title, command.action)]
                : command.menu.filter(\.enabled).map { ("\(command.title) \($0.title)", $0.action) }
        }
        ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
            Button(command.0, action: command.1)
        }
    }
}
