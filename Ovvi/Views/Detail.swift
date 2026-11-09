import Foundation
import HerdrKit
import SwiftUI

/// A short message at the bottom of the page (design: Notice).
struct Notice {
    enum Tone {
        /// `progress`: a spinner while a command runs; `success`: a green check when it ended.
        case error, warning, info, progress, success
    }

    let text: String
    var tone = Tone.error
    /// The terminal whose pane Show selects in the window (an agent's notice, agent-control/cli): a pane id can name
    /// another pane after a move.
    var show: String?
    let id = UUID()
}

/// A notice's glass capsule (design: Notice).
struct NoticeCapsule<Action: View>: View {
    let tone: Notice.Tone
    let text: String
    /// Instead of the tone's symbol.
    var symbol: String?
    /// A button, or the ✕.
    @ViewBuilder var action: Action
    @Environment(\.look) private var look

    var body: some View {
        let (toneSymbol, label, color) = switch tone {
        case .error: ("xmark.octagon.fill", "Error", look.error)
        case .warning: ("exclamationmark.triangle.fill", "Warning", look.needsYou)
        case .info: ("info.circle.fill", "Information", look.working)
        case .progress: ("", "In progress", look.working)
        case .success: ("checkmark.circle.fill", "Done", look.finished)
        }
        HStack(spacing: 8) {
            Group {
                if tone == .progress, symbol == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol ?? toneSymbol).foregroundStyle(color)
                }
            }
            .accessibilityLabel(label)
            .accessibilityIdentifier("notice.symbol")
            Text(text).lineLimit(2)
            action
        }
        // As the plugin card's toast: round buttons in the round notice.
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .floatingGlass(in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

/// The page's selected workspace's tabs, or why there is nothing to show.
struct Detail: View {
    let pages: WindowPages
    let page: Page

    var body: some View {
        let store = page.store
        let machine = store.name
        switch store.state {
        case .connecting:
            // After 0.3 s, so a fast connect shows nothing; ssh's question replaces it while it is up.
            if pages.question == nil {
                Loader(symbol: store.machine.icon, text: "Connecting to \(machine)…", id: "detail.connecting",
                       delay: .milliseconds(300))
            }
        case .failed(.notFound):
            install(store)
        case let .failed(.disconnected(text)):
            // Retries stopped: only Connect may ask (machines#health-check).
            let title = "Disconnected from \(store.machine.name)"
            EmptyState(symbol: "network.slash", title: title, text: text, id: "detail") {
                Button("Connect") { Task { await store.connect(in: pages) } }.buttonStyle(.glassProminent)
                    .accessibilityIdentifier("detail.connect")
            }
        case let .failed(.unsupported(text)):
            // The client asks again every 2 s, so an updated herdr clears it. No button: the running server's version
            // counts, and only a restart, which ends every program in the session, would change it.
            EmptyState(symbol: "arrow.up.circle", title: "herdr is too old", text: text + ".", id: "detail")
        case .failed where !store.isRunning:
            // Why a start failed, if one did.
            let title = "\(store.session) is not running"
            EmptyState(symbol: "power.circle", title: title, text: store.notice?.text, id: "detail") {
                Button("Start \(store.session)") { Task { await store.start() } }.buttonStyle(.glassProminent)
                    .accessibilityIdentifier("detail.start")
            }
        case .live, .failed:
            // Reconnecting (the server runs, the bridge fails) in one branch, so the page keeps its state through
            // it; the notices stay clickable.
            let reconnecting = store.reconnecting
            tabs()
                .opacity(reconnecting ? 0.5 : 1)
                .allowsHitTesting(!reconnecting)
                .overlay {
                    if reconnecting {
                        // Why, when it says (a remote with no Perl fails every try).
                        let why = if case let .failed(.failed(why)) = store.state {
                            why
                        } else {
                            ""
                        }
                        Loader(symbol: store.machine.icon, text: "Reconnecting to \(machine)…", detail: why,
                               id: "detail.reconnecting")
                    }
                }
                .overlay(alignment: .bottom) { notices(store) }
        }
    }

    /// The selected tab's page, the button that makes a missing tab, or that the session is empty: its page
    /// header's `+` makes a workspace.
    @ViewBuilder private func tabs() -> some View {
        if let workspace = page.selectedWorkspace {
            if workspace.tabs.isEmpty {
                EmptyState(symbol: "macwindow", title: "No tabs in \(workspace.label)") {
                    Button { Task { await page.newTab() } } label: {
                        Text("New Tab")
                        Text(KeyboardShortcut.newTab.glyphs).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("new-tab")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // As the tab bar's marker: the first tab until a snapshot settles the selection.
                TabPages(tab: workspace.tabs[page.selectedIndex(in: workspace)], page: page, overview: pages.overview)
                    .id(page.id)
            }
        } else if page.store.state == .live {
            // Not while it reconnects before its first snapshot.
            EmptyState(symbol: "square.dashed", title: "This session is empty", id: "detail.empty") {
                Button { Task { await page.newWorkspace() } } label: {
                    Text("New Space")
                    Text(KeyboardShortcut.newWorkspace.glyphs).foregroundStyle(.secondary)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("detail.new-workspace")
            }
        } else {
            // Room for the Reconnecting overlay: on no view it never drew (a machine that failed its first connect).
            Color.clear
        }
    }

    private func notices(_ store: HostStore) -> some View {
        VStack(spacing: gap) {
            if let notice = store.notice {
                NoticeCapsule(tone: notice.tone, text: notice.text) {
                    if let id = notice.show {
                        Button("Show") {
                            store.notice = nil
                            if let pane = store.panes.first(where: { $0.terminalID == id }) {
                                page.go(to: pane)
                            }
                        }
                        .accessibilityIdentifier("notice.show")
                    }
                    Button("Close", systemImage: "xmark") { store.notice = nil }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityIdentifier("notice.close")
                }
                .accessibilityIdentifier("detail.notice")
                // By id: the same text again is a new notice.
                .onChange(of: notice.id, initial: true) {
                    AccessibilityNotification.Announcement(notice.text).post()
                }
            }
            // Another window controls the session (D66). Under a notice; no ✕: only Take Back ends it.
            if page.watched {
                let text = "Controlled in another window"
                NoticeCapsule(tone: .info, text: text, symbol: "macwindow.on.rectangle") {
                    Button("Take Back") { pages.control(store) }
                        .accessibilityIdentifier("notice.controlled.take-back")
                }
                .accessibilityIdentifier("notice.controlled")
                .onAppear {
                    AccessibilityNotification.Announcement(text).post()
                }
            }
        }
        .padding(.horizontal, gap * 2)
        .padding(.bottom, 30)
    }

    /// A missing herdr, its install command and Install herdr; the installer's progress while it runs, its
    /// output and Try Again when it failed (talking-to-herdr#install-herdr).
    @ViewBuilder private func install(_ store: HostStore) -> some View {
        let machine = store.machine, installs = HerdrInstall.shared
        let run = { _ = Task { await installs.install(on: machine, session: store.session) } }
        switch installs.steps[machine.id] {
        case let .running(line):
            Loader(symbol: "shippingbox", text: "Installing herdr…", detail: line, id: "detail.installing")
        case let .failed(output):
            let failed = "herdr did not install"
            EmptyState(symbol: "exclamationmark.triangle", title: failed, text: output, code: true, id: "detail") {
                Button("Try Again") { run() }.buttonStyle(.glassProminent).accessibilityIdentifier("detail.install")
            }
        case nil:
            let title = "herdr is not installed" + (machine.isRemote ? " on \(machine.name)" : "")
            EmptyState(symbol: "shippingbox", title: title, text: HerdrInstall.command, code: true, id: "detail") {
                Button("Install herdr") { run() }.buttonStyle(.glassProminent)
                    .accessibilityIdentifier("detail.install")
            }
        }
    }
}

/// The selected tab's page over the pages of the tabs shown last, which stay made, hidden: a switch to one of them
/// shows it as it was, with nothing built again (a chat's rows, its scroll place, a web card in the window). Under the
/// overview every page stays, hidden. A view of its own per tab: a shared one would carry its cards' places into the
/// next tab's.
private struct TabPages: View {
    let tab: HostStore.Tab
    let page: Page
    let overview: Bool
    /// The tabs shown before, the latest last.
    @State private var shown: [String] = []
    /// ponytail: a fixed count; a kept page costs its cards' updates while hidden. Bound by the cards' cost if a
    /// session of heavy tabs needs more.
    static let kept = 8

    var body: some View {
        let all = page.store.workspaces.flatMap(\.tabs)
        let recent = (shown.filter { id in id != tab.id && all.contains { $0.id == id } } + [tab.id]).suffix(Self.kept)
        // In an order no switch, drop or move changes: a moved page would host its cards' views again. Only the shown
        // page draws and takes input, so the stacking order does not matter.
        ZStack {
            ForEach(all.filter { recent.contains($0.id) }.sorted { $0.id < $1.id }) { kept in
                let shows = kept === tab && !overview
                TabPage(tab: kept, page: page)
                    .opacity(shows ? 1 : 0)
                    .allowsHitTesting(shows)
                    .environment(\.pageHidden, !shows)
            }
        }
        .onChange(of: tab.id, initial: true) { shown = Array(recent) }
    }
}

extension EnvironmentValues {
    /// In a kept tab's page out of view (`TabPages`).
    @Entry var pageHidden = false
}

extension View {
    /// A text field in a kept page that goes out of view gives up the keyboard: keys typed after the switch must not
    /// reach it.
    func blursWhenHidden(_ focus: FocusState<Bool>.Binding) -> some View {
        modifier(BlurWhenHidden(focus: focus))
    }
}

private struct BlurWhenHidden: ViewModifier {
    let focus: FocusState<Bool>.Binding
    @Environment(\.pageHidden) private var hidden

    func body(content: Content) -> some View {
        content.onChange(of: hidden) {
            if hidden {
                focus.wrappedValue = false
            }
        }
    }
}
