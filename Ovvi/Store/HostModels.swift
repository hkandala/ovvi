import Foundation
import HerdrKit
import Observation

extension HostStore {
    enum Close {
        case pane(String)
        case tab(String)
        /// The tabs at the user's ask: a tab made since is not closed.
        case otherTabs([String], right: Bool)
        case workspace(String)

        var paneID: String? {
            if case let .pane(id) = self {
                id
            } else {
                nil
            }
        }
    }

    struct Closing {
        let close: Close
        let running: [String]
        var replace: Replacement?
    }

    @MainActor @Observable
    final class Workspace: Identifiable {
        let id: String
        var label = ""
        var tabs: [Tab] = []
        var activeTabID = ""
        var worktree: Worktree?
        var state: AgentState?
        var git: GitStatus?
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
        var focused = false
        var tabID = ""
        var terminalID: String?
        var agent: String?
        /// Without herdr's status glyphs.
        var terminalTitle: String?
        var state: AgentState?
        var since: Date?
        /// herdr's `state_change_seq`: one counter for the session's agents.
        var changeSeq: Int?
        var agentName: String?
        /// herdr's `agent_session` of the pane's agent.
        var reportedSession: String?
        var sessionTitle: String?
        @ObservationIgnored var titleKey: String?
        var program: Program?
        var placeholder = false
        @ObservationIgnored var placed: Int?
        @ObservationIgnored var rechecked: String?
        @ObservationIgnored var remade = false
        @ObservationIgnored var drawnLabel: String?
        @ObservationIgnored var asked = false
        @ObservationIgnored var asks = 0
        /// A shell's startup runs short-lived programs (`gh auth token`, `brew shellenv` in a .zshrc): no ask in a new
        /// pane's first second.
        @ObservationIgnored var starting = false

        init(id: String) {
            self.id = id
        }

        var folder: String? {
            cwd.map { ($0 as NSString).abbreviatingWithTildeInPath }
        }

        var browser: PaneLabel? {
            plugin.flatMap { $0.plugin == Registry.browser.id ? $0 : nil }
        }

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

        /// herdr's report, else the id after `resume` in the agent's command line (`codex resume <id>`): Codex runs
        /// the hook that reports it to herdr only at its first prompt. Not any id there: an MCP server's, `fork`'s.
        var session: String? {
            reportedSession ?? program?.foreground.lazy.compactMap {
                $0.argv.drop { $0 != "resume" }.lazy.compactMap(ChatAdapters.uuid).first
            }.first
        }

        var programName: String? {
            agent ?? program?.title
        }

        var agentTitle: String? {
            agent == nil ? nil : label ?? sessionTitle ?? "Untitled"
        }

        var agentLabel: String? {
            Chooser.agent(agent)?.name ?? agentName
        }

        var letter: String? {
            programName?.prefix(1).uppercased()
        }

        var iconID: String {
            plugin?.symbol ?? programIcons.iconID(agent: agent, program: program, title: terminalTitle)
        }
    }
}

extension HostStore {
    var agentPanes: [Pane] {
        workspaces.flatMap(\.tabs).flatMap { panes(in: $0.id).filter { $0.state != nil } }
    }
}

extension HostStore {
    var name: String {
        session == Session.defaultName ? machine.name : "\(machine.name) · \(session)"
    }

    var title: String {
        guard session == Session.defaultName else { return session }
        return machine.isRemote ? machine.name : Machine.computerName
    }

    var label: String {
        machine.isRemote ? name : session
    }

    var reconnecting: Bool {
        guard case let .failed(error) = state else { return false }
        return !error.isMachineProblem && isRunning
    }

    func workspace(of tabID: String) -> Workspace? {
        workspaces.first { $0.tabs.contains { $0.id == tabID } }
    }

    func tab(_ id: String) -> Tab? {
        workspaces.lazy.flatMap(\.tabs).first { $0.id == id }
    }

    func parent(of workspace: Workspace) -> Workspace? {
        guard let worktree = workspace.worktree, worktree.isLinkedWorktree else { return nil }
        return workspaces.first { $0.worktree?.repoKey == worktree.repoKey && $0.worktree?.isLinkedWorktree == false }
    }

    func worktrees(of workspaceID: String) -> [Workspace] {
        workspaces.filter { parent(of: $0)?.id == workspaceID }
    }

    /// One pass: a parent lookup per workspace reads every workspace's worktree, 40,000 observed reads at 200 spaces
    /// in each sidebar update.
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
    /// A new herdr server has no workspace. A second start of a session joins the one in flight: on its own it would
    /// find the booting server silent and boot it out.
    static func start(_ session: String, on machine: Machine) async throws {
        let key = key(session, machine)
        let start = starts[key] ?? Task {
            let client: any Multiplexer = await HerdrClient(session: session, exec: machine.exec())
            let timeout = UserDefaults.standard.string(forKey: "startTimeout").flatMap(Double.init) ?? 10
            if try await client.startServer(within: .seconds(timeout)),
               try await client.snapshot().workspaces.isEmpty
            {
                let pane = try await client.newWorkspace(label: nil, cwd: "~")
                open[key]?.choose(pane, fixed: true)
            }
        }
        starts[key] = start
        // Not a newer start that begins as this one ends.
        defer { starts[key] = starts[key] == start ? nil : starts[key] }
        try await start.value
    }

    private(set) static var starts: [String: Task<Void, Error>] = [:]

    func start() async {
        starting = true
        startProblem = nil
        do {
            try await Self.start(session, on: machine)
            // The loader stays until this read answers: `run` ends `starting`.
            await client?.refresh()
        } catch {
            starting = false
            startProblem = error.localizedDescription
        }
    }
}

/// Replaces the list only when its ids change, so views of the list redraw only then.
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

extension Array {
    /// The element `offset` steps from `index`, round the ends: the one rule for panes, tabs, spaces and sessions.
    func step(from index: Int, by offset: Int) -> Element {
        self[((index + offset) % count + count) % count]
    }
}

extension [String?] {
    var plainTitle: String {
        compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " | ")
    }
}
