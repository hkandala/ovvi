import AppKit
import HerdrKit
import SwiftUI

struct FloatingWindow: View {
    let floating: Floating
    @State private var palette = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.appearsActive) private var appearsActive

    private var look: Look {
        Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
    }

    var body: some View {
        let pages = WindowPages.windows.first { $0.floats(floating.terminalID) }
        let page = pages?.withFloats.first { $0.id == floating.session && $0.floating[floating.terminalID] != nil }
        let pane = page?.store.terminalPane(floating.terminalID)
        Group {
            if let pages, let page {
                content(pages, page, pane)
            }
        }
        .frame(minHeight: 200)
        .windowChrome(look)
        .environment(\.look, look)
        .navigationTitle(pane.map { pane in
            page?.kindTitle(pane).map { [$0, $1].plainTitle } ?? pane.cardTitle
        } ?? "terminal")
        .background(FloatReader(terminalID: floating.terminalID,
                                pinned: page?.floating[floating.terminalID] == true,
                                closed: { page?.floating[floating.terminalID] = nil }))
        .onChange(of: appearsActive, initial: true) { _, active in
            if active, let page {
                HostStore.look(pane, in: page.store)
            }
        }
        .onChange(of: page == nil, initial: true) { _, gone in
            if gone {
                dismissWindow(id: WindowPages.floatScene, value: floating)
            }
        }
    }

    private func content(_ pages: WindowPages, _ page: Page, _ pane: HostStore.Pane?) -> some View {
        let terminal = pane.flatMap(page.terminal), chooser = pane.flatMap { page.store.chooser($0.id) }
        let browser = pane.flatMap(page.browser), plugin = pane.flatMap(page.plugin)
        let chat = chooser == nil ? pane.flatMap(page.store.chat) : nil
        let commands = CommandList(pages: pages, palette: $palette, settings: settings,
                                   floating: floating)
        return VStack(spacing: 0) {
            header(page, pane, chat: chat)
            // Not a Group, whose modifiers go on each child: the chooser's overlay would be made again as they change.
            ZStack {
                if let browser {
                    FloatingBrowser(browser: browser, page: page)
                } else if let plugin {
                    FloatingPlugin(plugin: plugin, page: page)
                } else if let pane, let label = pane.plugin, terminal == nil {
                    MissingPlugin(label: label, pane: pane, page: page)
                } else if let chat, chat.showsChat {
                    ChatView(chat: chat, page: page, terminal: terminal)
                } else if let terminal {
                    terminalCard(terminal, page, pane, faded: chooser != nil, commands)
                } else {
                    Color.clear
                }
            }
            // Not on the window: a frame's minimum width hides its content's, and the title row's buttons (a chat's
            // switch too) can need more.
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let pane {
                    NewPaneOverlay(chooser: chooser, page: page, cardID: pane.id)
                        .contextMenu { CommandItems(commands: commands.all, sections: [.palette, .close]) }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let find = page.find, find.paneID == pane?.id {
                    FindBar(find: find, page: page).padding(gap)
                }
            }
            .background(CardSurface(keyboard: terminal?.hasKeyboard == true
                    || chat?.showsChat == true))
            .clipShape(CardSurface.shape)
            .overlay { CardFlash(store: page.store, id: pane?.id ?? "") }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("float.\(pane?.id ?? "")")
            .padding([.horizontal, .bottom], gap)
        }
        .overlay {
            if palette {
                Palette(pages: pages, page: page, commands: commands, open: $palette, height: 400)
                    .padding(.top, 40).floatingPanel(open: $palette, alignment: .top)
            }
        }
        .menuBar(commands)
        .modifier(CloseDialog(page: page, floated: pane?.id))
    }

    private func terminalCard(_ terminal: PaneTerminal, _ page: Page, _ pane: HostStore.Pane?, faded: Bool,
                              _ commands: CommandList) -> some View
    {
        TerminalCard(terminal: terminal, watched: page.watched, alpha: faded ? 0 : page.watched ? 0.85 : 1)
            // In this window already: a claim made while it is the main window's card would take that window's
            // keyboard.
            .onAppear { terminal.view.takeKeyboard() }
            .overlay {
                if let find = page.find, find.paneID == pane?.id {
                    FindHighlights(find: find, terminal: terminal)
                }
            }
            .padding(.horizontal, PaneCard.inset).padding(.vertical, gap)
            .contextMenu { CommandItems(commands: commands.all, sections: [.palette, .close]) }
    }

    private func header(_ page: Page, _ pane: HostStore.Pane?, chat: Chat?) -> some View {
        let workspace = pane.flatMap { page.store.workspace(of: $0.tabID) }
        let tab = workspace?.tabs.first { $0.id == pane?.tabID }
        let rest = [workspace?.label, tab.map(page.titleText)]
            .compactMap(\.self).map { " › \($0)" }.joined()
        let pinned = page.floating[floating.terminalID] == true
        let id = "float.\(pane?.id ?? "")"
        return HStack(spacing: gap) {
            if let pane {
                PaneInfo(pane: pane, page: page, chat: chat).layoutPriority(1).accessibilityIdentifier("\(id).info")
            }
            if PaneLabel(pane?.label) == nil {
                if pane != nil {
                    Rectangle().fill(look.divider).frame(width: 1, height: 12)
                }
                HStack(spacing: 0) {
                    Text(page.store.title).truncationMode(.middle)
                    Text(rest).layoutPriority(1)
                }
                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                .readableText(page.store.title + rest)
                .accessibilityIdentifier("\(id).place")
            }
            Spacer(minLength: 0)
            if let pane, pane.plugin == nil {
                AgentControl(pane: pane, chat: chat, page: page)
            }
            IconButton(symbol: pinned ? "pin.fill" : "pin", help: "Stay on Top", accent: pinned) {
                page.floating[floating.terminalID]?.toggle()
            }
            .accessibilityValue(pinned ? "on" : "off")
            .accessibilityIdentifier("\(id).pin")
            IconButton(symbol: "xmark", help: "Close Pane", key: .closeTab) {
                if let pane {
                    page.close(.pane(pane.id))
                }
            }
            .accessibilityIdentifier("\(id).close")
            IconButton(symbol: "pip.exit", help: "Detach Pane", key: .closePane) {
                page.floating[floating.terminalID] = nil
            }
            .accessibilityIdentifier("\(id).detach")
        }
        .foregroundStyle(look.chrome)
        .padding(.leading, TitleBar.inset(fullScreen: false)).padding(.trailing, gap)
        .frame(height: TitleBar.height)
        .background { Color.clear.contentShape(.rect).gesture(WindowDragGesture()) }
    }
}

private struct PaneInfo: View {
    let pane: HostStore.Pane
    let page: Page
    let chat: Chat?

    var body: some View {
        HStack(spacing: 6) {
            ProgramTile(icon: pane.iconID, letter: pane.letter)
            Group {
                if let (name, detail) = page.kindTitle(pane) {
                    Text("\(name)\(Text(detail.map { " \($0)" } ?? "").foregroundStyle(.secondary))").lineLimit(1)
                    if page.plugin(pane)?.dirty == true {
                        DirtyDot(paneID: pane.id)
                    }
                } else {
                    PaneTitle(pane: pane)
                }
            }
            .fontWeight(.medium)
            CardState(chat: chat, state: pane.state, paneID: pane.id)
        }
        .accessibilityElement(children: .combine)
    }
}
