import Foundation

/// Ordered: a tab or a workspace shows its strongest pane.
public enum AgentState: Comparable, Sendable {
    case idle, working, finishedUnseen, needsYou
}

/// Keyed by terminal (else pane id): a moved pane gets a new pane id and keeps its terminal, and herdr reuses pane
/// ids for new terminals.
public struct Seen: Sendable {
    public struct Change: Equatable, Sendable {
        public let paneID: String
        public let state: AgentState
    }

    /// Kept over a relaunch: an agent whose number is the same keeps its time (herdr gives no times).
    public struct Mark: Codable, Equatable, Sendable {
        public let seq: Int
        public let since: Date
    }

    public private(set) var states: [String: AgentState] = [:]
    public private(set) var since: [String: Date] = [:]
    private var agents: [Agent] = []
    private var looking: Set<String> = []
    /// An agent in here has been sighted; its value may be nil.
    private var seen: [String: Int?] = [:]
    private var started = false
    private var restored: [String: Mark]
    private var seqs: [String: Int] = [:]

    public init(marks: [String: Mark] = [:]) {
        restored = marks
    }

    public var marks: [String: Mark] {
        since.reduce(into: [:]) { marks, item in
            if let seq = seqs[item.key] {
                marks[item.key] = Mark(seq: seq, since: item.value)
            }
        }
    }

    public static func key(terminalID: String?, paneID: String) -> String {
        terminalID ?? paneID
    }

    public mutating func update(_ agents: [Agent], looking: Set<String>, now: Date = .now) -> [Change] {
        self.agents = agents
        defer { started = true }
        return look(looking, now: now)
    }

    @discardableResult
    public mutating func look(_ looking: Set<String>, now: Date = .now) -> [Change] {
        var states: [String: AgentState] = [:]
        var changes: [Change] = []
        for agent in agents {
            let id = Self.key(terminalID: agent.terminalID, paneID: agent.paneID)
            // The first sighting counts as seen: no flood of earlier finishes after launch. A finish the user looks at
            // stays Done until they leave it.
            if seen[id] == nil || self.looking.contains(id) && !looking.contains(id) {
                seen[id] = .some(agent.completionSeq)
            }
            // Different, not greater: the counter starts at 0 again when herdr restarts.
            let finished = agent.completionSeq != nil && agent.completionSeq != seen[id] ?? nil
            let state: AgentState = switch agent.status {
            case .blocked: .needsYou
            case .working: .working
            default: finished ? .finishedUnseen : .idle
            }
            states[id] = state
            seqs[id] = agent.stateChangeSeq
            if self.states[id] != state {
                let mark = self.states[id] == nil ? restored.removeValue(forKey: id) : nil
                since[id] = mark != nil && mark?.seq == agent.stateChangeSeq ? mark?.since : now
                if started {
                    changes.append(Change(paneID: agent.paneID, state: state))
                }
            }
        }
        seen = seen.filter { states[$0.key] != nil }
        since = since.filter { states[$0.key] != nil }
        seqs = seqs.filter { states[$0.key] != nil }
        self.states = states
        self.looking = looking
        return changes
    }
}
