import HerdrKit
import SwiftUI

/// A window's view until it shows a session (ui/window#new-window): Ovvi's icon and name over one glass list of every
/// machine's sessions, running first, each machine's New Session, then Add Machine and Edit Machines. A window shows
/// it whenever it would otherwise connect by itself: at launch with nothing to restore, on ⌘N, when the app reopens
/// with
/// no window. A pick opens that session as the window's first page. A machine whose sessions cannot be read lists the
/// row that fixes it (Install herdr, Connect).
struct SessionPicker: View {
    let pages: WindowPages
    /// Each machine's sessions by id, once read; an error when they could not be.
    @State private var read: [String: Result<[Session], Error>] = [:]
    /// New Session's name when nothing is typed, picked once.
    @State private var suggested = [Session]().newName
    @State private var fullScreen = false
    @State private var lightsOff = 0
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(pages: WindowPages) {
        self.pages = pages
    }

    /// A run against a throwaway session (`-session`, a test's `-defaultSession`) lists only throwaway ones, never the
    /// user's, and its fix rows open that session, not `default`.
    private static let throwaway: String? = {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        return (arguments["session"] ?? arguments["defaultSession"]) as? String
    }()

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text("Ovvi").font(.system(size: 22, weight: .semibold)).padding(.top, 8)
                .accessibilityIdentifier("picker.title")
            // The machine rows stay in view under the scrolled sessions; the panel's 8 pt goes round them too.
            FilterList(prompt: "Find a session", name: "picker", items: items, maxHeight: 420, pinned: 2) {}
                .padding(8)
                .frame(width: 440)
                .floatingGlass(in: .rect(cornerRadius: 14))
                .padding(.top, 24)
        }
        // The column's middle a title row above the window's: it sits in the middle of the room under the title row.
        .padding(.bottom, TitleBar.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let machine = pages.hostDialog {
                HostDialog(pages: pages, machine: machine).dialog()
            }
        }
        .environment(\.look, look)
        // Again for a machine added meanwhile.
        .task(id: machines.map(\.id)) { await readAll() }
        .windowChrome(look)
        .background(WindowReader(pages: pages, fullScreen: $fullScreen, lightsOff: $lightsOff))
        .navigationTitle("Ovvi")
        // A field's Esc goes on to here: the window closes, as nothing else in it has Esc.
        .onExitCommand { pages.window?.performClose(nil) }
    }

    private var machines: [Machine] {
        [.thisMac] + MachineList.shared.list
    }

    /// Every machine at once; each shows as soon as it answers, and within 15 s whatever the others do: a read can wait
    /// on another window's ssh question (`SSHExec.up`) or a slow login, and then says so instead of spinning.
    private func readAll() async {
        let unread = machines.filter { read[$0.id] == nil }
        let reads = unread.map { machine in
            Task {
                let result = await Self.sessions(on: machine)
                if read[machine.id] == nil {
                    read[machine.id] = result
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
        let client = await HerdrClient(session: "default", exec: machine.exec())
        do {
            return try await .success(client.sessions())
        } catch {
            return .failure(error)
        }
    }

    /// A group per machine: its running sessions, then its stopped ones, then New Session; a spinner row while it
    /// reads, or the row that fixes why it cannot. Add Machine and Edit Machines stay at the foot.
    private func items(_ filter: String) -> [FilterList.Item] {
        let typed = filter.trimmingCharacters(in: .whitespaces)
        let sessions = machines.flatMap { machine -> [FilterList.Item] in
            switch read[machine.id] {
            case nil:
                return [row(machine, "reading", machine.icon, "", title: "Reading sessions…", busy: true) {}]
            case let .failure(error):
                let fallback = Self.throwaway ?? "default"
                return switch error as? HerdrError {
                case .notFound:
                    [row(machine, "install", "shippingbox", "herdr is not installed", title: "Install herdr") {
                        pick(fallback, on: machine)
                        Task { await HerdrInstall.shared.install(on: machine, session: fallback) }
                    }]
                case .disconnected:
                    [row(machine, "connect", "network.slash", "Not connected", title: "Connect") {
                        pick(fallback, on: machine)
                        if let store = pages.current?.store {
                            Task { await store.connect(in: pages) }
                        }
                    }]
                default:
                    [row(machine, "default", machine.isRemote ? "network.slash" : "exclamationmark.triangle",
                         error.localizedDescription) { pick(fallback, on: machine) }]
                }
            case let .success(sessions):
                let shown = sessions.filter { Self.throwaway == nil || $0.name.hasPrefix("ovvi-") }
                let rows = (shown.filter(\.running) + shown.filter { !$0.running }).filter { $0.name.matches(filter) }
                    .map { session in
                        row(machine, session.name, "rectangle.stack", session.running ? "Running" : "Stopped") {
                            pick(session.name, on: machine)
                        }
                    }
                // A typed name no session of the machine has, else a free one.
                let name = typed.isEmpty ? suggested : typed
                let fresh = Session.isValidName(name) && !sessions.contains { $0.name == name }
                return rows + (fresh ? [row(machine, "new", "plus", "", title: typed.isEmpty ? "New Session"
                        : "New Session “\(name)”") { pick(name, on: machine, start: true) }] : [])
            }
        }
        let machineRows = [
            FilterList.Item(id: "add-machine", symbol: "plus.circle", title: "Add Machine…", section: "") {
                pages.hostDialog = Machine(id: UUID().uuidString, name: "", target: "", icon: "server.rack")
            },
            FilterList.Item(id: "edit-machines", symbol: "gearshape", title: "Edit Machines…", section: "") {
                SettingsRoute.shared.open(.machines)
            },
        ]
        return sessions + machineRows
    }

    /// A row of the machine's group, `<machine id>.<name>`.
    private func row(_ machine: Machine, _ name: String, _ symbol: String, _ detail: String, title: String? = nil,
                     busy: Bool = false, act: @escaping () -> Void) -> FilterList.Item
    {
        FilterList.Item(id: "\(machine.id).\(name)", symbol: symbol, title: title ?? name, detail: detail,
                        section: machine.name, busy: busy, act: act)
    }

    /// The session opens in this window; on This Mac a stopped one starts, as Open Session does, and New Session
    /// starts its server on any machine.
    private func pick(_ session: String, on machine: Machine, start: Bool = false) {
        pages.machine = machine
        pages.open(session, start: start || !machine.isRemote)
        // Only now a window of the machine: floats, the Dock's New Tab and the machine menu find it once it has a page.
        pages.opened()
    }
}
