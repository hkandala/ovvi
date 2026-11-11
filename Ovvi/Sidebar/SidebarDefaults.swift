import SwiftUI

/// A window's order of the unpinned spaces; a new window takes Settings'.
enum SpaceOrder: String {
    case manual, recent
}

extension EnvironmentValues {
    /// The window's `SpaceOrder` (scene storage), empty for Settings'.
    @Entry var spaceOrder: Binding<String> = .constant("")
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

    /// The pinned spaces, a line each ("‹machine› ‹session› pinned ‹id›"): the session's, as herdr's own order is.
    static let pinnedSpaces = "pinnedSpaces"

    func togglePin(_ workspace: String) {
        store.savePins(store.pins.symmetricDifference([workspace]))
    }

    /// herdr's order with the pinned spaces first, a worktree with its repository: the sidebar's in Manual, and the
    /// order of ⌃⌘[ ], ⌃⌘1–9, the overview and the palette's places.
    var sidebarGroups: [[HostStore.Workspace]] {
        let pinned = store.pins, groups = store.groups
        return groups.filter { pinned.contains($0[0].id) } + groups.filter { !pinned.contains($0[0].id) }
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
