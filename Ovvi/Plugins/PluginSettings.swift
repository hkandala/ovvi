import HerdrKit
import SwiftUI

/// Only the values that differ from the default: a new default reaches whoever never changed it.
@MainActor @Observable
final class PluginSettings {
    static let shared = PluginSettings()
    private var saved: [String: [String: PluginSetting.Value]] = [:]

    private init() {
        reload()
    }

    func reload() {
        saved = Dictionary(uniqueKeysWithValues: Registry.all.map { manifest in
            (manifest.id, PluginPackages.values(of: manifest.id, in: Registry.settings)
                .compactMapValues(PluginSetting.Value.init(json:)))
        })
    }

    func value(_ setting: PluginSetting, of id: String) -> PluginSetting.Value {
        saved[id]?[setting.id].flatMap { setting.fits($0) ? $0 : nil } ?? setting.default
    }

    func values(_ manifest: PluginManifest) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: manifest.settings.map { ($0.id, value($0, of: manifest.id).json) })
    }

    func set(_ value: PluginSetting.Value, _ setting: PluginSetting, of id: String) {
        guard setting.fits(value), value != self.value(setting, of: id) else { return }
        let kept = value == setting.default ? nil : value
        do {
            try PluginPackages.store(kept?.json, setting.id, of: id, in: Registry.settings)
        } catch {
            PluginInstalls.shared.couldNotSave(error)
            return
        }
        saved[id, default: [:]][setting.id] = kept
        // ponytail: a page between its context script and its runtime's start misses the event and keeps the value
        // it had until it loads again; the runtime would ask for the values once if that bites.
        for card in Plugin.cards where card.manifest.id == id {
            card.web.script()
            card.web.bridge?.event("settings", [setting.id: value.json])
        }
    }
}
