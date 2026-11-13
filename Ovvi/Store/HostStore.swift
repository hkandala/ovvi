import AppKit
import HerdrKit
import Observation

/// Snapshots land on stable objects keyed by id: Observation skips fields that do not change, so one status change
/// redraws one row.
@MainActor @Observable
final class HostStore {
    enum State: Equatable {
        case connecting, live
        case failed(HerdrError)
    }

    let session: String
    var machine: Machine
    private(set) var state = State.connecting
    /// A read failed and `failed` is finding out why: still `.live` until it knows.
    private(set) var checking = false
    private(set) var sessions: [Session] = []
    private(set) var workspaces: [Workspace] = []
    private(set) var panes: [Pane] = []
    /// Set only when it changes: a view of one tab reads its own.
    private(set) var tabPanes: [String: [Pane]] = [:]
    private(set) var waiting = 0
    private(set) var focusedWorkspaceID: String?
    var notice: Notice?
    /// Set by the notice's own hover: a notice under the pointer stays.
    @ObservationIgnored var noticeHovered = false
    /// The not-running page's reason, until the session answers or the next Start.
    var startProblem: String?
    var starting = false
    /// Until its first snapshot: a session found stopped starts as its Start does.
    @ObservationIgnored private var startStopped = false
    var flashing: String?
    var resuming: Set<String> = []
    var choosers: [Chooser] = []
    /// The session's sidebar (ui/window#sidebar), kept in the sidebar's defaults: its pinned spaces, its Sort Spaces
    /// (nil: Settings'), and whether it shows only the pinned spaces, which hides the others' states.
    var pins: Set<String> = [] {
        didSet {
            save("pinned", pins.sorted())
            if pins.isEmpty {
                onlyPinned = false
            } else if onlyPinned {
                showStates()
            }
        }
    }

    var order: SpaceOrder? {
        didSet { save("sorted", order.map { [$0.rawValue] } ?? []) }
    }

    var onlyPinned = false {
        didSet {
            save("only", onlyPinned ? ["pinned"] : [])
            showStates()
        }
    }

    @ObservationIgnored var chats: [String: Chat] = [:]
    /// Not observed: an observed write (`program`, `choosers`) follows each change.
    @ObservationIgnored var launches: [String: Launch] = [:]
    @ObservationIgnored let writes = Gate(1)
    var writing: Bool {
        writes.busy
    }

    @ObservationIgnored var ahead = Ahead()
    @ObservationIgnored private(set) var last: Snapshot?
    @ObservationIgnored private(set) var parked: [String: Pane] = [:]
    @ObservationIgnored var lookingTabID: String?
    @ObservationIgnored private var lookingKey: String? {
        didSet {
            if lookingKey != oldValue {
                seen.look(looking)
                showStates()
            }
        }
    }

    /// The controller first: the window where the user last typed or clicked in a card of the session.
    var windows: [WindowPages] = [] {
        // A space a closed window showed hides.
        didSet {
            if onlyPinned {
                showStates()
            }
        }
    }

    @ObservationIgnored var marked: Set<String> = []
    @ObservationIgnored var openMarked: Set<String> = []
    @ObservationIgnored var marking: Task<Void, Never>?
    var onScreen: Bool {
        windows.contains { $0.visible && $0.current?.store === self }
    }

    /// An error from ahead of a connect, whose session list waits for its start, does not show.
    @ObservationIgnored private var connecting = false
    @ObservationIgnored private var connects = 0
    @ObservationIgnored private(set) var client: (any Multiplexer)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored var gitReads: Set<String> = []
    /// By root, while a window follows the session's git (`followGit`).
    @ObservationIgnored var gitWatches: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var gitFollowers = 0
    @ObservationIgnored var gitEnded: Set<String> = []
    /// 8 at most: a 600-pane session's first snapshot makes 600 herdr runs.
    @ObservationIgnored let asks = Gate(8)
    @ObservationIgnored private var seen: Seen
    @ObservationIgnored private var marks: [String: Seen.Mark]

    private init(session: String, machine: Machine) {
        self.session = session
        self.machine = machine
        let saved = UserDefaults.sidebar.data(forKey: Self.marksKey(session, machine))
        marks = saved.flatMap { try? JSONDecoder().decode([String: Seen.Mark].self, from: $0) } ?? [:]
        seen = Seen(marks: marks)
        pins = Set(Self.saved("pinned", session, machine))
        order = Self.saved("sorted", session, machine).first.flatMap(SpaceOrder.init)
        onlyPinned = !Self.saved("only", session, machine).isEmpty
    }

    private(set) static var open: [String: HostStore] = [:]

    static func key(_ session: String, _ machine: Machine) -> String {
        "\(machine.id) \(session)"
    }

    static var all: [HostStore] {
        open.values.sorted { $0.session < $1.session }
    }

    static func named(_ session: String, on machine: Machine, start: Bool = false) -> HostStore {
        if let store = open[key(session, machine)] {
            return store
        }
        let store = HostStore(session: session, machine: machine)
        open[key(session, machine)] = store
        store.startStopped = start
        store.task = Task { await store.run() }
        return store
    }

    func disconnect() {
        task?.cancel()
        Self.open[Self.key(session, machine)] = nil
    }

    /// Only this may prompt for what ssh asks.
    func connect(in pages: WindowPages) async {
        guard machine.isRemote, !connecting else { return }
        connecting = true
        connects += 1
        if case .failed = state {
            state = .connecting
        }
        var failure: Error?
        do {
            try await (machine.exec() as? SSHExec)?.connect { question in await pages.ask(question) }
        } catch HerdrError.disconnected {
        } catch {
            failure = error
        }
        connecting = false
        // Its first check fails while the machine is not connected.
        pages.findAgents()
        await client?.refresh()
        if let failure {
            show(Notice(text: failure.localizedDescription))
        }
    }

    private func run() async {
        let client: any Multiplexer = await HerdrClient(session: session, exec: machine.exec())
        self.client = client
        defer { self.client = nil }
        var loadedSessions = false
        for await update in await client.updates() {
            switch update {
            case let .snapshot(snapshot):
                let start = Latency.threadTime
                balanceOthers(last, snapshot)
                let changes = apply(snapshot)
                state = .live
                startProblem = nil
                starting = false
                startStopped = false
                snapshotted(changes)
                Latency.shared.applied(since: start)
                // After the first snapshot, so the session list never delays the layout.
                if !loadedSessions {
                    loadedSessions = true
                    Task { [machine, session] in await machine.exec().pruneState(session: session) }
                    Task { [machine] in
                        if let script = AgentCommands.script {
                            await machine.exec().prepareAgent(script: script)
                        }
                    }
                    await loadSessions()
                }
            case let .request(id, pane):
                // ponytail: not cancelled with the store; its runs' timeouts and the float's 8 s wait end it.
                Task { await answer(request: id, from: pane) }
            case let .error(error):
                await failed(error)
            }
        }
    }

    private func failed(_ error: HerdrError) async {
        // Not while Connect runs, nor one that waits for its start: Connect's own read follows.
        let connects = connects
        guard !connecting else { return }
        // First, to tell "not running" from other failures without a flash of the other text. Meanwhile the cards
        // show no failure of their own (`PaneTerminal.live`).
        checking = true
        await loadSessions()
        checking = false
        guard connects == self.connects else { return }
        state = .failed(error)
        // Not a read that failed while the start still runs.
        if Self.starts[Self.key(session, machine)] == nil {
            starting = false
        }
        // Decided once, on the first read with a session list (herdr always lists `default`; a remote machine's
        // only once connected), so a later Stop is never undone. In this turn, so Start never draws first.
        if startStopped, !sessions.isEmpty, !Task.isCancelled {
            startStopped = false
            if !isRunning {
                starting = true
                Task { await start() }
            }
        }
        snapshotted([])
    }

    private func apply(_ snapshot: Snapshot) -> [Seen.Change] {
        // herdr's raw panes, so one made since the last snapshot stays.
        let gone = Set(last?.panes.compactMap(\.terminalID) ?? []).subtracting(snapshot.panes.compactMap(\.terminalID))
        drop(closed: gone)
        if !pins.isSubset(of: snapshot.workspaces.map(\.id)) {
            // herdr gives a new space an old id after a restart.
            pins.formIntersection(snapshot.workspaces.map(\.id))
        }
        last = snapshot
        let shown = ahead.show(snapshot)
        let tabs = Dictionary(grouping: shown.tabs, by: \.workspaceID)
        reuse(self, \.workspaces, shown.workspaces, Workspace.init(id:)) { workspace, new in
            workspace.label = new.label
            workspace.activeTabID = new.activeTabID
            workspace.worktree = new.worktree
            reuse(workspace, \.tabs, tabs[new.id] ?? [], Tab.init(id:)) { tab, new in
                tab.label = new.label
                tab.tree = shown.trees[new.id]
            }
        }
        focusedWorkspaceID = snapshot.focusedWorkspaceID
        let herdrs = Set(snapshot.panes.map(\.id))
        parked = parked.filter { herdrs.contains($0.key) }
        for pane in panes where ahead.closing.contains(pane.id) {
            parked[pane.id] = pane
        }
        let make = { self.parked.removeValue(forKey: $0) ?? Pane(id: $0) }
        // Once, not a new set for each pane: O(panes × tabs) per snapshot.
        let focused = snapshot.focusedPaneIDs
        reuse(self, \.panes, shown.panes, make) { pane, new in
            watchProgram(pane, new)
            remakeCard(pane, new)
            pane.agent = new.agent
            pane.terminalTitle = new.title
            pane.label = new.label
            pane.cwd = new.cwd
            pane.focused = focused.contains(new.id)
            pane.tabID = new.tabID
            pane.terminalID = new.terminalID
        }
        let grouped = Dictionary(grouping: panes, by: \.tabID)
        if grouped.mapValues({ $0.map(\.id) }) != tabPanes.mapValues({ $0.map(\.id) }) {
            tabPanes = grouped
        }
        let agents = Dictionary(snapshot.agents.map { ($0.paneID, $0) }, uniquingKeysWith: { first, _ in first })
        for pane in panes {
            pane.agentName = agents[pane.id].flatMap { $0.displayAgent ?? $0.agent }
            pane.changeSeq = agents[pane.id]?.stateChangeSeq
        }
        let changes = seen.update(snapshot.agents, looking: looking)
        showStates()
        closeArrived()
        Task { await updateGit(all: false) }
        return changes
    }
}

extension HostStore {
    private var looking: Set<String> {
        Set([lookingKey].compactMap(\.self))
    }

    /// A space Show Only Pinned Spaces hides shows no state, as if it were not there.
    func showStates() {
        let hidden = hidden
        let hiddenTabs = Set(workspaces.filter { hidden.contains($0.id) }.flatMap(\.tabs).map(\.id))
        for pane in panes {
            let key = Seen.key(terminalID: pane.terminalID, paneID: pane.id)
            pane.state = hiddenTabs.contains(pane.tabID) ? nil : seen.states[key]
            pane.since = seen.since[key]
        }
        showStrongest()
        keepMarks()
    }

    /// Kept here: views that read every pane's state redraw on any agent's change, every capsule and sidebar row.
    private func showStrongest() {
        for workspace in workspaces {
            for tab in workspace.tabs {
                let tabAgents = panes(in: tab.id).filter { $0.state != nil }
                let strongest = tabAgents.max { $0.state ?? .idle < $1.state ?? .idle }
                // Observation skips an equal value, but not an identical object.
                if tab.agent !== strongest {
                    tab.agent = strongest
                }
            }
            workspace.state = workspace.tabs.compactMap { $0.agent?.state }.max()
        }
        waiting = panes.count { $0.state == .needsYou }
    }

    private static func marksKey(_ session: String, _ machine: Machine) -> String {
        "agentMarks.\(machine.id) \(session)"
    }

    /// Only once a snapshot comes: until then they are empty.
    private func keepMarks() {
        guard last != nil, seen.marks != marks else { return }
        marks = seen.marks
        let key = Self.marksKey(session, machine)
        if marks.isEmpty {
            UserDefaults.sidebar.removeObject(forKey: key)
        } else {
            UserDefaults.sidebar.set(try? JSONEncoder().encode(marks), forKey: key)
        }
    }

    static func look(_ pane: Pane?, in store: HostStore) {
        let key = pane.map { Seen.key(terminalID: $0.terminalID, paneID: $0.id) }
        for other in all {
            other.lookingKey = other === store ? key : nil
        }
    }
}

let localExec = Task { await ProcessExec() }

extension HostStore {
    func panes(in tabID: String?) -> [Pane] {
        tabID.flatMap { tabPanes[$0] } ?? []
    }

    func pane(_ id: String) -> Pane? {
        panes.first { $0.id == id }
    }

    func terminalPane(_ id: String) -> Pane? {
        panes.first { $0.terminalID == id }
    }

    var isRunning: Bool {
        sessions.isEmpty || sessions.contains { $0.name == session && $0.running }
    }

    func loadSessions() async {
        guard let client, let listed = try? await client.sessions() else { return }
        sessions = listed
        KnownSessions.keep(listed, of: machine)
    }

    func redraw() {
        if let last {
            snapshotted(apply(last))
        }
    }
}
