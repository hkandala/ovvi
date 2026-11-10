import AppKit
import CryptoKit
import HerdrKit

@MainActor @Observable
final class DefaultPlugins {
    static let shared = DefaultPlugins()

    private(set) var installing: Set<String> = []
    private(set) var failures: [String: PluginProblem] = [:]
    private(set) var offers: [String: String?] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    /// `copy` is hashed after the install: a package manager may write its lockfile into it.
    private struct Record: Codable {
        let version: String, source: String, copy: String
    }

    private static var records: URL {
        Registry.plugins.appending(path: ".defaults.json")
    }

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
        let records = Self.read()
        for (id, manifest) in Registry.bundled {
            let copy = Registry.plugins.appending(path: id)
            guard FileManager.default.fileExists(atPath: copy.path) else {
                await put(id)
                continue
            }
            if let record = records[id], Self.newer(manifest.version, than: record.version),
               await Self.hash(copy) == record.copy
            {
                await put(id)
            }
        }
        await check()
    }

    func check() async {
        let records = Self.read()
        var offers: [String: String?] = [:]
        for (id, manifest) in Registry.bundled where !installing.contains(id) {
            let copy = Registry.plugins.appending(path: id)
            guard FileManager.default.fileExists(atPath: copy.path),
                  let source = Registry.defaultSources?.appending(path: id)
            else { continue }
            let record = records[id]
            if Self.newer(manifest.version, than: record?.version ?? "") {
                offers[id] = .some(manifest.version)
            } else if await Self.hash(copy) != record?.copy {
                offers[id] = .some(nil)
            } else if await Self.hash(source) != record?.source {
                offers[id] = .some(nil)
            }
        }
        self.offers = offers
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

    func reset(_ id: String) async {
        let copy = Registry.plugins.appending(path: id), record = Self.read()[id]
        let edited = await Self.hash(copy) != record?.copy
        if edited, await !PluginInstalls.ask("Replace your edited \(Registry.bundled[id]?.name ?? id)?",
                                             "Your copy goes to the Trash, and Ovvi installs its own.",
                                             button: "Replace", destructive: true)
        {
            return
        }
        await put(id, trash: edited)
        await check()
    }

    func put(_ id: String, trash: Bool = false) async {
        if let task = tasks[id] {
            return await task.value
        }
        let task = Task { await copy(id, trash: trash) }
        tasks[id] = task
        installing.insert(id)
        await task.value
        tasks[id] = nil
        installing.remove(id)
    }

    private func copy(_ id: String, trash: Bool) async {
        guard let source = Registry.defaultSources?.appending(path: id) else { return }
        failures[id] = nil
        let plugins = Registry.plugins,
            had = FileManager.default.fileExists(atPath: plugins.appending(path: id).path)
        let staging = PluginPackages.staging(in: plugins), copy = staging.appending(path: id)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: copy)
            let exec = await localExec.value
            let output = try await PluginPackages.prepare(copy, exec: exec)
            PluginLog.add(id, "installed", output: output)
            let hashes = await (Self.hash(source), Self.hash(copy))
            try PluginPackages.place(copy, at: plugins.appending(path: id), keeping: staging)
            if trash {
                try? FileManager.default.trashItem(at: staging.appending(path: "old"), resultingItemURL: nil)
            }
            var records = Self.read()
            records[id] = Record(version: Registry.bundled[id]?.version ?? "", source: hashes.0, copy: hashes.1)
            try JSONEncoder().encode(records).write(to: Self.records, options: .atomic)
            offers[id] = nil
            if had {
                Task { await Plugin.reload(id, build: false) }
            } else {
                Registry.reload()
            }
        } catch {
            if let manifest = Registry.bundled[id] {
                failures[id] = .failed(manifest, "could not install", error)
            }
        }
    }

    private static func newer(_ version: String, than other: String) -> Bool {
        version.compare(other, options: .numeric) == .orderedDescending
    }

    private static func read() -> [String: Record] {
        (try? JSONDecoder().decode([String: Record].self, from: Data(contentsOf: records))) ?? [:]
    }

    private nonisolated static func hash(_ folder: URL) async -> String {
        var hasher = SHA256()
        let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: .skipsHiddenFiles)
        var files: [URL] = []
        while let url = walk?.nextObject() as? URL {
            if ["node_modules", "dist"].contains(url.lastPathComponent) {
                walk?.skipDescendants()
            } else if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                files.append(url)
            }
        }
        let base = folder.standardizedFileURL.path.count
        for file in files.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data(file.standardizedFileURL.path.dropFirst(base).utf8))
            hasher.update(data: (try? Data(contentsOf: file)) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
