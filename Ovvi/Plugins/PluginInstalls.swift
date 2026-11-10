import AppKit
import HerdrKit

@MainActor @Observable
final class PluginInstalls {
    static let shared = PluginInstalls()

    private(set) var busy: [String: String] = [:]
    var failure: (text: String, retry: (() -> Void)?)?

    var rows: [InstalledPlugin] {
        let sources = PluginPackages.sources(Registry.settings)
        let pairs = sources.compactMap { text in PluginSource(text)?.folder.map { ($0, text) } }
        let installed = Dictionary(pairs) { first, _ in first }
        let plugins = Registry.all.map { manifest -> InstalledPlugin in
            let folder = Registry.package(manifest.id)
            let kind: InstalledPlugin.Kind = if Registry.defaults.contains(manifest.id) {
                .bundled
            } else if let folder, folder.deletingLastPathComponent().standardizedFileURL.path
                == Registry.plugins.standardizedFileURL.path
            {
                installed[folder.lastPathComponent].map(InstalledPlugin.Kind.installed) ?? .folder
            } else {
                .local(folder?.path ?? "")
            }
            return InstalledPlugin(id: manifest.id, manifest: manifest, kind: kind)
        }
        let present = Set((try? FileManager.default.contentsOfDirectory(atPath: Registry.plugins.path)) ?? [])
        let missing = installed.filter { !present.contains($0.key) }.sorted { $0.key < $1.key }
        return plugins + missing.map { InstalledPlugin(id: $0.value, manifest: nil, kind: .installed($0.value)) }
    }

    func install(_ text: String, for agent: Asker? = nil) async throws -> PluginManifest {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let source = PluginSource(text) else {
            throw refuse("Enter npm:<package>, git:<repository> or a folder’s path")
        }
        if let folder = source.folder, !PluginPackages.sources(Registry.settings).contains(text),
           FileManager.default.fileExists(atPath: Registry.plugins.appending(path: folder).path)
        {
            throw refuse("A plugin folder named \(folder) is already installed")
        }
        do {
            return try await run(text, "Installing…") {
                if case let .local(path) = source {
                    try await self.list(local: path, text, for: agent)
                } else {
                    try await self.fetch(source, text, for: agent)
                }
            }
        } catch {
            // The agent has its answer; a Retry from the page would show the agent's prompt as the user's.
            if agent != nil {
                failure?.retry = nil
            }
            throw error
        }
    }

    func update(_ row: InstalledPlugin) async {
        guard case let .installed(text) = row.kind, let source = PluginSource(text) else { return }
        let manifest = try? await run(row.id, "Updating…") {
            try await self.fetch(source, text, for: nil)
        }
        if let manifest, manifest.id != row.id {
            PluginTrust.shared.forget(row.id)
        }
    }

    static func removal(_ row: InstalledPlugin) -> String {
        if case .local = row.kind {
            return "Its folder stays where it is; Ovvi stops loading it."
        }
        return "Its folder in the plugins folder goes to the Trash."
    }

    func remove(_ row: InstalledPlugin) async {
        guard row.kind != .bundled, await Self.ask(
            "Remove “\((row.manifest?.name ?? row.id).shown)”?",
            Self.removal(row),
            button: "Remove",
            destructive: true,
        )
        else { return }
        try? await run(row.id, "Removing…") {
            // First: a settings.json that does not read stops the removal ahead of any change.
            try PluginPackages.store(nil, nil, of: row.id, in: Registry.settings)
            if case let .installed(text) = row.kind {
                try PluginPackages.list(text, in: Registry.settings, add: false)
            }
            if case let .local(path) = row.kind {
                let listed = PluginPackages.sources(Registry.settings).first { Registry.local($0).path == path }
                if let listed {
                    try PluginPackages.list(listed, in: Registry.settings, add: false)
                }
            } else if let folder = Registry.package(row.id) {
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            }
            PluginTrust.shared.forget(row.id)
            Registry.reload()
        }
    }

    func create() async {
        guard let typed = await askName() else { return }
        _ = try? await create(named: typed)
    }

    /// Trusted: the user, or their agent on This Mac, made it.
    func create(named typed: String) async throws -> URL {
        let name = typed.trimmingCharacters(in: .whitespaces).shown
        let id = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.joined(separator: "-")
        guard let template = Registry.folder?.appending(path: "template") else { throw refuse("Ovvi has no template") }
        guard !id.isEmpty else { throw refuse("Use letters or digits in a plugin’s name") }
        let folder = Registry.plugins.appending(path: id)
        guard Registry.plugin(id) == nil, !FileManager.default.fileExists(atPath: folder.path) else {
            throw refuse("A plugin named \(id) is already there")
        }
        return try await run(id, "Creating…") {
            try FileManager.default.createDirectory(at: Registry.plugins, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: template, to: folder)
            do {
                let file = folder.appending(path: "package.json")
                // A quote or a backslash in the name stays text.
                let quoted = try String(decoding: JSONEncoder().encode(name), as: UTF8.self)
                let text = try String(contentsOf: file, encoding: .utf8).replacing("my-plugin", with: id)
                    .replacing("\"My Plugin\"", with: quoted)
                try text.write(to: file, atomically: true, encoding: .utf8)
                let manifest = try PluginManifest(package: Data(contentsOf: file))
                let exec = await localExec.value
                let output = try await PluginPackages.prepare(folder, exec: exec)
                PluginLog.add(id, "created from the template", output: output)
                PluginTrust.shared.allow(manifest)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                PluginLog.add(id, "New Plugin failed: \(error.localizedDescription)")
                throw error
            }
            Registry.reload()
            return folder
        }
    }

    private func askName() async -> String? {
        let alert = NSAlert(), field = NSTextField(string: "")
        field.frame.size.width = 260
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return await Self.ask("New Plugin",
                              "Ovvi copies its template into the plugins folder, then installs and builds it.",
                              button: "Create", alert: alert) ? field.stringValue : nil
    }

    private func fetch(_ source: PluginSource, _ text: String, for agent: Asker?) async throws -> PluginManifest {
        let exec = await localExec.value
        let staged = try await PluginPackages.fetch(source, into: Registry.plugins, exec: exec)
        do {
            let folder = Registry.plugins.appending(path: source.folder ?? "")
            try free(staged.manifest.id, for: folder)
            try await trusts(staged.manifest, from: text, folder: folder, for: agent)
            let output = try await PluginPackages.finish(staged, into: Registry.plugins, exec: exec).output
            PluginLog.add(staged.manifest.id, "installed from \(text)", output: output)
        } catch {
            PluginPackages.discard(staged)
            if !(error is CancellationError) {
                PluginLog.add(staged.manifest.id, "install from \(text) failed: \(error.localizedDescription)")
            }
            throw error
        }
        try installed(staged.manifest, text)
        return staged.manifest
    }

    private func list(local path: String, _ text: String, for agent: Asker?) async throws -> PluginManifest {
        let folder = Registry.local(path)
        let manifest = try PluginManifest(package: Data(contentsOf: folder.appending(path: "package.json")))
        try free(manifest.id, for: folder)
        try await trusts(manifest, from: text, folder: folder, for: agent)
        try installed(manifest, text)
        return manifest
    }

    /// An id the app or another folder has would install a package the registry leaves out.
    private func free(_ id: String, for folder: URL) throws {
        if let other = Registry.package(id), other.standardizedFileURL.path != folder.standardizedFileURL.path {
            throw HerdrError.failed("The id \(id) is taken by \((other.path as NSString).abbreviatingWithTildeInPath)")
        }
    }

    private func installed(_ manifest: PluginManifest, _ source: String) throws {
        try PluginPackages.list(source, in: Registry.settings, add: true)
        PluginTrust.shared.allow(manifest)
        Task { await Plugin.reload(manifest.id, build: false) }
    }

    private func trusts(_ manifest: PluginManifest, from source: String, folder: URL, for agent: Asker?) async throws {
        let new = !PluginPackages.sources(Registry.settings).contains(source)
        guard new || !PluginTrust.shared.allows(manifest) else { return }
        let asks = agent.map { "\($0.name) asks to install it." }
        let fetched = PluginSource(source)?.folder == nil ? nil : source
        let text = [asks ?? "", PluginTrust.origin(manifest, source: fetched, folder: folder),
                    manifest.description.shown, PluginTrust.warning].filter { !$0.isEmpty }
        // An agent's prompt is a sheet only: a modal alert would hold every request and could come up over the
        // user's app.
        if let agent, agent.window == nil {
            throw refuse("no window to ask the user for \(agent.name)")
        }
        let alert = NSAlert()
        if manifest.chooser != nil {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Show in New Pane"
            alert.suppressionButton?.state = Registry.inNewPane(manifest) ? .on : .off
        }
        guard await Self.ask("Install “\(manifest.name.shown)”?", text.joined(separator: "\n\n"), button: "Install",
                             alert: alert, for: agent) else { throw CancellationError() }
        if let box = alert.suppressionButton, alert.showsSuppressionButton {
            Registry.show(manifest.id, inNewPane: box.state == .on)
        }
    }

    /// An agent's prompt never takes the user's keys: Return is not Install, so typing here installs nothing.
    static func ask(_ title: String, _ text: String, button: String, destructive: Bool = false,
                    alert: NSAlert = NSAlert(), for agent: Asker? = nil) async -> Bool
    {
        alert.messageText = title
        alert.informativeText = text
        let action = alert.addButton(withTitle: button)
        if destructive {
            (action.hasDestructiveAction, action.keyEquivalent) = (true, "")
        }
        alert.addButton(withTitle: "Cancel")
        if agent != nil {
            alert.buttons[0].keyEquivalent = ""
            NSApp.requestUserAttention(.informationalRequest)
        }
        guard let window = agent?.window ?? NSApp.keyWindow else {
            return alert.runModal() == .alertFirstButtonReturn
        }
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    func couldNotSave(_ error: any Error) {
        failure = ("Could not save settings.json: \(error.localizedDescription)", nil)
    }

    private func refuse(_ text: String) -> HerdrError {
        failure = (text, nil)
        return .failed(text)
    }

    private func run<T>(_ id: String, _ doing: String, _ body: @escaping () async throws -> T) async throws -> T {
        if let busy = busy[id] {
            throw HerdrError.failed("\(id) is busy: \(busy)")
        }
        busy[id] = doing
        failure = nil
        defer { busy[id] = nil }
        do {
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let text = (error as? ManifestError).map { "package.json: \($0.text)" } ?? error.localizedDescription
            failure = (text.firstLine, { Task { _ = try? await self.run(id, doing, body) } })
            if Registry.plugin(id) != nil {
                PluginLog.add(id, "\(doing) failed: \(text)")
            }
            throw HerdrError.failed(text)
        }
    }
}

struct Asker {
    let name: String
    weak var window: NSWindow?
}

struct InstalledPlugin: Identifiable {
    enum Kind: Equatable {
        case bundled
        case installed(String)
        case local(String)
        case folder
    }

    let id: String
    let manifest: PluginManifest?
    let kind: Kind

    var version: String? {
        guard let manifest else { return "Not installed" }
        return manifest.entry == nil ? nil : manifest.version.shown
    }

    @MainActor var busy: String? {
        PluginInstalls.shared.busy[id] ?? (DefaultPlugins.shared.installing.contains(id) ? "Installing…" : nil)
    }

    var source: String {
        switch kind {
        case .bundled: "Comes with Ovvi"
        case let .installed(source): source
        case let .local(path): (path as NSString).abbreviatingWithTildeInPath
        case .folder: Registry.package(id).map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
        }
    }
}
