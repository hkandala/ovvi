import Foundation
import HerdrKit
import os

@MainActor
enum Registry {
    static let browser = PluginManifest(
        id: "browser", name: "Browser", icon: "globe", description: "Web page", keywords: ["web", "url", "localhost"],
        opens: .init(urls: ["http://*", "https://*", "file://*"]), chooser: "Browser", settings: [network],
    )

    static let network = PluginSetting(
        id: "network", type: "choice", title: "Web pages on remote machines load through", default: .text("machine"),
        description: "For new cards. The machine chip in a card switches it.",
        options: [.init(value: "machine", title: "The Machine"), .init(value: "mac", title: "This Mac")],
    )

    static var all: [PluginManifest] {
        current.loaded.all
    }

    static var defaults: Set<String> {
        current.loaded.defaults
    }

    static var bundled: [String: PluginManifest] {
        current.loaded.bundled
    }

    @Observable final class Current {
        var loaded = load()
        var hidden = Registry.hidden()
    }

    private static let current = Current()

    static func reload() {
        current.loaded = load()
        current.hidden = hidden()
        PluginSettings.shared.reload()
    }

    static func inNewPane(_ manifest: PluginManifest) -> Bool {
        manifest.chooser != nil && !current.hidden.contains(manifest.id)
    }

    static func hiddenInNewPane(_ id: String) -> Bool {
        current.hidden.contains(id)
    }

    static func show(_ id: String, inNewPane: Bool) {
        do {
            try PluginPackages.list(id, in: settings, add: !inNewPane, key: hideKey)
        } catch {
            PluginInstalls.shared.couldNotSave(error)
        }
        current.hidden = hidden()
    }

    private static let hideKey = "hideInNewPane"

    private static func hidden() -> Set<String> {
        Set(PluginPackages.sources(settings, key: hideKey))
    }

    static var places: [String: Set<String>] {
        current.loaded.places
    }

    static func files(_ id: String) -> URL? {
        guard let entry = plugin(id)?.entry else { return nil }
        return package(id)?.appending(path: entry).deletingLastPathComponent()
    }

    static func package(_ id: String) -> URL? {
        current.loaded.folders[id]
    }

    static let folder = Bundle.main.resourceURL?.appending(path: "web")

    static let defaultSources = folder?.appending(path: "defaults")

    nonisolated static let testConfig = UserDefaults.standard.string(forKey: "configFolder")

    static let config = testConfig.map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/" + Self.name)

    static let plugins = config.appending(path: "plugins")

    #if DEBUG
        nonisolated static let name = "ovvi-dev", logs = "Ovvi Dev"
    #elseif TIP
        nonisolated static let name = "ovvi-tip", logs = "Ovvi Tip"
    #else
        nonisolated static let name = "ovvi", logs = "Ovvi"
    #endif

    static let settings = config.appending(path: "settings.json")

    static func plugin(_ id: String) -> PluginManifest? {
        current.loaded.byID[id]
    }

    static var symbols: Set<String> {
        current.loaded.symbols
    }

    static let missing = "puzzlepiece.extension"

    static func openers(_ path: String, options: Bool = false) -> [PluginManifest] {
        let ranked = all.compactMap { plugin in
            plugin.rank(file: path).flatMap { options || plugin.opens.priority == "default" ? ($0, plugin) : nil }
        }
        return ranked.sorted { first, second in
            let (mine, theirs) = (defaults.contains(first.1.id), defaults.contains(second.1.id))
            return first.0 != second.0 ? first.0 > second.0 : mine != theirs ? theirs : first.1.id < second.1.id
        }.map(\.1)
    }

    static func openers(for arg: String) -> [PluginManifest] {
        guard URL(string: arg)?.isWebAddress == true else {
            return arg.hasSuffix("/") ? all.filter(\.opens.folders) : openers(arg)
        }
        let matches = all.filter { $0.id != browser.id && $0.opens.priority == "default" && $0.opens(url: arg) }
        return matches.filter { !defaults.contains($0.id) } + matches.filter { defaults.contains($0.id) } + [browser]
    }

    private static let log = Logger(ovvi: "plugins")

    struct Loaded {
        let all: [PluginManifest], defaults: Set<String>, folders: [String: URL], bundled: [String: PluginManifest]
        let byID: [String: PluginManifest], symbols: Set<String>
        let problems: [String: Problem]
        let places: [String: Set<String>]

        init(all: [PluginManifest], defaults: Set<String>, folders: [String: URL], bundled: [String: PluginManifest],
             problems: [String: Problem])
        {
            (self.all, self.defaults, self.folders, self.bundled, self.problems) =
                (all, defaults, folders, bundled, problems)
            places = [folders["explorer"], defaultSources?.appending(path: "explorer")]
                .lazy.compactMap { $0.flatMap { try? Data(contentsOf: $0.appending(path: "places.json")) } }.first
                .flatMap { try? JSONDecoder().decode([String: Set<String>].self, from: $0) } ?? [:]
            byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            symbols = Set(all.map(\.icon) + ExplorerPlace.allCases.map(\.symbol)
                + [missing])
                .subtracting(programIcons.map(\.id))
        }
    }

    private static func load() -> Loaded {
        leftOut = [:]
        let bundled = packages(in: defaultSources)
        let mine = bundled.map { manifest, url in
            let copy = plugins.appending(path: url.lastPathComponent)
            return package(copy) ?? (manifest, copy)
        }
        var seen = [browser.id: "the app"]
        var folders = Set<String>()
        let found = mine + paths().compactMap { package($0, named: true) }
            + packages(in: plugins)
        // A settings path into the plugins folder is the same package.
        let kept = found.filter { folders.insert($0.url.standardizedFileURL.path).inserted }.filter { manifest, url in
            if let first = seen[manifest.id] {
                note(url, "\(url.path): the id \(manifest.id) is taken by \(first)")
                return false
            }
            seen[manifest.id] = url.path
            return true
        }
        let defaults = Set(mine.map(\.manifest.id)), manifests = kept.map(\.manifest)
        return Loaded(all: [browser] + manifests.filter { defaults.contains($0.id) }
            + manifests.filter { !defaults.contains($0.id) }.sorted { $0.id < $1.id },
            defaults: defaults.union([browser.id]),
            folders: Dictionary(kept.map { ($0.manifest.id, $0.url) }) { first, _ in first },
            bundled: Dictionary(bundled.map { ($0.url.lastPathComponent, $0.manifest) }) { first, _ in first },
            problems: leftOut.filter { problem in !manifests.contains { $0.id == problem.key } })
    }

    private static func packages(in folder: URL?) -> [(manifest: PluginManifest, url: URL)] {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        return names.sorted().filter { !$0.hasPrefix(".") }.compactMap { package(folder.appending(path: $0)) }
    }

    private static func package(_ folder: URL, named: Bool = false) -> (manifest: PluginManifest, url: URL)? {
        let file = folder.appending(path: "package.json")
        guard let data = try? Data(contentsOf: file) else {
            if named {
                note(folder, "\(file.path): no package.json")
            }
            return nil
        }
        do {
            return try (PluginManifest(package: data), folder)
        } catch {
            let text = "\(file.path): \(error.text)"
            note(folder, text)
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let id = (json?["ovvi"] as? [String: Any])?["id"] as? String {
                leftOut[id] = Problem(folder: folder, error: "package.json: \(error.text)")
                if id != folder.lastPathComponent {
                    PluginLog.add(id, text)
                }
            }
            return nil
        }
    }

    private static var leftOut: [String: Problem] = [:]

    struct Problem {
        let folder: URL
        let error: String
    }

    static var problems: [String: Problem] {
        current.loaded.problems
    }

    static func problem(_ id: String) -> String? {
        current.loaded.problems[id].map { "\($0.folder.path)/\($0.error)" }
    }

    private static func note(_ folder: URL, _ text: String) {
        log.error("\(text, privacy: .public)")
        PluginLog.add(folder.lastPathComponent, text)
    }

    private static func paths() -> [URL] {
        PluginPackages.sources(settings)
            .filter { ["/", "~", "."].contains($0.prefix(1)) }.map(local)
    }

    static func local(_ path: String) -> URL {
        let path = (path as NSString).expandingTildeInPath
        return (path.hasPrefix("/") ? URL(filePath: path) : config.appending(path: path)).standardizedFileURL
    }
}
