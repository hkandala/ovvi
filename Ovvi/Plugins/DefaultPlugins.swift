import HerdrKit
import SwiftUI

/// A default plugin installs from the app's copy only while its folder is missing: a first launch needs no published
/// package. From then on it is an npm install like any other: it updates from npm, never with the app.
@Observable
final class DefaultPlugins {
    static let shared = DefaultPlugins()

    private(set) var installing: Set<String> = []
    private(set) var failures: [String: PluginProblem] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    /// Ahead of any install, which would lose its staging folder.
    private init() {
        let plugins = Registry.plugins, files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: plugins.path)) ?? []
            where name.hasPrefix(PluginPackages.stagingPrefix)
        {
            try? files.removeItem(at: plugins.appending(path: name))
        }
    }

    func install() async {
        for id in Registry.bundled.keys.sorted() {
            if FileManager.default.fileExists(atPath: Registry.plugins.appending(path: id).path) {
                list(id)
            } else {
                await put(id)
            }
        }
    }

    /// Its npm source in `settings.json`, also when the file lost its line or did not read at the install.
    private func list(_ id: String) {
        guard !PluginPackages.sources(Registry.settings).contains(where: { PluginSource($0)?.folder == id }),
              let file = Registry.defaultSources?.appending(path: "\(id)/package.json"),
              let package = try? JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
              let name = package["name"] as? String
        else { return }
        do {
            try PluginPackages.list("npm:" + name, in: Registry.settings, add: true)
        } catch {
            PluginInstalls.shared.couldNotSave(error)
        }
    }

    func installed(_ manifest: PluginManifest) async -> PluginProblem? {
        guard Registry.defaults.contains(manifest.id) else { return nil }
        let id = manifest.id, copy = Registry.plugins.appending(path: id)
        if tasks[id] != nil || !FileManager.default.fileExists(atPath: copy.path) {
            await put(id)
        }
        guard !FileManager.default.fileExists(atPath: copy.path) else { return nil }
        return failures[id] ?? PluginProblem(title: "\(manifest.name.shown) is not installed", text: "",
                                             button: "Try Again")
    }

    private func put(_ id: String) async {
        if let task = tasks[id] {
            return await task.value
        }
        let task = Task { await copy(id) }
        tasks[id] = task
        installing.insert(id)
        await task.value
        tasks[id] = nil
        installing.remove(id)
    }

    private func copy(_ id: String) async {
        guard let source = Registry.defaultSources?.appending(path: id) else { return }
        failures[id] = nil
        let plugins = Registry.plugins, staging = PluginPackages.staging(in: plugins)
        let copy = staging.appending(path: id)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: copy)
            let output = try await PluginPackages.prepare(copy, exec: localExec.value)
            PluginLog.add(id, "installed", output: output)
            try PluginPackages.place(copy, at: plugins.appending(path: id), keeping: staging)
            list(id)
            Registry.reload()
        } catch {
            if let manifest = Registry.bundled[id] {
                failures[id] = .failed(manifest, "could not install", error)
            }
        }
    }
}
