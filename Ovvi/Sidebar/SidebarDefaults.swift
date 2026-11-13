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
    static let foldsAndShelves = "foldsAndShelves"

    var archivedKey: String {
        "\(store.machine.id) archived-sessions"
    }

    func foldKey(_ workspace: String) -> String {
        "\(store.machine.id) \(id) folded \(workspace)"
    }

    func togglePin(_ workspace: String) {
        store.pins.formSymmetricDifference([workspace])
    }

    var spaceOrder: SpaceOrder {
        store.order ?? AppSettings().spaceOrder
    }

    /// The sidebar's order: the pinned spaces in herdr's order, then the others in the sort, a worktree with its
    /// repository, less the ones the sidebar hides. Also the order of ⌃⌘[ ], ⌃⌘1–9, the overview and the palette.
    var sidebarGroups: [[HostStore.Workspace]] {
        let pinned = store.pins, hidden = store.hidden, groups = store.groups
        return groups.filter { pinned.contains($0[0].id) }
            + sorted(groups.filter { !pinned.contains($0[0].id) && !hidden.contains($0[0].id) })
    }

    /// Recent: the group whose agent changed state last first, held still under the pointer.
    func sorted(_ groups: [[HostStore.Workspace]]) -> [[HostStore.Workspace]] {
        guard spaceOrder == .recent else { return groups }
        let place = Dictionary(uniqueKeysWithValues: (sortHold ?? []).enumerated().map { ($1, $0) })
        return groups.map { group in
            let changed = group.flatMap(\.tabs).flatMap { store.panes(in: $0.id) }.compactMap(\.changeSeq).max()
            return (group, place[group[0].id] ?? .max, -(changed ?? -1))
        }
        .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
        .map(\.0)
    }
}

extension HostStore {
    /// The session's lines of a kind ("‹machine› ‹session› ‹kind› ‹value›") in the sidebar's defaults.
    static func saved(_ kind: String, _ session: String, _ machine: Machine) -> [String] {
        let prefix = "\(machine.id) \(session) \(kind) "
        return lines.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// The session's lines of the kind replaced; the others kept.
    func save(_ kind: String, _ values: [String]) {
        let prefix = "\(machine.id) \(session) \(kind) "
        UserDefaults.sidebar.set((Self.lines.filter { !$0.hasPrefix(prefix) } + values.map { prefix + $0 })
            .joined(separator: "\n"), forKey: Self.key)
    }

    private static let key = "spaceChoices"

    private static var lines: [String] {
        (UserDefaults.sidebar.string(forKey: key) ?? "").split(separator: "\n").map(String.init)
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
