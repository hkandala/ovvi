import HerdrKit
import SwiftUI

/// A new window's first view (File ▸ New Window, ⌘N): every machine and its sessions, on the Open Session panel's
/// glass. It connects to nothing by itself; a pick opens that session as the window's first page. A machine whose
/// sessions it cannot read (no herdr, one that needs a password) opens its `default` page, which says why and shows
/// the button that fixes it.
struct SessionPicker: View {
    let pages: WindowPages
    /// Each machine's sessions by id, once read; an error when they could not be.
    @State private var read: [String: Result<[Session], Error>] = [:]
    @State private var fullScreen = false
    @State private var lightsOff = 0
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(pages: WindowPages) {
        self.pages = pages
    }

    /// A run against a throwaway session (`-session`) lists only throwaway ones, never the user's.
    private static let throwaway = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        .keys.contains("session")

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        VStack(spacing: 16) {
            EmptyState(symbol: "macwindow.badge.plus", title: "Open a Session", id: "picker.title")
            FilterList(prompt: "Find a session", name: "picker", items: items, maxHeight: 360, inset: 8) {}
                .padding([.horizontal, .top], 8)
                .frame(width: 420)
                .floatingGlass(in: .rect(cornerRadius: 14))
        }
        .padding(.bottom, TitleBar.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.look, look)
        .task { await readAll() }
        .windowChrome(look)
        .background(WindowReader(pages: pages, fullScreen: $fullScreen, lightsOff: $lightsOff))
        .navigationTitle("New Window")
    }

    private var machines: [Machine] {
        [.thisMac] + MachineList.shared.list
    }

    /// Every machine at once; each shows as soon as it answers.
    private func readAll() async {
        await withTaskGroup(of: (String, Result<[Session], Error>).self) { group in
            for machine in machines {
                let exec = await machine.exec()
                group.addTask {
                    let client = HerdrClient(session: "default", exec: exec)
                    do {
                        return try await (machine.id, .success(client.sessions()))
                    } catch {
                        return (machine.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                read[id] = result
            }
        }
    }

    /// A group per machine: its running sessions, then its stopped ones; a spinner row while it reads.
    private func items(_ filter: String) -> [FilterList.Item] {
        machines.flatMap { machine -> [FilterList.Item] in
            switch read[machine.id] {
            case nil:
                return [row(machine, "reading", machine.icon, "", title: "Reading sessions…", busy: true) {}]
            case let .failure(error):
                let why = (error as? HerdrError) == .notFound ? "herdr is not installed" : "Not connected"
                return [row(machine, "default", machine.icon, why) { pick("default", on: machine) }]
            case let .success(sessions):
                let shown = sessions.filter { !Self.throwaway || $0.name.hasPrefix("ovvi-") }
                    .map { ($0.name, $0.running) }
                // A Mac or machine with no session yet: its `default`, made by the pick.
                let listed = shown.isEmpty && !Self.throwaway ? [("default", false)] : shown
                return (listed.filter(\.1) + listed.filter { !$0.1 }).filter { $0.0.matches(filter) }
                    .map { name, running in
                        row(machine, name, "rectangle.stack", running ? "Running" : "Stopped") {
                            pick(name, on: machine)
                        }
                    }
            }
        }
    }

    /// A row of the machine's group, `<machine id>.<name>`: a session's, or its spinner.
    private func row(_ machine: Machine, _ name: String, _ symbol: String, _ detail: String, title: String? = nil,
                     busy: Bool = false, act: @escaping () -> Void) -> FilterList.Item
    {
        FilterList.Item(id: "\(machine.id).\(name)", symbol: symbol, title: title ?? name, detail: detail,
                        section: machine.name, busy: busy, act: act)
    }

    /// The session opens in this window; on This Mac a stopped one starts, as Open Session does.
    private func pick(_ session: String, on machine: Machine) {
        pages.machine = machine
        pages.open(session, start: !machine.isRemote)
    }
}
