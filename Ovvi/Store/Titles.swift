import Foundation
import HerdrKit

extension Page {
    /// herdr's default label is a bare number.
    func title(_ tab: HostStore.Tab) -> (name: String, folder: String?) {
        guard tab.label.allSatisfy(\.isNumber) else { return (tab.label, nil) }
        // The stack's first, without the stack: the menus ask for every tab's title.
        let front = keyboardCard(tab.id) ?? store.panes(in: tab.id).first
        if let pane = front, pane.plugin != nil, let (name, detail) = kindTitle(pane) {
            return (name, detail)
        }
        let choosing = front.map { store.chooser($0.id) != nil } ?? false
        guard let pane = front, let name = pane.programName, !choosing else {
            return (front?.starting == false && !choosing ? tab.label : "New Tab", nil)
        }
        if let title = pane.agentTitle {
            return (pane.agentLabel ?? name, title)
        }
        return (name, pane.cwd.map { $0 == Self.home ? "~" : ($0 as NSString).lastPathComponent })
    }

    private static let home = NSHomeDirectory()

    func stack(_ tab: HostStore.Tab) -> [HostStore.Pane] {
        let tabPanes = store.panes(in: tab.id)
        let front = keyboardCard(tab.id)
        return Array(([front].compactMap(\.self) + tabPanes.filter { $0 !== front }).prefix(5))
    }

    func place(_ pane: HostStore.Pane) -> String {
        let workspace = store.workspace(of: pane.tabID)
        let tab = workspace?.tabs.first { $0.id == pane.tabID }
        return [workspace?.label, tab.map(titleText)].compactMap(\.self).joined(separator: " · ")
    }

    func titleText(_ tab: HostStore.Tab) -> String {
        let title = title(tab)
        return [title.name, title.folder].plainTitle
    }

    func kindTitle(_ pane: HostStore.Pane) -> (name: String, detail: String?)? {
        if store.chooser(pane.id) != nil {
            return ("New Pane", nil)
        }
        if let label = pane.browser {
            return ("Browser", browserTitle(pane, label))
        }
        if let label = pane.plugin {
            return (label.manifest?.name ?? label.plugin, pluginTitle(pane, label))
        }
        return pane.agentTitle.map { (pane.agentLabel ?? "", $0) }
    }
}
