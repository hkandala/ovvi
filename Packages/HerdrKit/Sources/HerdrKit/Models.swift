import Foundation

// Only the fields the app uses, most optional, and unknown enum values fall back: one odd entry or a newer herdr
// cannot fail a snapshot.

public struct Snapshot: Decodable, Sendable {
    let version: String?
    public let focusedWorkspaceID: String?
    public let workspaces: [Workspace]
    public let tabs: [Tab]
    public let panes: [Pane]
    public let agents: [Agent]
    let layouts: [Layout]
    public internal(set) var trees: [String: SplitNode] = [:]
    /// herdr's global `focused` marks only one pane of all tabs.
    public var focusedPaneIDs: Set<String> {
        Set(layouts.compactMap(\.focusedPaneID))
    }

    enum CodingKeys: String, CodingKey {
        case focusedWorkspaceID = "focused_workspace_id"
        case version, workspaces, tabs, panes, agents, layouts
    }
}

public struct Workspace: Decodable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let activeTabID: String
    /// Only once a `worktree.*` call has looked at the workspace; a plain `workspace.create` leaves it out.
    public let worktree: Worktree?

    enum CodingKeys: String, CodingKey {
        case id = "workspace_id", label, activeTabID = "active_tab_id", worktree
    }
}

public struct Worktree: Decodable, Equatable, Sendable {
    /// The repository's shared `.git` directory: the same for a repository and its linked worktrees.
    public let repoKey: String
    public let checkoutPath: String
    public let isLinkedWorktree: Bool

    enum CodingKeys: String, CodingKey {
        case repoKey = "repo_key", checkoutPath = "checkout_path", isLinkedWorktree = "is_linked_worktree"
    }
}

public struct Tab: Decodable, Sendable, Identifiable {
    public let id: String
    public let workspaceID: String
    public let label: String

    public init(id: String, workspaceID: String, label: String) {
        self.id = id
        self.workspaceID = workspaceID
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id = "tab_id", workspaceID = "workspace_id", label
    }
}

public struct Pane: Decodable, Sendable, Identifiable {
    public let id: String
    public let terminalID: String?
    public let tabID: String
    public let label: String?
    public let cwd: String?
    public let agent: String?
    /// The terminal title without the status glyphs herdr strips (`✳`, spinners).
    public let title: String?
    /// herdr's viewport, which every client of the pane shares.
    public let scroll: PaneScroll?
    /// The agent's status; `unknown` until herdr read it from the agent's screen.
    public let agentStatus: AgentStatus?
    public let agentSession: AgentSession?
    let tokens: Tokens?
    /// Set when herdr brings the pane back from its saved session without a program: its saved folder is gone.
    public let restoreError: String?

    public var chat: String? {
        tokens?[Tokens.chat]
    }

    enum CodingKeys: String, CodingKey {
        case id = "pane_id", terminalID = "terminal_id", tabID = "tab_id", label, cwd, agent
        case title = "terminal_title_stripped", scroll, agentStatus = "agent_status", agentSession = "agent_session"
        case tokens, restoreError = "restore_error"
    }
}

struct Tokens: Decodable {
    static let request = "ovvi-req", chat = "ovvi-chat", shown = "ovvi-shown", open = "ovvi-open"

    private let values: [String: String]

    init(from decoder: any Decoder) throws {
        values = (try? decoder.singleValueContainer().decode([String: String].self)) ?? [:]
    }

    subscript(_ name: String) -> String? {
        values[name]
    }
}

/// herdr's `agent_session`: `value` is the session's id (Claude Code, Codex, OpenCode) or its file (pi). It can be an
/// earlier agent's: check `agent`.
public struct AgentSession: Decodable, Sendable {
    public let agent: String?
    public let value: String?
}

public struct PaneScroll: Decodable, Sendable {
    public let offsetFromBottom: Int?
    public let maxOffsetFromBottom: Int?
    public let viewportRows: Int?

    enum CodingKeys: String, CodingKey {
        case offsetFromBottom = "offset_from_bottom", maxOffsetFromBottom = "max_offset_from_bottom"
        case viewportRows = "viewport_rows"
    }
}

public struct Agent: Decodable, Sendable {
    public let paneID: String
    public let terminalID: String?
    public let agent: String?
    /// A label set through `pane.report_metadata`; wins over `agent` as the name.
    public let displayAgent: String?
    public let status: AgentStatus
    /// The number of the agent's last finish (working or blocked to idle); null again at its next status change.
    public let completionSeq: Int?
    /// Counted over the session: the newest is the largest.
    public var stateChangeSeq: Int?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id", terminalID = "terminal_id", agent, displayAgent = "display_agent"
        case status = "agent_status", completionSeq = "completion_seq", stateChangeSeq = "state_change_seq"
    }
}

/// In an extension, so tests keep the memberwise init.
public extension Agent {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paneID = try container.decode(String.self, forKey: .paneID)
        terminalID = try? container.decode(String.self, forKey: .terminalID)
        agent = try? container.decode(String.self, forKey: .agent)
        displayAgent = try? container.decode(String.self, forKey: .displayAgent)
        status = (try? container.decode(AgentStatus.self, forKey: .status)) ?? .unknown
        completionSeq = try? container.decode(Int.self, forKey: .completionSeq)
        stateChangeSeq = try? container.decode(Int.self, forKey: .stateChangeSeq)
    }
}

public enum AgentStatus: String, Decodable, Sendable {
    case idle, working, blocked, done, unknown

    public init(from decoder: any Decoder) throws {
        self = try Self(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

struct Created: Decodable {
    let rootPane: Pane?
    let pane: Pane?

    enum CodingKeys: String, CodingKey { case rootPane = "root_pane", pane }
}

/// A move to another workspace gives the pane a new id.
struct Moved: Decodable {
    let moveResult: Change

    enum CodingKeys: String, CodingKey { case moveResult = "move_result" }
}

struct Applied: Decodable {
    struct Root: Decodable {
        let root: Layout.Pane
    }

    let layout: Root
}

struct Swapped: Decodable {
    let swap: Change
}

struct Change: Decodable {
    let changed: Bool?
    let reason: String?
    let pane: Pane?

    func check() throws {
        if changed == false {
            throw HerdrError.refused(reason ?? "unknown")
        }
    }
}

struct Read: Decodable {
    struct Text: Decodable {
        let text: String
    }

    let read: Text
}

struct ProcessInfoResult: Decodable {
    let processInfo: PaneProcesses

    enum CodingKeys: String, CodingKey { case processInfo = "process_info" }
}

public struct Program: Equatable, Sendable {
    public let name: String
    public let argv0: String?
    /// ponytail: the first argument that is not an option, so `node --require x.js cli.js` or `bun run dev` pick the
    /// wrong one (the header and the base-name match); skip option values if it matters.
    public let script: String?
    public let isShell: Bool
    public var foreground: [Foreground] = []

    public struct Foreground: Equatable, Sendable {
        public let pid: Int
        public let argv: [String]
        /// Its name and `argv[0]`: a Node CLI that sets its process title (npm's pi) is `node` with the title as
        /// `argv[0]`, and macOS lists no other argument for it.
        public let name: String
        public var argv0: String?
    }

    init(name: String, argv0: String? = nil, script: String? = nil, isShell: Bool = false) {
        self.name = name
        self.argv0 = argv0
        self.script = script
        self.isShell = isShell
    }

    static let runtimes: Set = ["node", "bun"]

    public var title: String {
        guard let script, Self.runtimes.contains(name) else { return name }
        // Not `URL(filePath:)`: for a relative path it reads the working folder.
        return script.split(separator: "/").last.map(String.init) ?? name
    }
}

struct PaneProcesses: Decodable {
    struct Process: Decodable {
        let pid: Int
        let name: String
        let argv0: String?
        let argv: [String]?

        var isShell: Bool {
            argv0?.hasPrefix("-") == true || ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "nu"]
                .contains(name)
        }
    }

    let shellPID: Int
    let foregroundProcesses: [Process]

    /// A program the shell `exec`ed has the shell's pid, so the shell's pid counts only while it is a shell.
    var program: Program? {
        let program = foregroundProcesses.first { $0.pid != shellPID || !$0.isShell }
        return (program ?? foregroundProcesses.first).map { process in
            var found = Program(name: process.name, argv0: process.argv0,
                                script: process.argv?.dropFirst().first { !$0.hasPrefix("-") }, isShell: program == nil)
            found.foreground = foregroundProcesses.map {
                Program.Foreground(pid: $0.pid, argv: $0.argv ?? [], name: $0.name, argv0: $0.argv0)
            }
            return found
        }
    }

    enum CodingKeys: String, CodingKey { case shellPID = "shell_pid", foregroundProcesses = "foreground_processes" }
}

public struct Session: Codable, Equatable, Sendable {
    public let name: String
    public let running: Bool
    let socketPath: String?

    enum CodingKeys: String, CodingKey {
        case name, running, socketPath = "socket_path"
    }

    /// herdr's rule for session names: ASCII letters, digits, `.`, `_` and `-`, at most 64 bytes, not `.` or `..`.
    /// Not a leading `-` either: names from outside (`ovvi://float`) go into argv, where it reads as an option.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 64 && name != "." && name != ".." && !name.hasPrefix("-")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}

struct Layout: Decodable {
    let tabID: String
    let focusedPaneID: String?
    let panes: [Pane]
    let splits: [Split]

    struct Pane: Decodable {
        let pane_id: String // swiftlint:disable:this identifier_name
    }

    struct Split: Decodable {
        let id: String
        let direction: SplitNode.Direction
        let ratio: Double
    }

    enum CodingKeys: String, CodingKey { case tabID = "tab_id", focusedPaneID = "focused_pane_id", panes, splits }
}
