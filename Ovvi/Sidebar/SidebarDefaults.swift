import Foundation

enum SpaceOrder: String {
    case manual, recent
    static let key = "spaceOrder"
}

extension Page {
    /// ponytail: folds are never pruned, so a space herdr makes again with a folded one's id starts folded.
    static let openShelves = "agentsOpen"

    var archivedKey: String {
        "\(store.machine.id) archived-sessions"
    }

    func foldKey(_ workspace: String) -> String {
        "\(store.machine.id) \(id) folded \(workspace)"
    }
}

extension String {
    func hasLine(_ line: String) -> Bool {
        split(separator: "\n").contains { $0 == line }
    }

    func togglingLine(_ line: String) -> String {
        var lines = split(separator: "\n").map(String.init)
        if lines.contains(line) {
            lines.removeAll { $0 == line }
        } else {
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
