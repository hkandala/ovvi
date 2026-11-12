import HerdrKit
import SwiftUI

extension CommandList {
    static func pluginCard(_ plugin: Plugin?) -> [Command] {
        guard let plugin else { return [] }
        let id = plugin.manifest.id
        return [
            Command(section: .pane, title: "Reload Plugin", key: .redraw,
                    group: .plugins, symbol: "arrow.clockwise", keywords: "plugin build refresh",
                    action: { Task { await Plugin.reload(id) } }),
            Command(section: .pane, title: "Show Log", group: .plugins, symbol: "doc.text.magnifyingglass",
                    keywords: "plugin build errors console debug") { PluginLog.show(id) },
        ]
    }

    static let reloadPlugins = Command(section: .palette, title: "Reload Plugins", group: .plugins,
                                       symbol: "arrow.clockwise",
                                       keywords: "plugin build refresh packages") { Task { await Plugin.reloadAll() } }
}
