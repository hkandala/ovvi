import AppKit
import HerdrKit
import WebKit

@MainActor
final class PluginBuilds {
    static let shared = PluginBuilds()

    /// The next build waits for the last, so two never write one plugin's folder at once.
    private var running: [String: Task<PluginProblem?, Never>] = [:]

    func build(_ manifest: PluginManifest) async -> PluginProblem? {
        let id = manifest.id, last = running[id]
        let task = Task { () -> PluginProblem? in
            _ = await last?.value
            // An author's script runs only for a plugin the user confirmed.
            guard PluginTrust.shared.allows(manifest), let package = Registry.package(id) else { return nil }
            if let problem = await DefaultPlugins.shared.installed(manifest) {
                return problem
            }
            let start = ContinuousClock.now
            do {
                guard let output = try await PluginPackages.build(package, exec: localExec.value) else { return nil }
                PluginLog.add(
                    id,
                    "built in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])))",
                    output: output,
                )
                return Self.built(manifest)
            } catch {
                return .failed(manifest, "did not build", error, builds: true)
            }
        }
        running[id] = task
        return await task.value
    }

    func failure(_ id: String) async -> PluginProblem? {
        await running[id]?.value
    }

    static func built(_ manifest: PluginManifest) -> PluginProblem? {
        guard let package = Registry.package(manifest.id), let entry = manifest.entry,
              !FileManager.default.fileExists(atPath: package.appending(path: entry).path) else { return nil }
        let script = PluginPackages.builds(package)
        return .noted(manifest, PluginProblem(
            title: "\(manifest.name.shown) is not built",
            text: "\(entry) is missing. " + (script ? "Build runs its build script."
                : "Its package has no build script: build it with its own tools."),
            button: script ? "Build" : nil, builds: true,
        ))
    }

    /// `tsc` finds `@ovvi/plugin-api` here from any plugin in the folder.
    static func writeTypes() {
        guard let source = Registry.folder?.appending(path: "plugin-api") else { return }
        let target = Registry.plugins.appending(path: "node_modules/@ovvi/plugin-api")
        Task.detached {
            let files = FileManager.default
            for name in ["package.json", "ovvi.d.ts"] {
                let data = try? Data(contentsOf: source.appending(path: name))
                guard let data, data != (try? Data(contentsOf: target.appending(path: name))) else { continue }
                try? files.createDirectory(at: target, withIntermediateDirectories: true)
                try? data.write(to: target.appending(path: name), options: .atomic)
            }
        }
    }
}

struct PluginProblem {
    let title: String
    let text: String
    var button: String? = "Reload"
    var builds = false

    @MainActor func toast(_ id: String) -> Toast {
        Toast(
            text: "\(title): \(text.firstLine)",
            other: nil,
            main: .init(title: "Try Again") { Task { await Plugin.reload(id) } },
        )
    }

    static func failed(_ manifest: PluginManifest, _ what: String, _ error: any Error,
                       builds: Bool = false) -> PluginProblem
    {
        let title = error is PluginPackages.NoManager ? "\(manifest.name.shown) needs Node.js"
            : "\(manifest.name.shown) \(what)"
        return noted(manifest, PluginProblem(title: title, text: error.localizedDescription, button: "Try Again",
                                             builds: builds))
    }

    static func noted(_ manifest: PluginManifest, _ problem: PluginProblem) -> PluginProblem {
        PluginLog.add(manifest.id, "\(problem.title): \(problem.text)")
        return problem
    }
}

enum PluginLog {
    nonisolated static let folder = Registry.testConfig
        .map { URL(filePath: $0).appending(path: "logs/plugins") }
        ?? URL.homeDirectory.appending(path: "Library/Logs/\(Registry.logs)/plugins")
    private nonisolated static let queue = DispatchQueue(label: "dev.ovvi.app.plugin-log")

    nonisolated static func file(_ id: String) -> URL {
        folder.appending(path: "\(id).log")
    }

    nonisolated static func add(_ id: String, _ text: String, output: String) {
        add(id, "\(text):\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    nonisolated static func add(_ id: String, _ text: String) {
        // Indented, so a page's line breaks never read as the app's own lines.
        let text = text.replacingOccurrences(of: "\n", with: "\n  ")
        let line = Data("\(Date.now.ISO8601Format(.iso8601(timeZone: .current))) \(text)\n".utf8)
        queue.async {
            let file = PluginLog.file(id), files = FileManager.default
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            // ponytail: starts over past 1 MB; keep a second file if authors need more history.
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            if size.map({ $0 > 1 << 20 }) ?? true {
                files.createFile(atPath: file.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        }
    }

    /// On the queue: after the lines on their way.
    nonisolated static func show(_ id: String) {
        queue.async {
            let file = PluginLog.file(id)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            DispatchQueue.main.async { NSWorkspace.shared.open(file) }
        }
    }
}

extension WebCard {
    func reload() {
        ready = false
        guard let bridge else { return }
        loads += 1
        let load = loads
        Task { [weak self] in
            // Only the last reload loads: Allow and a Reload Plugin may overlap.
            guard await bridge.prepare(), let self, load == loads else { return }
            bridge.failure = nil
            bridge.reset()
            script()
            view.load(URLRequest(url: PluginScheme.url(plugin)))
        }
    }
}

extension Bridge {
    func prepare() async -> Bool {
        guard let plugin else { return false }
        let manifest = plugin.manifest
        guard PluginTrust.shared.allows(manifest) else {
            plugin.web.ready = true
            return false
        }
        let problem = await DefaultPlugins.shared.installed(manifest)
        let failed = await PluginBuilds.shared.failure(manifest.id)
        if let problem = problem ?? PluginBuilds.built(manifest) {
            failure = problem
            plugin.web.ready = true
            return false
        }
        if let failed, plugin.web.loads == 1 {
            plugin.web.toast = failed.toast(manifest.id)
        }
        return true
    }
}

extension Plugin {
    static var cards: [Plugin] {
        WindowPages.windows.flatMap(\.terminals.plugins.values)
    }

    /// ponytail: Discard on the first dirty card drops every card's edits, and a card made again starts from its state
    /// file (up to 500 ms behind); ask per card and hand the state over if that bites.
    @discardableResult
    static func reload(_ id: String, asked: Bool = false, build: Bool = true, keepEdits: Bool = false) async
        -> PluginProblem?
    {
        if !asked, let dirty = cards.first(where: { $0.manifest.id == id && $0.dirty }) {
            dirty.leave { _ in Task { await reload(id, asked: true, build: build) } }
            return nil
        }
        Registry.reload()
        guard let manifest = Registry.plugin(id), manifest.entry != nil else { return nil }
        let cards = cards.filter { $0.manifest == manifest }
        guard build, let problem = await PluginBuilds.shared.build(manifest) else {
            cards.filter { !keepEdits || !$0.dirty }.forEach { $0.web.reload() }
            return nil
        }
        for card in cards {
            if card.web.bridge?.failure != nil || !card.web.ready {
                card.web.bridge?.failure = problem
                card.web.ready = true
            } else {
                card.web.bridge?.dropToast()
                card.web.toast = problem.toast(id)
            }
        }
        return problem
    }

    static func reloadAll(asked: Bool = false) async {
        if !asked, let dirty = cards.first(where: \.dirty) {
            dirty.leave { _ in Task { await reloadAll(asked: true) } }
            return
        }
        Registry.reload()
        for id in Set(cards.map(\.manifest.id)) {
            await reload(id, asked: true)
        }
    }
}

extension String {
    var firstLine: String {
        split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? self
    }
}
