import HerdrKit
import SwiftUI

@main
struct OvviApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private var settings = AppSettings()

    init() {
        SwipeRouter.install()
        MovingCard.activateOnClick()
        Latency.shared.install()
        FrameProbe.shared.install()
        NSWindow.allowsAutomaticWindowTabbing = false
        // Ahead of any surface, so none starts at libghostty's default size.
        PaneTerminal.configure()
        // A monitor sees keys ahead of any view: an invisible button's shortcut keeps its first action.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                KeyboardShortcut.second(event) || NSWindow.confirm(event) || Page.chooserKey(event)
            } ? nil : event
        }
    }

    var body: some Scene {
        WindowGroup(id: WindowPages.mainScene) {
            ContentView()
        }
        .windowToolbarStyle(.unifiedCompact)
        // The frame a window last moved, resized or closed with, which AppKit cascades; with none, the screen's
        // visible frame.
        .defaultWindowPlacement { _, context in
            WindowReader.lastFrame.map(FloatFrames.placement)
                ?? WindowPlacement(.center, size: context.defaultDisplay.visibleRect.size)
        }
        .windowIdealSize(.maximum)
        // The first launch shows the welcome alone; its end opens the first window.
        .defaultLaunchBehavior(Welcome.firstLaunch ? .suppressed : .automatic)
        // The title-bar tabs would grow the window when the sidebar hides.
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }
        // Else SwiftUI opens a window for a folder dropped on the Dock icon.
        .handlesExternalEvents(matching: [])
        .onChange(of: settings.terminal) { PaneTerminal.configure() }
        .onChange(of: settings.appearance, initial: true) {
            NSApp.appearance = switch settings.appearance {
            case .auto: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
        // Its main window saves and opens it, so SwiftUI must not restore it.
        WindowGroup(id: WindowPages.floatScene, for: Floating.self) { $floating in
            if let floating {
                FloatingWindow(floating: floating)
            }
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 720, height: 460)
        .defaultWindowPlacement { _, _ in FloatFrames.placement() }
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        // Else its scene's File items (Close on ⌘W) take the main window's place: ⌘W closes the main window.
        .commandsRemoved()
        // Else a folder dropped on the Dock icon opens an empty floating window.
        .handlesExternalEvents(matching: [])
        Window("About Ovvi", id: WindowPages.aboutScene) { About() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .handlesExternalEvents(matching: [])
        // Not a `Settings` scene: its window grows on a pushed page and puts Back on a row of its own.
        Window("Settings", id: WindowPages.settingsScene) { SettingsWindow() }
            .defaultSize(width: 715, height: 560)
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .handlesExternalEvents(matching: [])
    }
}

struct ContentView: View {
    @State private var pages = WindowPages()
    @SceneStorage("pages") private var savedPages = ""
    @SceneStorage("page") private var savedPage = ""
    @SceneStorage("machine") private var savedMachine = ""
    @SceneStorage("selection") private var savedSelection = ""
    @SceneStorage("sidebar") private var sidebar = true
    @SceneStorage("sidebarWidth") private var sidebarWidth = 300.0
    @SceneStorage("picking") private var picking = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let page = pages.current {
                WindowContent(pages: pages, page: page, sidebar: $sidebar,
                              sidebarWidth: $sidebarWidth)
            } else if picking {
                SessionPicker(pages: pages)
            } else {
                WindowStart(pages: pages)
            }
        }
        .animation(Animation.reduced ? nil : .easeOut(duration: 0.2),
                   value: pages.current == nil && !picking)
        .onChange(of: pages.current == nil && !picking) { WindowStart.started = true }
        .task {
            let opening = WindowPages.opening
            WindowPages.opening = nil
            if let opening, opening.machine == nil {
                picking = true
            }
            guard !picking else { return }
            let restored = await restore(opening?.machine)
            // Closed while it restores: nothing of it may stay.
            if Task.isCancelled {
                pages.closed()
            } else if pages.list.isEmpty, !openAsked() {
                picking = true
            } else {
                pages.opened()
                for page in pages.list {
                    for id in page.floating.keys {
                        FloatFrames.open(Floating(session: page.id, terminalID: id), over: pages.window,
                                         with: openWindow)
                    }
                }
                if opening?.connect == true || restored, let store = pages.current?.store {
                    await store.connect(in: pages)
                }
            }
        }
        .onChange(of: pages.list.map(\.id)) {
            savedPages = $1.joined(separator: " ")
            if !$1.isEmpty {
                picking = false
            }
        }
        .onChange(of: pages.current?.id) { savedPage = $1 ?? "" }
        .onChange(of: pages.machine.id) { savedMachine = $1 }
        .onChange(of: selection) { savedSelection = $1 }
        .task(id: scenePhase == .active ? pages.current?.id : nil) {
            pages.visible = scenePhase == .active
            pages.markShown()
            guard pages.visible, let store = pages.current?.store else { return }
            repeat {
                await store.updateGit(all: true)
            } while await (try? Task.sleep(for: .seconds(10))) != nil
        }
    }

    private func openAsked() -> Bool {
        guard let asked = WindowPages.asked,
              let machine = MachineList.shared.machine(asked.machine) else { return false }
        pages.machine = machine
        pages.open(asked.session)
        return true
    }

    /// Sorted keys, so the same selection is the same text.
    private var selection: String {
        let pages = Dictionary(uniqueKeysWithValues: pages.list.map { page in
            (page.id, Selection(workspace: page.selectedWorkspaceID, tabs: page.selectedTabIDs,
                                floating: page.floating))
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(pages)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private func restoreSelection() {
        let selection = (try? JSONDecoder().decode([String: Selection].self, from: Data(savedSelection.utf8))) ??
            [:]
        for page in pages.list {
            guard let saved = selection[page.id] else { continue }
            page.floating = saved.floating
            page.selectedWorkspaceID = saved.workspace
            page.selectedTabIDs = saved.tabs
            if page.store.state == .live {
                page.settle()
            }
        }
    }

    private struct Selection: Codable {
        var workspace: String?
        var tabs: [String: String]
        var floating: [String: Bool]
    }

    /// Whether it opened the window's saved pages.
    private func restore(_ opening: Machine?) async -> Bool {
        guard pages.list.isEmpty else { return false }
        // A window macOS restores gets its scene storage a moment after it first shows; a restored window always
        // has saved pages.
        if AppDelegate.restoring {
            for _ in 0 ..< 50 where savedPages.isEmpty {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        // Closed meanwhile: no session may start for it.
        guard !Task.isCancelled else { return false }
        // A run against a throwaway session must open only it.
        let argument = MachineList.session
        let id = MachineList.machine ?? savedMachine
        let machine = opening ?? MachineList.shared.machine(id)
        if let machine {
            pages.machine = machine
        }
        // A removed machine's window opens no page: its saved pages are the remote's sessions.
        let removed = machine == nil && !id.isEmpty
        // A test run (`-defaultSession`) shares saved windows with Debug runs: it restores only throwaway sessions. A
        // first launch restores none (the app closes those windows).
        let restores = argument == nil && !removed && !Welcome.firstLaunch
        let saved = restores ? savedPages.split(separator: " ").map(String.init)
            .filter { MachineList.defaultSession == nil || $0.hasPrefix("ovvi-e2e-") } : []
        if !saved.isEmpty {
            let client: any Multiplexer = await HerdrClient(session: saved[0], exec: pages.machine.exec())
            // A deleted session stays deleted; a stopped one (a restart of the Mac) starts.
            let names = await (try? client.sessions())?.map(\.name)
            guard !Task.isCancelled else { return false }
            for name in saved where names?.contains(name) ?? true {
                pages.open(name, start: true)
            }
            if let page = pages.list.first(where: { $0.id == savedPage }) {
                pages.show(page)
            }
        }
        if pages.list.isEmpty, let name = argument ?? (opening == nil ? nil : Session.defaultName) {
            pages.open(name, start: !pages.machine.isRemote)
        }
        restoreSelection()
        pages.showTerminals() // The restored tab streams at once, not at the next snapshot.
        return !saved.isEmpty
    }
}

private struct WindowContent: View {
    let pages: WindowPages
    let page: Page
    @Binding var sidebar: Bool
    @Binding var sidebarWidth: Double
    @State private var panel: Panel?
    @State private var workspaceButtonX: CGFloat = 0
    @State private var fullScreen = false
    @State private var lightsOff = 0
    @State private var height: CGFloat = 0
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let style = settings.style
        let look = Look(style: style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let commands = CommandList(pages: pages, palette: open(.palette), sidebar: $sidebar,
                                   openSession: open(.openSession), shortcuts: open(.shortcuts), settings: settings)
        // The page's and the sidebar's 4 pt top room (for the cards' strokes) lies under the title row; the row
        // stays on top for its clicks and window drags.
        VStack(spacing: -4) {
            TitleBar(
                pages: pages,
                page: page,
                fullScreen: fullScreen,
                sidebar: $sidebar,
                sidebarWidth: sidebarWidth,
                palette: open(.palette),
                workspaceMenu: open(.workspaces),
                openSession: open(.openSession),
                workspaceButtonX: $workspaceButtonX,
            )
            .zIndex(1)
            HStack(spacing: 0) {
                if sidebar {
                    // The cards start at the sidebar's width: its handle lies over the page's 8 pt gap.
                    Sidebar(pages: pages, width: $sidebarWidth) { panel = .openSession }
                        .padding(.bottom, gap)
                        // Rex's page header and first row sit 3 pt lower than the page's 4 pt room.
                        .padding(.top, 7)
                        .padding(.trailing, -gap)
                        .underOverview(pages)
                        .zIndex(1)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                // Kept under the overview, hidden, so its kept pages stay.
                Detail(pages: pages, page: page).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(pages.overview ? 0 : 1)
                    .animation(nil, value: pages.overview)
                    .allowsHitTesting(!pages.overview)
                    // Not `accessibilityHidden(false)`, which overrides the hidden ones inside.
                    .accessibilityElement(children: pages.overview ? .ignore : .contain)
            }
            .testValue("overview.zoom", "Overview Zoom", "\(WindowPages.zoomSteps)",
                       shown: SettlingHost.record)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay {
                if pages.overview {
                    Overview(pages: pages, leading: sidebar ? sidebarWidth - gap : 0)
                        .transition(.identity)
                }
            }
        }
        // Rex's collapse time.
        .animation(Animation.reduced ? nil : .easeInOut(duration: 0.3), value: sidebar)
        .hoverPanelHost()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .overlay {
            if panel == .workspaces || !sidebar && page.dragging != nil {
                WorkspaceMenu(pages: pages, page: page, open: open(.workspaces)) { panel = .openSession }
                    .padding(.leading, workspaceButtonX)
                    .padding(.top, TitleBar.height)
                    .floatingPanel(open: open(.workspaces), alignment: .topLeading)
                    .opacity(panel == .workspaces ? 1 : 0).allowsHitTesting(panel == .workspaces)
            }
            if panel == .openSession {
                OpenSession(pages: pages, open: open(.openSession))
                    .padding(.top, 96).floatingPanel(open: open(.openSession), alignment: .top)
            }
            if panel == .palette {
                Palette(pages: pages, page: page, commands: commands, open: open(.palette), height: height)
                    .padding(.top, 96).floatingPanel(open: open(.palette), alignment: .top)
            }
            if panel == .shortcuts {
                Shortcuts(commands: commands.all).floatingPanel(open: open(.shortcuts), alignment: .center)
            }
        }
        .modifier(CloseDialog(page: page))
        .overlay {
            if let question = pages.question {
                AskDialog(question: question, machine: pages.machine).id(question.id).dialog()
            }
        }
        .environment(\.look, look)
        .testValue("window.machine", "Machine", pages.machine.name)
        .testValue("window.look", "Appearance", "\(style.rawValue) \(look.dark ? "dark" : "light")")
        .testValue("app.latency", "Latency", Latency.shared.recorded.joined(separator: "; "), shown: Latency.isOn)
        .testValue("app.frames", "Frames", FrameProbe.shared.recorded, shown: FrameProbe.isOn)
        // In one handler: the keys go back only once the panel counts as closed.
        .onChange(of: panel, initial: true) { old, new in
            pages.panelOpen = new != nil
            if new != nil {
                pages.terminals.dropClaims()
            } else if old != nil {
                page.focusKeyboardCard()
            }
        }
        .onChange(of: "\(panel.map { "\($0)" } ?? "") \(sidebar)", initial: true) {
            Latency.shared.panel = $1
        }
        .modifier(AgentsWatch(pages: pages, page: page))
        .windowChrome(look)
        .background(WindowReader(pages: pages, fullScreen: $fullScreen, lightsOff: $lightsOff))
        .testValue("window.lights", "Traffic Lights Off", "\(lightsOff)",
                   shown: WindowReader.recordLights)
        .navigationTitle(page.selectedTab.map { "\(page.titleText($0)) - \(page.store.title)" } ?? page.store.name)
        .menuBar(commands)
        .onChange(of: sidebar) {
            if sidebar, panel == .workspaces {
                panel = nil
            }
        }
        .onChange(of: page.shownTerminals) { pages.showTerminals() }
        .onChange(of: page.zoomedPaneID) { pages.markShown() }
    }

    enum Panel {
        case workspaces, palette, openSession, shortcuts
    }

    private func open(_ which: Panel) -> Binding<Bool> {
        Binding { panel == which } set: { panel = $0 ? which : panel == which ? nil : panel }
    }
}
