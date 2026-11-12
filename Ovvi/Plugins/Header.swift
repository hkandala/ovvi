import HerdrKit
import SwiftUI

@MainActor @Observable
final class Header {
    private(set) var controls: [PluginManifest.Control]
    private(set) var focus: [String: Int] = [:]
    private(set) var refused: [String: Int] = [:]
    @ObservationIgnored var send: (([String: Any]) -> Void)?
    @ObservationIgnored var changed: (() -> Void)?

    init(manifest: PluginManifest) {
        controls = manifest.header
    }

    var values: [String: Any] {
        controls.reduce(into: [:]) { values, control in
            if let id = control.id, let value = control.value {
                values[id] = value.json
            }
        }
    }

    func restore(_ values: [String: Any]) {
        for (index, control) in controls.enumerated() {
            if let id = control.id, let value = values[id].flatMap(PluginManifest.Value.init(json:)) {
                controls[index].value = value
            }
        }
    }

    func set(_ id: String, _ change: [String: Any]) {
        guard let index = controls.firstIndex(where: { $0.id == id }) else { return }
        var control = controls[index]
        if let value = change["value"].flatMap(PluginManifest.Value.init(json:)) {
            control.value = value
        }
        if let title = change["title"] as? String {
            control.title = title
        }
        if let label = change["label"] as? String {
            control.label = label.isEmpty ? nil : label
        }
        if let symbol = change["symbol"] as? String {
            control.symbol = symbol.isEmpty ? nil : symbol
        }
        if let badge = change["badge"] {
            let text = (badge as? NSNumber)?.stringValue ?? badge as? String ?? ""
            control.badge = text.isEmpty || text == "0" ? nil : text
        }
        control.links = change["links"] as? Int ?? control.links
        if let items = change["items"] as? [Any] {
            control.items = items.map { PluginManifest.Item(json: $0) }
        }
        for (key, path) in [("hidden", \PluginManifest.Control.hidden), ("enabled", \.enabled), ("busy", \.busy)] {
            if let flag = change[key] as? Bool {
                control[keyPath: path] = flag
            }
        }
        controls[index] = control
        for (key, path) in [("focus", \Header.focus), ("refused", \.refused)] where change[key] as? Bool == true {
            self[keyPath: path][id, default: 0] += 1
        }
        changed?()
    }

    func click(_ id: String, part: Int) {
        send?(["id": id, "part": part])
    }

    func pick(_ id: String, _ value: PluginManifest.Value?, submit: Bool = false) {
        guard let index = controls.firstIndex(where: { $0.id == id }) else { return }
        let control = controls[index], value = submit ? control.value : value
        if let value, control.type != "menu", value != control.value {
            controls[index].value = value
            changed?()
        } else if ["segmented", "field"].contains(control.type), !submit {
            // A field writes back its text as it loses focus: nothing new for the page.
            return
        }
        var event: [String: Any] = ["id": id]
        event["value"] = value?.json
        if submit {
            event["submit"] = true
        }
        send?(event)
    }
}

extension PluginManifest {
    var hasRow: Bool {
        history || !header.isEmpty
    }
}
