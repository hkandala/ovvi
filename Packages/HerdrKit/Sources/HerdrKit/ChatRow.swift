import Foundation

public enum ChatRow: Equatable, Sendable, Identifiable {
    case user(id: String, text: String)
    case stack(id: String, steps: Range<Int>)
    case worked(id: String, seconds: Double)
    case reply(id: String, text: String)
    case todos(id: String, [ChatTodo])
    case note(id: String, text: String, failed: Bool)

    public var id: String {
        switch self {
        case let .user(id, _), let .stack(id, _), let .worked(id, _), let .reply(id, _), let .todos(id, _),
             let .note(id, _, _): id
        }
    }
}

public extension ChatHistory {
    /// Each run of steps between two other entries is one line; a turn's end, as the agent records it, is its Worked.
    func rows() -> [ChatRow] {
        var rows: [ChatRow] = [], run = 0 ..< 0
        func endRun() {
            if entries[run].contains(where: { $0.tool != nil }) {
                rows.append(.stack(id: entries[run.lowerBound].id, steps: run))
            }
        }
        for (index, entry) in entries.enumerated() {
            if entry.isStep {
                run = (run.isEmpty ? index : run.lowerBound) ..< index + 1
                continue
            }
            endRun()
            if let row = entry.row {
                rows.append(row)
            }
            run = index + 1 ..< index + 1
        }
        endRun()
        return rows
    }

    /// The start of a turn that has not ended.
    var turnStart: Date? {
        guard let last = entries.lastIndex(where: { $0.user != nil || $0.seconds != nil }),
              entries[last].user != nil else { return nil }
        return entries[last].time
    }
}
