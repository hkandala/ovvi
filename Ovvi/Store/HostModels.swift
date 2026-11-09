import Foundation
import HerdrKit
import Observation

/// The stable objects snapshots land on (see `HostStore`).
extension HostStore {
    enum Close {
        case pane(String)
        case tab(String)
        /// The other tabs of a workspace, or the ones to the right of a tab, as they were when the user asked: a tab
        /// made since is not closed.
        case otherTabs([String], right: Bool)
        /// A workspace, with its linked worktrees' workspaces when it has any.
        case workspace(String)

        var paneID: String? {
            if case let .pane(id) = self {
                id
            } else {
                nil
            }
        }
    }

    /// A close waiting for the user's yes, and the programs besides the shells that run in its panes.
    struct Closing {
        let close: Close
        let running: [String]
        /// Replace Pane's question: a new shell takes the pane's place.
        var replace: Replacement?
    }

    @MainActor @Observable
    final class Workspace: Identifiable {
        let id: String
        var label = ""
        var tabs: [Tab] = []
        /// herdr's active tab: a page's first selection in it.
        var activeTabID = ""
        var worktree: Worktree?
        /// Its tabs' strongest agent state (`HostStore.showStrongest`).
        var state: AgentState?
        /// The branch of its root (`worktree.checkout_path`, else its first pane's cwd); nil when not a repository.
        var git: GitStatus?
        /// The root of the last git run.
        @ObservationIgnored var gitRoot: String?

        init(id: String) {
            self.id = id
        }
    }

    @MainActor @Observable
    final class Tab: Identifiable {
        let id: String
        var label = ""
        var tree: SplitNode?
        /// Its agent pane with the strongest state (needs you > finished > working > idle) (`HostStore.showStrongest`).
        var agent: Pane?

        init(id: String) {
            self.id = id
        }
    }

    @MainActor @Observable
    final class Pane: Identifiable {
        let id: String
        var label: String?
        var cwd: String?
        /// The tab's focused pane, as herdr has it.
        var focused = false
        var tabID = ""
        var terminalID: String?
        /// herdr's agent kind, detected or reported.
        var agent: String?
        /// The terminal title without herdr's status glyphs.
        var terminalTitle: String?
        /// Its agent's state (D14); nil without an agent.
        var state: AgentState?
        /// When the app saw the state change, for the working time.
        var since: Date?
        /// herdr's `state_change_seq`: a workspace's agent rows list the newest change first.
        var changeSeq: Int?
        /// The agent's name: herdr's `display_agent`, else its kind.
        var agentName: String?
        /// Its agent's session (herdr's `agent_session` value, of this agent), and that session's title (`watchTitle`).
        var session: String?
        var sessionTitle: String?
        /// What the last title read was for.
        @ObservationIgnored var titleKey: String?
        /// What runs in the foreground (the shell when nothing else does), from the last `pane.process_info`.
        var program: Program?
        /// The card of a plugin not on this Mac shows the pane's placeholder terminal: the user asked for it.
        var placeholder = false
        /// The shell process the placeholder was typed into, and the terminal looked at again (`keepPlaceholder`).
        @ObservationIgnored var placed: Int?
        @ObservationIgnored var rechecked: String?
        /// A card pane herdr brought back without its folder was made again (`remakeCard`).
        @ObservationIgnored var remade = false
        /// The label its placeholder last drew (`redrawPlaceholder`).
        @ObservationIgnored var drawnLabel: String?
        /// Relaunch with Chat restarted its agent: the user asked for the chat, so it shows first.
        @ObservationIgnored var relaunched = false
        /// herdr was asked for the program at least once.
        @ObservationIgnored var asked = false
        /// Asks made, so only the latest answer lands.
        @ObservationIgnored var asks = 0
        /// A new pane's first second, when no ask is made: its shell's startup runs short-lived programs (`gh auth
        /// token`, `brew shellenv` in a .zshrc), and an answer then showed their icons before the shell's.
        @ObservationIgnored var starting = false

        init(id: String) {
            self.id = id
        }

        /// The directory, `~` for home.
        var folder: String? {
            cwd.map { ($0 as NSString).abbreviatingWithTildeInPath }
        }

        /// A browser pane's label (ui/browser): the pane's kind.
        var browser: PaneLabel? {
            plugin.flatMap { $0.plugin == Registry.browser.id ? $0 : nil }
        }

        /// The card header's parts: the label alone, else the program and the folder, as in Rex ("zsh", "~"). A
        /// browser's address or a plugin's argument, not its label.
        var header: (name: String?, folder: String) {
            if let plugin {
                return (nil, plugin.arg.isEmpty ? plugin.manifest?.name ?? plugin.plugin : plugin.arg)
            }
            let name = label == nil ? programName : nil
            return (name, label ?? folder ?? (name == nil ? "terminal" : ""))
        }

        var cardTitle: String {
            let (name, folder) = header
            return [name, folder].plainTitle
        }

        /// The program's name for the card header: herdr's agent, else the foreground process ("zsh" for the shell).
        var programName: String? {
            agent ?? program?.title
        }

        /// An agent pane's name (ui/chat-view): the user's herdr label, else its session's title; nil for other panes.
        var agentTitle: String? {
            agent == nil ? nil : label ?? sessionTitle ?? "Untitled"
        }

        /// The agent's name as people know it ("Claude Code"): the chooser's, else herdr's.
        var agentLabel: String? {
            Chooser.agents.first { $0.command == agent }?.name ?? agentName
        }

        /// The placeholder icon's letter.
        var letter: String? {
            programName?.prefix(1).uppercased()
        }

        /// Its program icon's catalog id.
        var iconID: String {
            plugin?.symbol ?? programIcons.iconID(agent: agent, program: program, title: terminalTitle)
        }
    }
}

extension HostStore {
    /// The machine's name, with the session's unless it is `default`.
    var name: String {
        session == "default" ? machine.name : "\(machine.name) · \(session)"
    }

    /// The sidebar's title: the machine's name for its `default` session, This Mac's own name for This Mac's;
    /// else the session's.
    var title: String {
        guard session == "default" else { return session }
        return machine.isRemote ? machine.name : Machine.computerName
    }

    /// The session in a notification or a Dock row: a remote one with its machine.
    var label: String {
        machine.isRemote ? name : session
    }

    /// Failed while its server runs, not for a missing or old herdr: the client tries again every 2 s.
    var reconnecting: Bool {
        guard case let .failed(error) = state else { return false }
        switch error {
        case .notFound, .unsupported, .disconnected: return false
        default: return isRunning
        }
    }

    func workspace(of tabID: String) -> Workspace? {
        workspaces.first { $0.tabs.contains { $0.id == tabID } }
    }

    /// The workspace of the repository a linked worktree's workspace sits under: the first one with the same
    /// `repo_key` that is not a linked worktree.
    func parent(of workspace: Workspace) -> Workspace? {
        guard let worktree = workspace.worktree, worktree.isLinkedWorktree else { return nil }
        return workspaces.first { $0.worktree?.repoKey == worktree.repoKey && $0.worktree?.isLinkedWorktree == false }
    }

    func worktrees(of workspaceID: String) -> [Workspace] {
        workspaces.filter { parent(of: $0)?.id == workspaceID }
    }

    /// The sidebar's rows in groups: each workspace in herdr's order, its linked worktrees right after it.
    /// One pass: a parent looked up for each workspace read every workspace's worktree for each, 40,000 observed reads
    /// at 200 spaces in each sidebar update.
    var groups: [[Workspace]] {
        var heads: [String: Workspace] = [:], tops: [Workspace] = [], under: [String: [Workspace]] = [:]
        for workspace in workspaces {
            if let worktree = workspace.worktree, !worktree.isLinkedWorktree, heads[worktree.repoKey] == nil {
                heads[worktree.repoKey] = workspace
            }
        }
        for workspace in workspaces {
            if let worktree = workspace.worktree, worktree.isLinkedWorktree, let head = heads[worktree.repoKey] {
                under[head.id, default: []].append(workspace)
            } else {
                tops.append(workspace)
            }
        }
        return tops.map { [$0] + (under[$0.id] ?? []) }
    }
}

extension HostStore {
    /// Starts the session's server when it is not running (a launchd job, D47); a server started here gets
    /// its first workspace in home, as a new one has none.
    /// A second start of a session (a double click on Start, Open Session) joins the one in flight: on its own it
    /// would find the booting server silent and boot it out.
    static func start(_ session: String, on machine: Machine) async throws {
        let key = key(session, machine)
        let start = starting[key] ?? Task {
            // herdr is the only multiplexer (design D49).
            let client: any Multiplexer = await HerdrClient(session: session, exec: machine.exec())
            // `-startTimeout 0` makes every start fail, for e2e.
            let timeout = UserDefaults.standard.double(forKey: "startTimeout")
            if try await client.startServer(within: .seconds(timeout)),
               try await client.snapshot().workspaces.isEmpty
            {
                let pane = try await client.newWorkspace(label: nil, cwd: "~")
                all.first { Self.key($0.session, $0.machine) == key }?.choose(pane, fixed: true)
            }
        }
        starting[key] = start
        // Not a newer start that began as this one ended.
        defer { starting[key] = starting[key] == start ? nil : starting[key] }
        try await start.value
    }

    private static var starting: [String: Task<Void, Error>] = [:]

    /// The Start button of a session that stopped: the running store finds it again.
    func start() async {
        do {
            try await Self.start(session, on: machine)
            await client?.refresh()
        } catch {
            await show(Notice(text: error.localizedDescription))
        }
    }
}

/// Keeps the object of each id that stays, makes the new ones, and replaces the list only when its
/// ids changed, so views of the list redraw only then.
@MainActor
func reuse<Owner: AnyObject, Object: Identifiable<String>, Item: Identifiable<String>>(
    _ owner: Owner,
    _ list: ReferenceWritableKeyPath<Owner, [Object]>,
    _ items: [Item],
    _ make: (String) -> Object,
    _ update: (Object, Item) -> Void,
) {
    let old = Dictionary(owner[keyPath: list].map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let new = items.map { item in
        let object = old[item.id] ?? make(item.id)
        update(object, item)
        return object
    }
    if new.map(\.id) != owner[keyPath: list].map(\.id) {
        owner[keyPath: list] = new
    }
}

extension [String?] {
    /// A title's parts where it shows as plain text (⌘K, menus, window titles): with no dimmed part, a bar
    /// separates them ("Browser | Hacker News").
    var plainTitle: String {
        compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " | ")
    }
}
