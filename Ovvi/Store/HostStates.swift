import Foundation
import HerdrKit

extension HostStore {
    var looking: Set<String> {
        Set([lookingKey].compactMap(\.self))
    }

    /// A space Show Only Pinned Spaces hides shows no state, as if it were not there.
    func showStates() {
        let hidden = hidden
        let hiddenTabs = Set(workspaces.filter { hidden.contains($0.id) }.flatMap(\.tabs).map(\.id))
        for pane in panes {
            let key = Seen.key(terminalID: pane.terminalID, paneID: pane.id)
            pane.state = hiddenTabs.contains(pane.tabID) ? nil : seen.states[key]
            pane.since = seen.since[key]
        }
        showStrongest()
        keepMarks()
    }

    static func marksKey(_ session: String, _ machine: Machine) -> String {
        "agentMarks.\(machine.id) \(session)"
    }

    /// Only once a snapshot comes: until then they are empty.
    private func keepMarks() {
        guard last != nil, seen.marks != marks else { return }
        marks = seen.marks
        let key = Self.marksKey(session, machine)
        if marks.isEmpty {
            UserDefaults.sidebar.removeObject(forKey: key)
        } else {
            UserDefaults.sidebar.set(try? JSONEncoder().encode(marks), forKey: key)
        }
    }

    func clear(_ panes: [Pane]) {
        seen.clear(Set(panes.map { Seen.key(terminalID: $0.terminalID, paneID: $0.id) }))
        showStates()
        Notifications.remove(panes, of: self)
    }

    static func look(_ pane: Pane?, in store: HostStore) {
        let key = pane.map { Seen.key(terminalID: $0.terminalID, paneID: $0.id) }
        for other in all {
            other.lookingKey = other === store ? key : nil
        }
    }
}
