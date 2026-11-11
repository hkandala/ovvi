import AppKit
import HerdrKit
import UserNotifications

@MainActor
enum Notifications {
    static let agent = "agent|"

    static func post(_ changes: [Seen.Change], _ page: Page) {
        let store = page.store
        Task {
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications().map(\.request.identifier)
            // After the wait: a later snapshot's new one must not go.
            let holding = Set(store.panes.filter { $0.state?.calls == true }
                .map { id($0, of: store) })
            let prefix = Self.prefix(store)
            let panes = Set(store.panes.map { agent + id($0, of: store) })
            let gone = delivered.filter {
                $0.hasPrefix(prefix) && !holding.contains($0) || $0.hasPrefix(agent + prefix) && !panes.contains($0)
            }
            center.removeDeliveredNotifications(withIdentifiers: gone)
        }
        let settings = AppSettings()
        for change in changes where change.state.calls
            && (change.state == .needsYou ? settings.notifyNeedsYou : settings.notifyFinished)
        {
            // A pane Show Only Pinned Spaces hides shows no state.
            guard let pane = store.pane(change.paneID), pane.state != nil, pane.tabID != store.lookingTabID
            else { continue }
            let content = UNMutableNotificationContent()
            content.title = title(pane, change.state)
            content.body = "\(store.label) · \(page.place(pane))"
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: id(pane, of: store), content: content, trigger: nil))
        }
    }

    static func post(_ title: String, _ body: String, from agent: String, for pane: HostStore.Pane,
                     of store: HostStore) async throws
    {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "\(agent) · \(store.label)"
        content.body = body
        try await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: Self.agent + id(pane, of: store), content: content, trigger: nil))
    }

    static func remove(_ panes: [HostStore.Pane], of store: HostStore) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: panes.map { id($0, of: store) })
    }

    /// One per terminal: macOS replaces a delivered notification of the same id.
    static func id(_ pane: HostStore.Pane, of store: HostStore) -> String {
        prefix(store) + (pane.terminalID ?? pane.id)
    }

    static func prefix(_ store: HostStore) -> String {
        "\(store.machine.id)|\(store.session)|"
    }

    static func parts(_ id: String) -> [String] {
        id.split(separator: "|", maxSplits: 2).map(String.init)
    }

    static func title(_ pane: HostStore.Pane, _ state: AgentState) -> String {
        "\(pane.agentName ?? "agent") \(state.word)"
    }
}

extension HostStore {
    static var needsYou: Int {
        all.reduce(0) { $0 + $1.waiting }
    }

    static func showBadge() {
        NSApp.dockTile.badgeLabel = needsYou > 0 ? "\(needsYou)" : nil
    }
}
