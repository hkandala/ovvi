import Foundation
import HerdrKit

/// A pinned tab (ui/window#pinned): on top of its session's page, in pin order, until the tab closes.
/// ponytail: kept by herdr's tab id, which herdr gives again to a later tab; a pin is dropped once a snapshot lacks
/// its tab, so only a tab made again with that id while the app was not running inherits it.
struct TabPin: Codable, Hashable {
    let machine: String
    /// The herdr session it is in.
    let session: String
    let tab: String

    /// The defaults key of the pins, a JSON list.
    static let key = "tabPins"
}

extension Page {
    /// The page's pinned tabs that still show, in pin order.
    func pinnedTabs(_ text: String) -> [HostStore.Tab] {
        [TabPin](json: text).filter { $0.machine == store.machine.id && $0.session == store.session }
            .compactMap { pin in store.workspaces.lazy.flatMap(\.tabs).first { $0.id == pin.tab } }
    }

    func pinned(_ tab: HostStore.Tab, in text: String) -> Bool {
        [TabPin](json: text).contains(pin(tab))
    }

    /// Pins the tab at the end of Pinned, or unpins it.
    func togglePin(_ tab: HostStore.Tab) {
        var pins = [TabPin](json: UserDefaults.agents.string(forKey: TabPin.key) ?? "")
        if let index = pins.firstIndex(of: pin(tab)) {
            pins.remove(at: index)
        } else {
            pins.append(pin(tab))
        }
        UserDefaults.agents.set(pins.json, forKey: TabPin.key)
    }

    private func pin(_ tab: HostStore.Tab) -> TabPin {
        TabPin(machine: store.machine.id, session: store.session, tab: tab.id)
    }
}

extension HostStore {
    /// Drops this session's pins whose tab is gone, after each snapshot, but a moving tab's; another session's stay.
    func keepTabPins() {
        guard last != nil, let text = UserDefaults.agents.string(forKey: TabPin.key) else { return }
        let tabs = Set(workspaces.flatMap(\.tabs).map(\.id)).union(movingTabs)
        let pins = [TabPin](json: text)
            .filter { $0.machine != machine.id || $0.session != session || tabs.contains($0.tab) }
        if pins.json != text {
            UserDefaults.agents.set(pins.json, forKey: TabPin.key)
        }
    }

    /// A pinned tab moved to another workspace keeps its pin, in its place, under its new tab's id.
    func repin(tab old: String, to new: String?) {
        guard let new, let text = UserDefaults.agents.string(forKey: TabPin.key) else { return }
        let pins = [TabPin](json: text).map { pin in
            pin.machine == machine.id && pin.session == session && pin.tab == old
                ? TabPin(machine: pin.machine, session: pin.session, tab: new) : pin
        }
        if pins.json != text {
            UserDefaults.agents.set(pins.json, forKey: TabPin.key)
        }
    }
}

@MainActor
extension UserDefaults {
    /// The sidebar's own state: tab pins, open folds and shelves, and the agents' times, in a defaults domain of the
    /// config folder's (`dev.ovvi.app.agents.‹folder, / as _›`), so a test's `-configFolder` keeps its writes out of
    /// the user's. Not a suite at a path: once its file exists, a new process's writes read back the old value and
    /// notify no view.
    static let agents = UserDefaults(suiteName: "dev.ovvi.app.agents." + Registry.config.path.replacing("/", with: "_"))
        ?? .standard

    /// Drops the keys of the old Agents view left in the user's defaults: its agent pins, its Settled fold and setting,
    /// the Archived fold's old name. The app's own defaults only outside a test's config folder: those are the user's.
    /// ponytail: runs on every launch; delete once no user runs a build from before the one sidebar.
    static func dropAgentsView() {
        agents.removeObject(forKey: "agentPins")
        let open = agents.string(forKey: Page.openShelves)?.split(separator: "\n") ?? []
        let kept = open.filter { !$0.hasSuffix(" Settled") && !$0.hasSuffix(" Archived") }
        if kept.count != open.count {
            agents.set(kept.joined(separator: "\n"), forKey: Page.openShelves)
        }
        if standard.string(forKey: "configFolder") == nil {
            standard.removeObject(forKey: "settleAfter")
        }
    }
}

extension Array where Element: Codable {
    /// From the JSON text a setting keeps; empty when there is none or it does not decode.
    init(json: String) {
        self = (try? JSONDecoder().decode(Self.self, from: Data(json.utf8))) ?? []
    }

    var json: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
