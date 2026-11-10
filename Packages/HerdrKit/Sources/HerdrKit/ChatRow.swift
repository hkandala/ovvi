import Foundation

public enum ChatRow: Equatable, Sendable, Identifiable {
    case user(id: String, text: String)
    case stack(id: String, steps: Range<Int>)
    case worked(id: String, seconds: Double?)
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
    func rows(working: Bool) -> [ChatRow] {
        var rows: [ChatRow] = [], turn = 0, run = 0 ..< 0
        func endRun() {
            if entries[run].contains(where: { $0.tool != nil }) {
                rows.append(.stack(id: entries[run.lowerBound].id, steps: run))
            }
        }
        func endTurn(at end: Int, running: Bool) {
            endRun()
            let body = entries[turn ..< end].drop { $0.user != nil }
            if !running, body.contains(where: { $0.tool != nil }) {
                rows.append(.worked(id: "\(entries[turn].id).worked", seconds: Self.seconds(body)))
            }
        }
        for (index, entry) in entries.enumerated() {
            if let text = entry.user {
                endTurn(at: index, running: false)
                turn = index
                rows.append(.user(id: entry.id, text: text))
            } else if entry.isStep {
                run = (run.isEmpty ? index : run.lowerBound) ..< index + 1
                continue
            } else {
                // A run never spans two turns.
                endRun()
                if let row = entry.row {
                    rows.append(row)
                }
            }
            run = index + 1 ..< index + 1
        }
        endTurn(at: entries.endIndex, running: working)
        return rows
    }

    var lastTurnStart: Date? {
        (entries.last { $0.user != nil } ?? entries.first)?.time
    }

    private static func seconds(_ body: ArraySlice<ChatEntry>) -> Double? {
        body.lazy.compactMap(\.seconds).last
            ?? body.first?.time.flatMap { first in body.last?.time?.timeIntervalSince(first) }
    }
}
