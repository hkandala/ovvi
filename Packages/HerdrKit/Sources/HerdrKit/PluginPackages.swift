import Foundation

public enum PluginSource: Equatable, Sendable {
    case npm(String)
    case git(url: String, ref: String?)
    case local(String)

    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("npm:") {
            let spec = String(text.dropFirst(4))
            guard !spec.isEmpty, !spec.hasPrefix("-") else { return nil }
            self = .npm(spec)
        } else if text.hasPrefix("git:") || ["https://", "http://", "ssh://"].contains(where: text.hasPrefix) {
            var url = text.hasPrefix("git:") ? String(text.dropFirst(4)) : text
            var ref: String?
            // The ref is the last part's `@…`: `git@host:x/y` has its `@` in the host.
            if let slash = url.lastIndex(of: "/"), let sign = url[slash...].lastIndex(of: "@") {
                ref = String(url[url.index(after: sign)...])
                url = String(url[..<sign])
            }
            guard !url.isEmpty, !url.hasPrefix("-"), ref?.hasPrefix("-") != true, ref?.isEmpty != true else {
                return nil
            }
            if !url.contains("://"), !url.hasPrefix("/"), !url.hasPrefix("git@") {
                url = "https://" + url
            }
            self = .git(url: url, ref: ref)
        } else if ["/", "~", "."].contains(text.prefix(1)) {
            self = .local(text)
        } else {
            return nil
        }
    }

    public var folder: String? {
        let name: Substring
        switch self {
        case let .npm(spec):
            // A tarball's path, `@scope/name@range` or `name@range`.
            let path = ["/", ".", "~"].contains(spec.prefix(1)) || spec.hasPrefix("file:")
            let bare = path ? Substring(spec) : spec.prefix(1) + spec.dropFirst().prefix { $0 != "@" }
            name = (bare.split(separator: "/").last ?? "").replacing(/\.(tgz|tar\.gz)$/, with: "")
        case let .git(url, _):
            name = (url.split(separator: "/").last ?? "").replacing(/\.git$/, with: "")
        case .local: return nil
        }
        // The plugins folder's `node_modules` holds the host types package.
        return name.isEmpty || name.hasPrefix(".") || name == "node_modules" ? nil : String(name)
    }
}

public enum PluginPackages {
    /// Its manifest is read ahead of any of its code or scripts: the trust prompt shows it, then `finish` or `discard`.
    public struct Staged: Sendable {
        public let source: PluginSource
        public let manifest: PluginManifest
        public let folder: URL
        let staging: URL
    }

    /// No scripts run.
    public static func fetch(_ source: PluginSource, into plugins: URL, exec: any Exec) async throws -> Staged {
        guard source.folder != nil else { throw HerdrError.failed("A local path is not installed") }
        let staging = staging(in: plugins)
        let folder = staging.appending(path: "package")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            switch source {
            case let .npm(spec):
                guard await exec.succeeds("command -v npm", []) else {
                    throw HerdrError.failed("Installing from npm needs npm on your PATH")
                }
                let packed = try await exec.checkedOutput(["npm", "pack", spec, "--pack-destination", staging.path,
                                                           "--json", "--ignore-scripts"], timeout: .seconds(300))
                let json = try? JSONSerialization.jsonObject(with: Data(packed.utf8)) as? [[String: Any]]
                guard let file = json?.first?["filename"] as? String else {
                    throw HerdrError.failed("npm pack printed no package")
                }
                // A scoped package's tarball name has no folder in it.
                let tarball = staging.appending(path: (file as NSString).lastPathComponent).path
                // The fetch's bound for each step: the default 10 s runs out on a loaded Mac.
                _ = try await exec.checkedOutput(["tar", "-xzf", tarball, "-C", staging.path], timeout: .seconds(300))
                try? FileManager.default.removeItem(atPath: tarball)
            case let .git(url, ref):
                let git = ["env", "GIT_TERMINAL_PROMPT=0", "git"]
                _ = try await exec.checkedOutput(git + ["clone", "--quiet", "--", url, folder.path],
                                                 timeout: .seconds(300))
                if let ref {
                    _ = try await exec.checkedOutput(git + ["-C", folder.path, "checkout", "--quiet", ref, "--"],
                                                     timeout: .seconds(300))
                }
            case .local: break
            }
            let manifest = try PluginManifest(package: Data(contentsOf: folder.appending(path: "package.json")))
            return Staged(source: source, manifest: manifest, folder: folder, staging: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Builds it only with no built entry yet: a published package ships its build.
    public static func finish(_ staged: Staged, into plugins: URL, exec: any Exec) async throws
        -> (folder: URL, output: String)
    {
        defer { discard(staged) }
        var output = try await dependencies(staged.folder, exec: exec)
        if !FileManager.default.fileExists(atPath: staged.folder.appending(path: staged.manifest.entry ?? "").path) {
            output += try await build(staged.folder, exec: exec) ?? ""
        }
        guard let name = staged.source.folder else { throw HerdrError.failed("A local path is not installed") }
        let target = plugins.appending(path: name)
        try place(staged.folder, at: target, keeping: staged.staging)
        return (target, output)
    }

    public static func place(_ folder: URL, at target: URL, keeping staging: URL) throws {
        let files = FileManager.default, old = staging.appending(path: "old"),
            had = files.fileExists(atPath: target.path)
        if had {
            try files.moveItem(at: target, to: old)
        }
        do {
            try files.moveItem(at: folder, to: target)
        } catch {
            if had {
                try? files.moveItem(at: old, to: target)
            }
            throw error
        }
    }

    public static func staging(in plugins: URL) -> URL {
        plugins.appending(path: stagingPrefix + UUID().uuidString)
    }

    public static let stagingPrefix = ".install-"

    public static func discard(_ staged: Staged) {
        try? FileManager.default.removeItem(at: staged.staging)
    }

    public struct NoManager: LocalizedError {
        public var errorDescription: String? {
            "Ovvi installs and builds plugins with npm, pnpm or bun, and none is on your PATH. Install Node.js from "
                + "nodejs.org, then try again."
        }
    }

    /// No install scripts run, and no peer dependencies install: `@ovvi/plugin-api` is the app's.
    static func dependencies(_ folder: URL, exec: any Exec) async throws -> String {
        let json = package(folder)
        guard ["dependencies", "devDependencies"].contains(where: { !((json[$0] as? [String: Any]) ?? [:]).isEmpty })
        else { return "" }
        let (found, frozen) = try await manager(folder, exec: exec)
        let argv: [String] = switch found {
        case "npm": ["npm", frozen ? "ci" : "install", "--no-audit", "--no-fund", "--ignore-scripts",
                     "--legacy-peer-deps"]
        case "pnpm": ["pnpm", "install", frozen ? "--frozen-lockfile" : "--no-frozen-lockfile", "--ignore-scripts",
                      "--config.auto-install-peers=false"]
        default: ["bun", "install", "--ignore-scripts", "--omit=peer"] + (frozen ? ["--frozen-lockfile"] : [])
        }
        return try await run(argv, in: folder, exec: exec)
    }

    public static func prepare(_ folder: URL, exec: any Exec) async throws -> String {
        try await dependencies(folder, exec: exec) + (build(folder, exec: exec) ?? "")
    }

    public static func build(_ folder: URL, exec: any Exec) async throws -> String? {
        guard builds(folder) else { return nil }
        // `--silent`: the script's own lines, not the manager's banner, head an error.
        return try await run([manager(folder, exec: exec).name, "run", "--silent", "build"], in: folder, exec: exec)
    }

    /// The file `ovvi-plugin://<id>/<name>` serves from `folder`, nil when it would leave it: a name with a folder or
    /// a hidden one, or a symlink (`git clone` keeps them) out of `folder`, or a `folder` that resolves out of `root`
    /// (its package). Else a file's HTML that a page shows could read any file of the user's with `fetch`.
    public static func served(_ name: String, in folder: URL, within root: URL) -> URL? {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        let real = folder.resolvingSymlinksInPath(), top = root.resolvingSymlinksInPath().path
        let file = real.appending(path: name).resolvingSymlinksInPath()
        guard file.deletingLastPathComponent().path == real.path, real.path == top || real.path.hasPrefix(top + "/")
        else { return nil }
        return file
    }

    public static func builds(_ folder: URL) -> Bool {
        (package(folder)["scripts"] as? [String: Any])?["build"] is String
    }

    static func manager(_ folder: URL, exec: any Exec) async throws -> (name: String, frozen: Bool) {
        let has = { (name: String) in FileManager.default.fileExists(atPath: folder.appending(path: name).path) }
        let locked = has("package-lock.json") ? "npm" : has("pnpm-lock.yaml") ? "pnpm"
            : has("bun.lock") || has("bun.lockb") ? "bun" : nil
        for manager in [locked].compactMap(\.self) + ["npm", "pnpm", "bun"]
            where await exec.succeeds("command -v \"$1\"", [manager])
        {
            return (manager, manager == locked)
        }
        throw NoManager()
    }

    static func run(_ argv: [String], in folder: URL, exec: any Exec) async throws -> String {
        let channel = try await exec.run(["sh", "-c", #"cd "$1" && shift && exec "$@" 2>&1"#, "sh", folder.path] + argv)
        channel.closeInput()
        let lines: [String]
        do {
            lines = try await withTimeout(.seconds(600), onTimeout: channel.terminate) {
                await channel.lines.reduce(into: []) { $0.append($1) }
            }
        } catch HerdrError.timeout {
            throw HerdrError.failed("\(argv.joined(separator: " ")) took over 10 minutes")
        }
        guard await channel.exit().status == 0 else {
            let tail = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(20)
            throw HerdrError
                .failed(tail.isEmpty ? "\(argv.joined(separator: " ")) failed" : tail.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func package(_ folder: URL) -> [String: Any] {
        (try? read(folder.appending(path: "package.json"))) ?? [:]
    }

    // MARK: settings.json

    public static func sources(_ settings: URL, key: String = "packages") -> [String] {
        ((try? read(settings))?[key] as? [Any] ?? []).compactMap {
            $0 as? String ?? ($0 as? [String: Any])?["source"] as? String
        }
    }

    public static func list(_ source: String, in settings: URL, add: Bool, key: String = "packages") throws {
        var json = try read(settings)
        var packages = (json[key] as? [Any] ?? []).filter {
            ($0 as? String ?? ($0 as? [String: Any])?["source"] as? String) != source
        }
        if add {
            packages.append(source)
        }
        json[key] = packages
        try write(json, to: settings)
    }

    public static func values(of id: String, in settings: URL) -> [String: Any] {
        ((try? read(settings))?["plugins"] as? [String: Any])?[id] as? [String: Any] ?? [:]
    }

    public static func store(_ value: Any?, _ setting: String?, of id: String, in settings: URL) throws {
        var json = try read(settings), plugins = json["plugins"] as? [String: Any] ?? [:]
        var values = setting == nil ? [:] : plugins[id] as? [String: Any] ?? [:]
        if let setting {
            values[setting] = value
        }
        plugins[id] = values.isEmpty ? nil : values
        json["plugins"] = plugins.isEmpty ? nil : plugins
        try write(json, to: settings)
    }

    private static func write(_ json: [String: Any], to settings: URL) throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys,
                                                                   .withoutEscapingSlashes])
            .write(to: settings, options: .atomic)
    }

    /// A file there that is no JSON object throws, so a write never replaces a hand edit with a typo in it.
    private static func read(_ settings: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settings) else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HerdrError.failed("\(settings.lastPathComponent) is not a JSON object")
        }
        return json
    }
}
