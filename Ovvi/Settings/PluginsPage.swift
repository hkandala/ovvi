import HerdrKit
import SwiftUI

struct PluginsPage: View {
    @State private var source = ""

    static var searchRows: [SettingsSearch] {
        Registry.all.flatMap { manifest in
            let place = "Plugins › \(manifest.name.shown)", detail = SettingsDetail.plugin(manifest.id)
            let rows = manifest.settings.map { setting in
                SettingsSearch(id: PluginPage.row(manifest.id, setting.id), title: setting.title.shown, page: .plugins,
                               words: "\(setting.description ?? "") \(setting.section ?? "")".shown, detail: detail,
                               place: place)
            }
            return rows + (manifest.chooser == nil ? [] : [
                SettingsSearch(id: PluginPage.newPaneRow(manifest.id), title: "Show in New Pane",
                               page: .plugins, words: "chooser", detail: detail, place: place),
            ])
        }
    }

    var body: some View {
        let installs = PluginInstalls.shared, typed = source.trimmingCharacters(in: .whitespaces)
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField("Source", text: $source, prompt: Text("npm:package, git:repository or a folder"))
                        .labelsHidden().textFieldStyle(.roundedBorder).onSubmit(install)
                        .accessibilityIdentifier("plugins.source")
                    if let busy = installs.busy[typed] {
                        ProgressView().controlSize(.small)
                        Text(busy).foregroundStyle(.secondary)
                    } else {
                        Button("Install", action: install).buttonStyle(.borderedProminent).disabled(typed.isEmpty)
                    }
                }
            } footer: {
                Text("Ovvi installs with the npm, pnpm or bun in your login shell. It asks before a new plugin runs.")
                    .settingsFooter()
            }
            if let failure = installs.failure {
                NoticeCapsule(tone: .error, text: failure.text) {
                    if let retry = failure.retry {
                        Button("Retry", action: retry).accessibilityIdentifier("notice.retry")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                ForEach(installs.rows) { PluginLink(row: $0) }
            } header: {
                HStack {
                    Text("Installed")
                    Spacer()
                    if let busy = installs.busy.first(where: { $0.value == "Creating…" }) {
                        ProgressView().controlSize(.small)
                        Text("Creating \(busy.key)…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button("New Plugin…") { Task { await installs.create() } }.accessibilityIdentifier("plugins.new")
                    Button("Reload All", systemImage: "arrow.clockwise") { Task { await Plugin.reloadAll() } }
                }
                .controlSize(.small)
            }
        }
        .task { await DefaultPlugins.shared.check() }
    }

    private func install() {
        let text = source
        Task {
            _ = try? await PluginInstalls.shared.install(text)
            if PluginInstalls.shared.failure == nil {
                source = ""
            }
        }
    }
}

private struct PluginLink: View {
    let row: InstalledPlugin

    var body: some View {
        NavigationLink(value: SettingsDetail.plugin(row.id)) {
            HStack(spacing: 10) {
                ProgramTile(icon: row.manifest?.icon ?? Registry.missing)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(row.manifest?.name.shown ?? row.id).lineLimit(1)
                        if let version = row.version {
                            Text(version).foregroundStyle(.secondary)
                        }
                    }
                    Text(row.source).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let busy = row.busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("plugins.\(row.id)")
    }
}
