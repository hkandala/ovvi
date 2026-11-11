import SwiftUI

/// A session's order of the unpinned spaces; a session follows Settings' until its Sort Spaces picks.
enum SpaceOrder: String {
    case manual, recent
}

/// Once the menu has closed: its fade draws no animation frame, so a move started from it showed half done, then a
/// jump.
@MainActor func afterMenu(_ action: @escaping @MainActor () -> Void) {
    RunLoop.main.perform(inModes: [.default]) {
        MainActor.assumeIsolated(action)
    }
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

    func togglePin(_ workspace: String) {
        store.pins.formSymmetricDifference([workspace])
    }

    /// herdr's order with the pinned spaces first, a worktree with its repository, less the ones the sidebar hides: the
    /// sidebar's in Manual, and the order of ⌃⌘[ ], ⌃⌘1–9, the overview and the palette's places.
    var sidebarGroups: [[HostStore.Workspace]] {
        let pinned = store.pins, hidden = store.hidden, groups = store.groups
        return groups.filter { pinned.contains($0[0].id) }
            + groups.filter { !pinned.contains($0[0].id) && !hidden.contains($0[0].id) }
    }
}

extension HostStore {
    /// The session's lines of a kind ("‹machine› ‹session› ‹kind› ‹value›") in the sidebar's defaults, under the key
    /// that held only pins at first, so those stay.
    static func saved(_ kind: String, _ session: String, _ machine: Machine) -> [String] {
        let prefix = "\(machine.id) \(session) \(kind) "
        return lines.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// The session's lines of the kind replaced; the others kept.
    func save(_ kind: String, _ values: [String]) {
        let prefix = "\(machine.id) \(session) \(kind) "
        UserDefaults.agents.set((Self.lines.filter { !$0.hasPrefix(prefix) } + values.map { prefix + $0 })
            .joined(separator: "\n"), forKey: Self.key)
    }

    private static let key = "pinnedSpaces"

    private static var lines: [String] {
        (UserDefaults.agents.string(forKey: key) ?? "").split(separator: "\n").map(String.init)
    }

    /// While Show Only Pinned Spaces is on: the unpinned spaces, less any a window shows, so the user never loses
    /// their place. A worktree goes with its repository.
    var hidden: Set<String> {
        guard onlyPinned else { return [] }
        let shown = Set(windows.compactMap { $0.page(self)?.selectedWorkspaceID })
        return Set(groups.filter { group in !pins.contains(group[0].id) && !group.contains { shown.contains($0.id) } }
            .flatMap { $0.map(\.id) })
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
