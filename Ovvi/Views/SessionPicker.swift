import HerdrKit
import SwiftUI

/// A window's view until it shows a session (ui/window#new-window): Ovvi's icon and name over one glass list of every
/// machine's sessions, running first, each machine's New Session, then Add Machine and Edit Machines. A window shows
/// it whenever it would otherwise connect by itself: at launch with nothing to restore, on ⌘N, when the app reopens
/// with no window. A pick opens that session as the window's first page. A machine whose sessions cannot be read lists
/// the
/// row that fixes it (Install herdr, Connect).
struct SessionPicker: View {
    let pages: WindowPages
    /// Each machine's sessions by id, once read; an error when they could not be.
    @State private var read: [String: Result<[Session], Error>] = [:]
    @State private var fullScreen = false
    @State private var lightsOff = 0
    /// The window's content height: the list gets what the icon, the name and the panel's own rows leave.
    @State private var room: CGFloat = 900
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
            FilterList(
                prompt: "Find a session",
                name: "picker",
                items: items,
                maxHeight: min(420, max(120, room - 400)),
                pinned: 2,
            ) {}
                .padding(8)
                .frame(width: 440)
                .floatingGlass(in: .rect(cornerRadius: 14))
                .padding(.top, 24)
        }
        // Lifted by a title row's height, so the column centers in the room under the title row.
        .padding(.bottom, TitleBar.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { room = $0 }
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
    /// reads, or the row that fixes why it cannot. Typed text keeps the sessions it matches (and a machine's other
    /// rows when it matches the machine's name), the machines with a match first, so Return opens the first match.
    /// Add Machine and Edit Machines stay at the foot.
    private func items(_ filter: String) -> [FilterList.Item] {
        let typed = filter.trimmingCharacters(in: .whitespaces)
        let groups = machines.map { machine in
            let (rows, sessions) = group(machine, typed: typed)
            let kept = typed.isEmpty || machine.name.matches(filter) ? rows
                : rows.filter { sessions.contains($0.id) || $0.id.hasSuffix(".+new") }
            return (rows: kept, matched: !typed.isEmpty && !sessions.isEmpty)
        }
        // A stable sort: the machine order stays inside each half.
        let sessions = (groups.filter(\.matched) + groups.filter { !$0.matched }).flatMap(\.rows)
        return sessions + [
            FilterList.Item(id: "+add-machine", symbol: "plus.circle", title: "Add Machine…", section: "") {
                pages.hostDialog = .new
            },
            FilterList.Item(id: "+edit-machines", symbol: "gearshape", title: "Edit Machines…", section: "") {
                SettingsRoute.shared.open(.machines)
            },
        ]
    }

    /// The machine's rows, and the ids of the sessions a typed name matches. The app's own rows' ids start with `+`,
    /// which no session name has.
    private func group(_ machine: Machine, typed: String) -> ([FilterList.Item], Set<String>) {
        let fallback = Self.throwaway ?? "default"
        switch read[machine.id] {
        case nil:
            return ([row(machine, "+reading", machine.icon, "", title: "Reading sessions…", busy: true) {}], [])
        case let .failure(error):
            let fix = switch error as? HerdrError {
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
            return ([fix], [])
        case let .success(sessions):
            let shown = sessions.filter { Self.throwaway == nil || $0.name.hasPrefix("ovvi-") }
            var rows = (shown.filter(\.running) + shown.filter { !$0.running }).map { session in
                row(machine, session.name, "rectangle.stack", session.running ? "Running" : "Stopped") {
                    pick(session.name, on: machine)
                }
            }
            let matched = Set(rows.filter { $0.title.matches(typed) }.map(\.id))
            // A typed name no session of the machine has, else a free one picked as it starts. A throwaway run makes
            // only typed throwaway names.
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
