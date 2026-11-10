import HerdrKit
import SwiftUI

struct PluginPage: View {
    let id: String
    @Environment(\.dismiss) private var dismiss

    static func row(_ plugin: String, _ setting: String) -> String {
        "plugin.\(plugin).\(setting)"
    }

    /// `+` is in no setting's id.
    static func newPaneRow(_ plugin: String) -> String {
        "plugin.\(plugin).+new-pane"
    }

    var body: some View {
        let row = PluginInstalls.shared.rows.first { $0.id == id }
        Form {
            if let failure = PluginInstalls.shared.failure {
                NoticeCapsule(tone: .error, text: failure.text) {}.frame(maxWidth: .infinity)
            }
            if let row {
                Section { PluginSummary(row: row, gone: { dismiss() }) }
                if let manifest = row.manifest {
                    let sections = Self.sections(manifest.settings)
                    ForEach(sections, id: \.offset) { index, section in
                        Section {
                            ForEach(section.settings, id: \.id) { SettingRow(setting: $0, plugin: id) }
                            if index == sections.count - 1 {
                                inOvvi(manifest)
                            }
                        } header: {
                            Text(section.title)
                        } footer: {
                            if Registry.defaults.contains(id), index == sections.count - 1 {
                                Text("New cards start with the settings above. A card keeps its own choice once you "
                                    + "change it in its header.").settingsFooter()
                            }
                        }
                    }
                    if sections.isEmpty, manifest.chooser != nil {
                        Section { inOvvi(manifest) }
                    }
                }
                if row.kind != .bundled {
                    PluginRemove(row: row, gone: { dismiss() })
                }
            }
        }
        // A pushed page takes no style from the stack it is pushed on.
        .formStyle(.grouped)
        .navigationTitle(row?.manifest?.name.shown ?? id)
        .scrollsToRing()
    }

    @ViewBuilder
    private func inOvvi(_ manifest: PluginManifest) -> some View {
        if manifest.chooser != nil {
            NewPaneSwitch(manifest: manifest).accessibilityIdentifier("plugins.\(id).new-pane")
                .settingsRow(Self.newPaneRow(id))
        }
        if id == Registry.browser.id {
            LabeledContent("Approved websites") {
                Button("Show in Privacy") { SettingsRoute.shared.open(.privacy) }
            }
        }
    }

    private static func sections(_ settings: [PluginSetting])
        -> [(offset: Int, element: (title: String, settings: [PluginSetting]))]
    {
        let groups = settings.reduce(into: [(title: String, settings: [PluginSetting])]()) { groups, setting in
            if let title = setting.section ?? (groups.isEmpty ? "Settings" : nil) {
                groups.append((title.shown, [setting]))
            } else {
                groups[groups.count - 1].settings.append(setting)
            }
        }
        return Array(groups.enumerated())
    }
}

private struct PluginSummary: View {
    let row: InstalledPlugin
    let gone: () -> Void

    var body: some View {
        let installs = PluginInstalls.shared, defaults = DefaultPlugins.shared, id = "plugins.\(row.id)"
        let manifest = row.manifest
        let lines = [manifest?.description.shown ?? "", row.source]
        SettingsHeader(title: manifest?.name.shown ?? row.id, note: row.version, lines: lines) {
            ProgramTile(icon: manifest?.icon ?? Registry.missing).scaleEffect(2)
        } actions: {
            if let busy = row.busy {
                ProgressView().controlSize(.small)
                Text(busy).foregroundStyle(.secondary)
            } else {
                if case .installed = row.kind {
                    Button(manifest == nil ? "Install" : "Update") {
                        Task {
                            await installs.update(row)
                            if !installs.rows.contains(where: { $0.id == row.id }) {
                                gone()
                            }
                        }
                    }
                    .accessibilityIdentifier("\(id).update")
                }
                if row.kind == .bundled, let offer = defaults.offers[row.id] {
                    Button(offer.map { "Update to Version \($0)" } ?? "Reset to Default") {
                        Task { await defaults.reset(row.id) }
                    }
                }
                if manifest?.entry != nil {
                    Button("Show Log") { PluginLog.show(row.id) }
                    Button("Reload") { Task { await Plugin.reload(row.id) } }
                }
            }
        }
    }
}

private struct PluginRemove: View {
    let row: InstalledPlugin
    let gone: () -> Void

    var body: some View {
        let installs = PluginInstalls.shared
        Section {
            LabeledContent {
                Button("Remove…", role: .destructive) {
                    Task {
                        await installs.remove(row)
                        if !installs.rows.contains(where: { $0.id == row.id }) {
                            gone()
                        }
                    }
                }
                .disabled(installs.busy[row.id] != nil)
                .accessibilityIdentifier("plugins.\(row.id).remove")
            } label: {
                Text("Remove \((row.manifest?.name ?? row.id).shown)")
                Text(PluginInstalls.removal(row))
            }
        }
    }
}

private struct SettingRow: View {
    let setting: PluginSetting
    let plugin: String
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        let store = PluginSettings.shared, value = store.value(setting, of: plugin)
        let set = { (value: PluginSetting.Value) in store.set(value, setting, of: plugin) }
        Group {
            switch (setting.type, value) {
            case let ("toggle", .bool(isOn)):
                Toggle(isOn: Binding { isOn } set: { set(.bool($0)) }) { label }
            case ("choice", _):
                let options = setting.options ?? []
                let picker = Picker(selection: Binding { value } set: { set($0) }) {
                    ForEach(options, id: \.value) {
                        Text($0.title.shown).tag(PluginSetting.Value.text($0.value))
                    }
                } label: { label }
                if options.count <= 4, options.map(\.title.count).reduce(0, +) <= 24 {
                    picker.pickerStyle(.segmented)
                } else {
                    picker
                }
            case let ("number", .number(number)):
                let range = (setting.min ?? -1e9) ... (setting.max ?? 1e9)
                LabeledContent {
                    HStack(spacing: 4) {
                        TextField("", value: Binding { number } set: { set(.number(min(max($0, range.lowerBound),
                                                                                       range.upperBound))) },
                        format: .number)
                            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 70)
                        if let unit = setting.unit {
                            Text(unit.shown).foregroundStyle(.secondary)
                        }
                        Stepper("", value: Binding { number } set: { set(.number($0)) }, in: range,
                                step: setting.step ?? 1).labelsHidden()
                    }
                } label: { label }
            case let (_, .text(text)):
                LabeledContent {
                    TextField(setting.title.shown, text: Binding { draft ?? text } set: { draft = $0 },
                              prompt: Text((setting.placeholder ?? (setting.type == "path"
                                      ? "A \(setting.kind ?? "file")’s path" : "")).shown))
                        .labelsHidden().multilineTextAlignment(.trailing).truncationMode(.middle).frame(width: 220)
                        .focused($focused)
                        .onSubmit { save() }
                        .onChange(of: focused) {
                            if !focused {
                                save()
                            }
                        }
                } label: { label }
            default:
                EmptyView()
            }
        }
        .accessibilityIdentifier("plugins.\(plugin).setting.\(setting.id)")
        .settingsRow(PluginPage.row(plugin, setting.id))
    }

    @ViewBuilder
    private var label: some View {
        Text(setting.title.shown)
        if let description = setting.description {
            Text(description.shown)
        }
    }

    private func save() {
        if let draft {
            PluginSettings.shared.set(.text(draft), setting, of: plugin)
        }
        draft = nil
    }
}
