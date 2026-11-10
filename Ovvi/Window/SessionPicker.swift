import HerdrKit
import SwiftUI

struct SessionPicker: View {
    let pages: WindowPages
    @State private var read: [String: Result<[Session], Error>] = [:]
    @State private var slow = false
    @State private var room: CGFloat = 900
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(pages: WindowPages) {
        self.pages = pages
    }

    /// A run against a throwaway session (`-session`, a test's `-defaultSession`) lists only throwaway ones, never the
    /// user's.
    private static let throwaway = MachineList.session ?? MachineList.defaultSession

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text("Ovvi").font(.system(size: 22, weight: .semibold)).padding(.top, 8)
            FilterList(
                prompt: "Find a session",
                name: "picker",
                items: items,
                maxHeight: min(420, max(120, room - 400)),
                pinned: 2,
            ) {}
                .padding(8)
                .frame(width: 440)
                .floatingGlass(in: .panel)
                .padding(.top, 24)
        }
        .padding(.bottom, TitleBar.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { room = $0 }
        .environment(\.look, look)
        .task(id: MachineList.shared.all.map(\.id)) { await readAll() }
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            slow = true
        }
        .windowChrome(look)
        .background(WindowReader(pages: pages, fullScreen: .constant(false), lightsOff: .constant(0)))
        .navigationTitle("Ovvi")
        .onAppear { WindowPages.takeAsked = takeAsked }
        .onDisappear { WindowPages.takeAsked = nil }
        .onExitCommand { pages.window?.performClose(nil) }
    }

    /// Within 15 s whatever the others do: a read can wait on another window's ssh question (`SSHExec.up`) or a slow
    /// login.
    private func readAll() async {
        let unread = MachineList.shared.all.filter { read[$0.id] == nil }
        let reads = unread.map { machine in
            Task {
                let result = await Self.sessions(on: machine)
                if read[machine.id] == nil {
                    read[machine.id] = result
                    switch result {
                    case let .success(sessions): KnownSessions.keep(sessions, of: machine)
                    case .failure(HerdrError.disconnected): KnownSessions.forget(machine)
                    case .failure: break
                    }
                }
            }
        }
        let closed = await (try? Task.sleep(for: .seconds(15))) == nil
        reads.forEach { $0.cancel() }
        guard !closed else { return }
        for machine in unread where read[machine.id] == nil {
            read[machine.id] = .failure(HerdrError.failed("No answer within 15 s"))
        }
    }

    private static func sessions(on machine: Machine) async -> Result<[Session], Error> {
        let client = await HerdrClient(session: Session.defaultName, exec: machine.exec())
        do {
            return try await .success(client.sessions())
        } catch {
            return .failure(error)
        }
    }

    private func items(_ filter: String) -> [FilterList.Item] {
        let typed = filter.trimmingCharacters(in: .whitespaces)
        let groups = MachineList.shared.all.map { machine in
            let (rows, sessions) = group(machine, typed: typed)
            let kept = typed.isEmpty || machine.name.matches(filter) ? rows
                : rows.filter { sessions.contains($0.id) || $0.id.hasSuffix(".+new") }
            return (rows: kept, matched: !typed.isEmpty && (!sessions.isEmpty || machine.name.matches(filter)))
        }
        let sessions = (groups.filter(\.matched) + groups.filter { !$0.matched }).flatMap(\.rows)
        return sessions + [
            FilterList.Item(id: "+add-machine", symbol: "plus.circle", title: "Add Machine…", section: "") {
                SettingsRoute.shared.open(.machines, .machine(MachinePage.new))
            },
            FilterList.Item(id: "+edit-machines", symbol: "gearshape", title: "Edit Machines…", section: "") {
                SettingsRoute.shared.open(.machines)
            },
        ]
    }

    /// The app's own rows' ids start with `+`, which no session name has.
    private func group(_ machine: Machine, typed: String) -> ([FilterList.Item], Set<String>) {
        let fallback = Self.throwaway ?? Session.defaultName
        switch read[machine.id] ?? KnownSessions.of(machine).map(Result.success) {
        case nil:
            var reading = row(
                machine,
                "+reading",
                machine.icon,
                "",
                title: slow ? "Reading sessions…" : "",
                busy: slow,
            ) {}
            reading.symbol = slow ? machine.icon : nil
            return ([reading], [])
        case let .failure(error):
            return ([fix(machine, error, fallback: fallback)], [])
        case let .success(sessions):
            let shown = sessions.filter { Self.throwaway == nil || $0.name.hasPrefix("ovvi-") }
            var rows = (shown.filter(\.running) + shown.filter { !$0.running }).map { session in
                row(machine, session.name, "rectangle.stack", session.running ? "Running" : "Stopped") {
                    pick(session.name, on: machine)
                }
            }
            let matched = Set(rows.filter { $0.title.matches(typed) }.map(\.id))
            let fresh = typed.isEmpty ? Self.throwaway == nil
                : Session.isValidName(typed) && !sessions.contains { $0.name == typed }
                && (Self.throwaway == nil || typed.hasPrefix("ovvi-"))
            if fresh {
                let title = typed.isEmpty ? "New Session" : "New Session “\(typed)”"
                let new = row(machine, "+new", "plus", "", title: title) {
                    pick(typed.isEmpty ? sessions.newName : typed, on: machine, start: true)
                }
                rows.append(new)
            }
            return (rows, matched)
        }
    }

    private func fix(_ machine: Machine, _ error: Error, fallback: String) -> FilterList.Item {
        switch error as? HerdrError {
        case .notFound:
            row(machine, "+install", "shippingbox", "herdr is not installed", title: "Install herdr") {
                pick(fallback, on: machine)
                Task { await HerdrInstall.shared.install(on: machine, session: fallback) }
            }
        case .disconnected:
            row(machine, "+connect", "network.slash", "Not connected", title: "Connect") {
                pick(fallback, on: machine)
                if let store = pages.current?.store {
                    Task { await store.connect(in: pages) }
                }
            }
        default:
            row(machine, "+default", machine.isRemote ? "network.slash" : "exclamationmark.triangle",
                error.localizedDescription, title: fallback) { pick(fallback, on: machine) }
        }
    }

    private func row(_ machine: Machine, _ name: String, _ symbol: String, _ detail: String, title: String? = nil,
                     busy: Bool = false, act: @escaping () -> Void) -> FilterList.Item
    {
        FilterList.Item(id: "\(machine.id).\(name)", symbol: symbol, title: title ?? name, detail: detail,
                        section: machine.name, busy: busy, act: act)
    }

    private func takeAsked() {
        guard let asked = WindowPages.asked, let machine = MachineList.shared.machine(asked.machine) else { return }
        pick(asked.session, on: machine)
    }

    private func pick(_ session: String, on machine: Machine, start: Bool = false) {
        pages.machine = machine
        pages.open(session, start: start || !machine.isRemote)
        pages.opened()
    }
}
