import Foundation

@MainActor
extension UserDefaults {
    /// The sidebar's own state: folded spaces, the open Archived Sessions, its agent, and the agents' times, in a
    /// defaults domain of the config folder's (`dev.ovvi.app.agents.‹folder, / as _›`), so a test's `-configFolder`
    /// keeps its writes out of the user's. Not a suite at a path: once its file exists, a new process's writes read
    /// back the old value and notify no view.
    static let agents = UserDefaults(suiteName: "dev.ovvi.app.agents." + Registry.config.path.replacing("/", with: "_"))
        ?? .standard

    /// Drops the keys of the old sidebars left in the user's defaults: the Agents view's agent pins, Settled fold and
    /// setting, the pinned tabs, the old Archived folds (per session), and the unfolded spaces (all start unfolded
    /// now). The app's own defaults only outside a test's config folder: those are the user's.
    /// ponytail: runs on every launch; delete once no user runs a build from before phase 57.
    static func dropAgentsView() {
        agents.removeObject(forKey: "agentPins")
        agents.removeObject(forKey: "tabPins")
        let open = agents.string(forKey: Page.openShelves)?.split(separator: "\n") ?? []
        let kept = open.filter { line in
            let words = line.split(separator: " ")
            return !line.hasSuffix(" Settled") && !line.hasSuffix(" Archived") && !line.hasSuffix(" Archived Sessions")
                && !(words.count == 4 && words[2] == "workspace")
        }
        if kept.count != open.count {
            agents.set(kept.joined(separator: "\n"), forKey: Page.openShelves)
        }
        if standard.string(forKey: "configFolder") == nil {
            standard.removeObject(forKey: "settleAfter")
        }
    }
}

extension Page {
    /// The defaults key of the folded spaces and the open Archived Sessions, a line each.
    /// ponytail: folds are never pruned, so a space herdr makes again with a folded one's id starts folded.
    static let openShelves = "agentsOpen"

    /// "‹machine› ‹session› ‹label›".
    func shelfKey(_ label: String) -> String {
        "\(store.machine.id) \(id) \(label)"
    }
}

extension String {
    /// This text of lines (`Page.openShelves`) has `line`.
    func hasLine(_ line: String) -> Bool {
        split(separator: "\n").contains { $0 == line }
    }

    /// This text with `line` added, or taken out when it is there.
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
