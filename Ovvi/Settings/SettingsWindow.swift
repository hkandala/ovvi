import SwiftUI

enum SettingsPage: String, CaseIterable, Hashable {
    case general, appearance, terminal, agents, machines, plugins, privacy

    var title: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .terminal: "apple.terminal"
        case .agents: "sparkles"
        case .machines: "desktopcomputer"
        case .plugins: "puzzlepiece.extension"
        case .privacy: "hand.raised"
        }
    }
}

enum SettingsDetail: Hashable {
    case machine(String), plugin(String)
}

@MainActor @Observable
final class SettingsRoute {
    static let shared = SettingsRoute()
    var page: SettingsPage? = .general
    var path: [SettingsDetail] = []
    var ring: String?

    func open(_ page: SettingsPage, _ detail: SettingsDetail? = nil) {
        self.page = page
        path = detail.map { [$0] } ?? []
        WindowPages.openWindow?(id: WindowPages.settingsScene)
    }
}

struct SettingsWindow: View {
    @State private var search = ""
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        @Bindable var route = SettingsRoute.shared
        NavigationSplitView {
            List(selection: Binding { route.page } set: { route.page = $0
                route.path = []
            }) {
                if search.isEmpty {
                    ForEach(SettingsPage.allCases, id: \.self) { page in
                        SettingsSidebarRow(page: page)
                    }
                } else {
                    ForEach(SettingsSearch.matches(search)) { row in
                        Button {
                            route.page = row.page
                            route.path = row.detail.map { [$0] } ?? []
                            route.ring = row.id
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title)
                                    Text(row.place ?? row.page.title).font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                SettingsIcon(page: row.page)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.search.\(row.id)")
                    }
                }
            }
            .overlay {
                if !search.isEmpty, SettingsSearch.matches(search).isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            // The list's content margins draw no room under the search field.
            .safeAreaPadding(.top, 6)
            .searchable(text: $search, placement: .sidebar)
            .toolbar(removing: .sidebarToggle)
            .accessibilityIdentifier("settings.sidebar")
            .navigationSplitViewColumnWidth(215)
        } detail: {
            NavigationStack(path: $route.path) {
                SettingsPageView(page: route.page ?? .general)
                    .navigationDestination(for: SettingsDetail.self) { detail in
                        switch detail {
                        case let .machine(id): MachinePage(id: id)
                        case let .plugin(id): PluginPage(id: id)
                        }
                    }
            }
        }
        .frame(width: 715).frame(minHeight: 400)
        .environment(\.look, Look(style: settings.style, dark: colorScheme == .dark,
                                  contrast: colorSchemeContrast == .increased))
    }
}

private struct SettingsIcon: View {
    let page: SettingsPage
    @Environment(\.look) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Image(systemName: page.symbol).font(.system(size: 13, weight: .medium)).imageScale(.medium)
            .symbolVariant(.fill).symbolRenderingMode(.hierarchical)
            .foregroundStyle(look.settingsGlyph)
            .frame(width: 22, height: 22)
            .background(LinearGradient(colors: look.settingsFill, startPoint: .top, endPoint: .bottom), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: look.settingsEdge, startPoint: .top, endPoint: .bottom),
                                        lineWidth: 0.5))
            .shadow(color: look.settingsShadow, radius: 0.5, y: 0.5)
            .compositingGroup()
    }
}

private struct SettingsSidebarRow: View {
    let page: SettingsPage

    var body: some View {
        Label { Text(page.title) } icon: { SettingsIcon(page: page) }
            .tag(page)
            .accessibilityIdentifier("settings.page.\(page.rawValue)")
    }
}

private struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        Group {
            switch page {
            case .general: GeneralPage()
            case .appearance: AppearancePage()
            case .terminal: TerminalPage()
            case .agents: AgentsPage()
            case .machines: MachinesPage()
            case .plugins: PluginsPage()
            case .privacy: PrivacyPage()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(page.title)
        // With no toolbar item the window has a bare title bar: traffic lights in the corner, square corners.
        .toolbar { ToolbarSpacer(.fixed) }
        .scrollsToRing()
    }
}

/// Each page has its own: the sidebar page's proxy cannot reach a page pushed over it.
private struct RingScroll: ViewModifier {
    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.task(id: SettingsRoute.shared.ring) {
                guard let ring = SettingsRoute.shared.ring else { return }
                // After the page's first layout: its rows are there to scroll to.
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(Animation.reduced ? nil : .default) { proxy.scrollTo(ring, anchor: .center) }
                try? await Task.sleep(for: .seconds(1))
                if SettingsRoute.shared.ring == ring {
                    SettingsRoute.shared.ring = nil
                }
            }
        }
    }
}

extension View {
    func scrollsToRing() -> some View {
        modifier(RingScroll())
    }

    func settingsRow(_ id: String) -> some View {
        modifier(SettingsRow(id: id))
    }

    func identifiedSettingsRow(_ id: String) -> some View {
        accessibilityIdentifier("settings." + id).settingsRow(id)
    }
}

private struct SettingsRow: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content.id(id).background {
            if SettingsRoute.shared.ring == id {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).padding(-6)
            }
        }
    }
}

struct SettingsSearch: Identifiable {
    let id: String, title: String, page: SettingsPage
    var words = ""
    var detail: SettingsDetail?
    var place: String?

    static let app = [
        SettingsSearch(id: "general.open-at-login", title: "Open at login", page: .general,
                       words: "startup launch login items"),
        SettingsSearch(id: "general.new-pane", title: "New panes open", page: .general,
                       words: "default split tab terminal agent browser explorer git plugin chooser"),
        SettingsSearch(id: "general.follow-mouse", title: "Focus follows mouse", page: .general, words: "pane hover"),
        SettingsSearch(id: "general.shortcuts", title: "Keyboard shortcuts", page: .general, words: "keys help"),
        SettingsSearch(id: "general.welcome", title: "Welcome to Ovvi", page: .general,
                       words: "onboarding intro tour help getting started herdr install"),
        SettingsSearch(id: "appearance.appearance", title: "Appearance", page: .appearance,
                       words: "auto light dark theme mode"),
        SettingsSearch(id: "appearance.style", title: "Interface style", page: .appearance,
                       words: "glass classic"),
        SettingsSearch(id: "appearance.font-size", title: "Text size", page: .appearance, words: "font bigger"),
        SettingsSearch(id: "terminal.font", title: "Font", page: .terminal, words: "typeface monospaced"),
        SettingsSearch(id: "terminal.cursor", title: "Cursor", page: .terminal, words: "block bar underline"),
        SettingsSearch(id: "terminal.blink", title: "Blink the cursor", page: .terminal),
        SettingsSearch(id: "terminal.option", title: "Option key", page: .terminal, words: "meta alt emacs"),
        SettingsSearch(id: "terminal.copy", title: "Copy text when you select it", page: .terminal,
                       words: "clipboard selection"),
        SettingsSearch(id: "agents.view", title: "Open new agents in", page: .agents, words: "chat terminal tui"),
        SettingsSearch(id: "agents.sort", title: "Sort spaces", page: .agents,
                       words: "sidebar order manual recent workspaces"),
        SettingsSearch(id: "agents.closed", title: "Show closed sessions", page: .agents,
                       words: "sidebar archived sessions resume history"),
        SettingsSearch(id: "agents.new-pane", title: "Agents in New Pane", page: .agents,
                       words: "arguments flags claude codex pi opencode"),
        SettingsSearch(id: "agents.needs-you", title: "When an agent needs you", page: .agents,
                       words: "notifications"),
        SettingsSearch(id: "agents.finished", title: "When an agent finishes", page: .agents,
                       words: "notifications done"),
        SettingsSearch(id: "agents.from-agents", title: "When an agent sends one", page: .agents,
                       words: "notifications notify"),
        SettingsSearch(id: "machines.list", title: "Machines", page: .machines, words: "remote ssh host add"),
        SettingsSearch(id: "privacy.websites", title: "Approved websites", page: .privacy,
                       words: "browser sites privacy allowlist add"),
    ]

    static func matches(_ text: String) -> [SettingsSearch] {
        let typed = text.lowercased().split(separator: " ")
        return (app + PluginsPage.searchRows).filter { row in
            let words = "\(row.title) \(row.words) \(row.place ?? row.page.title)".lowercased()
            return typed.allSatisfy { words.contains($0) }
        }
    }
}

struct SettingsHeader<Icon: View, Actions: View>: View {
    let title: String
    var note: String?
    var lines: [String] = []
    @ViewBuilder var icon: Icon
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    if let note {
                        Text(note).foregroundStyle(.secondary)
                    }
                }
                let shown = lines.filter { !$0.isEmpty }
                ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                    let last = index == shown.count - 1
                    Text(line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(last ? 1 : 2)
                        .truncationMode(last ? .middle : .tail)
                }
            }
            Spacer(minLength: 8)
            actions.controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

extension SettingsHeader where Actions == EmptyView {
    init(title: String, note: String? = nil, lines: [String] = [], @ViewBuilder icon: () -> Icon) {
        self.init(title: title, note: note, lines: lines, icon: icon, actions: { EmptyView() })
    }
}
