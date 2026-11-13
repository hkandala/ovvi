import Foundation
import HerdrKit
import SwiftUI

struct Detail: View {
    let pages: WindowPages
    let page: Page

    var body: some View {
        let store = page.store
        let machine = store.name
        switch store.state {
        case .connecting:
            if pages.question == nil {
                Loader(symbol: store.machine.icon, text: "Connecting to \(machine)…", id: "detail.connecting",
                       delay: .milliseconds(300))
            }
        case .failed(.notFound):
            install(store)
        case let .failed(.disconnected(text)):
            let title = "Disconnected from \(store.machine.name)"
            EmptyState(symbol: "network.slash", title: title, text: text, id: "detail") {
                Button("Connect") { Task { await store.connect(in: pages) } }.buttonStyle(.glassProminent)
                    .accessibilityIdentifier("detail.connect")
            }
        case let .failed(.unsupported(text)):
            // No button: the running server's version counts, and only a restart, which ends every program in the
            // session, changes it.
            EmptyState(symbol: "arrow.up.circle", title: "herdr is too old", text: text + ".", id: "detail")
        case .failed where store.starting:
            Loader(symbol: "rectangle.stack", text: "Starting \(store.session)…", id: "detail.starting")
        case .failed where !store.isRunning:
            let title = "\(store.session) is not running"
            EmptyState(symbol: "rectangle.stack", title: title, text: store.startProblem, id: "detail") {
                Button("Start \(store.session)") { Task { await store.start() } }.buttonStyle(.glassProminent)
                    .accessibilityIdentifier("detail.start")
            }
        case .live, .failed:
            // Reconnecting in one branch, so the page keeps its state through it.
            let reconnecting = store.reconnecting
            let why = if case let .failed(error) = store.state {
                error.localizedDescription
            } else {
                ""
            }
            let cards = page.selectedWorkspace.map { !$0.tabs.isEmpty } ?? false
            tabs()
                // Before the overlay: the page's own Loader still draws.
                .environment(\.pageReconnecting, reconnecting)
                .opacity(reconnecting ? 0.5 : 1)
                .allowsHitTesting(!reconnecting)
                .overlay {
                    // With no cards, the page reads as Connecting does.
                    if reconnecting, !cards {
                        Loader(symbol: store.machine.icon, text: "Reconnecting to \(machine)…", detail: why,
                               id: "detail.reconnecting")
                    }
                }
                .overlay(alignment: .bottom) { notices(store, reconnecting: reconnecting && cards ? why : nil) }
        }
    }

    @ViewBuilder private func tabs() -> some View {
        if let workspace = page.selectedWorkspace {
            if workspace.tabs.isEmpty {
                EmptyState(symbol: "macwindow", title: "No tabs in \(workspace.label)") {
                    Button { Task { await page.newTab() } } label: {
                        Text("New Tab")
                        Text(Hotkeys.glyphs("tab.new")).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.glassProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabPages(tab: workspace.tabs[page.selectedIndex(in: workspace)], page: page, overview: pages.overview)
                    .id(page.id)
            }
        } else if page.store.state == .live {
            EmptySession(page: page)
        } else {
            Color.clear
        }
    }

    /// `reconnecting`: the reason, while the page reconnects over its cards.
    private func notices(_ store: HostStore, reconnecting: String?) -> some View {
        VStack(spacing: gap) {
            if let notice = store.notice {
                NoticeCapsule(tone: notice.tone, text: notice.text) {
                    if let id = notice.show {
                        Button("Show") {
                            store.notice = nil
                            if let pane = store.terminalPane(id) {
                                page.go(to: pane)
                            }
                        }
                        .accessibilityIdentifier("notice.show")
                    }
                    if let retry = notice.retry {
                        Button("Retry") {
                            store.notice = nil
                            retry()
                        }
                        .accessibilityIdentifier("notice.retry")
                    }
                    Button("Close", systemImage: "xmark") { store.notice = nil }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityIdentifier("notice.close")
                }
                .accessibilityIdentifier("detail.notice")
                .onHover { store.noticeHovered = $0 }
                // A notice removed under the pointer gets no hover end.
                .onDisappear { store.noticeHovered = false }
                .onChange(of: notice.id, initial: true) {
                    AccessibilityNotification.Announcement(notice.text).post()
                }
            }
            if let reconnecting {
                // In the notices' place: small, at the bottom, not over the cards' middle.
                NoticeCapsule(tone: .progress, text: "Reconnecting to \(store.name)…", detail: reconnecting) {}
                    .accessibilityIdentifier("detail.reconnecting")
            }
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
            let why = "Ovvi runs on herdr, which keeps your sessions running."
            EmptyState(symbol: "shippingbox", title: title, text: why, command: HerdrInstall.command, id: "detail") {
                Button("Install herdr") { run() }.buttonStyle(.glassProminent)
                    .accessibilityIdentifier("detail.install")
            }
        }
    }
}

/// A view of its own per tab: a shared one would carry its cards' places into the next tab's.
private struct TabPages: View {
    let tab: HostStore.Tab
    let page: Page
    let overview: Bool
    @State private var shown: [String] = []
    /// ponytail: a constant count; a kept page costs its cards' updates while hidden. Bound by the cards' cost if a
    /// session of heavy tabs needs more.
    static let kept = 8

    var body: some View {
        let all = page.store.workspaces.flatMap(\.tabs)
        let recent = (shown.filter { id in id != tab.id && all.contains { $0.id == id } } + [tab.id]).suffix(Self.kept)
        // In an order no switch, drop or move changes: a moved page would host its cards' views again.
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
    @Entry var pageHidden = false
    /// The page shows Reconnecting over its cards: it says it once, so no card or empty page shows a state of its own.
    @Entry var pageReconnecting = false
}

extension View {
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
