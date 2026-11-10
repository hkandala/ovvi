import AppKit
import HerdrKit
import Observation
import WebKit

@MainActor @Observable
final class Bridge {
    @ObservationIgnored private(set) weak var plugin: Plugin?
    private(set) var commands: [String: [String: Any]] = [:]
    var failure: PluginProblem?
    @ObservationIgnored private var state: Any?
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var watches: [Int: String] = [:]
    @ObservationIgnored private var watching: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private(set) var visible = false
    @ObservationIgnored private var written: Data?
    @ObservationIgnored var keyboard = false {
        didSet {
            if keyboard != oldValue {
                event("keyboard", keyboard)
            }
        }
    }

    @ObservationIgnored private var runs = 0
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Git takes `index.lock`: one write at a time.
    @ObservationIgnored private var writes: Task<Void, Never>?
    @ObservationIgnored var toast: Int?
    @ObservationIgnored var theme: [String: Any] = [:] {
        didSet {
            if loaded, (theme as NSDictionary) != (oldValue as NSDictionary) {
                event("theme", theme)
            }
        }
    }

    @ObservationIgnored private var loaded = false

    static let api = 3

    init(plugin: Plugin) {
        self.plugin = plugin
        plugin.header.send = { [weak self] in self?.event("control", $0) }
        plugin.header.changed = { [weak self] in self?.save() }
        plugin.web.view.keyboard = { [weak self] in self?.keyboard = $0 }
        if plugin.manifest.api > Self.api {
            plugin.web.ready = true
            failure = .noted(plugin.manifest, PluginProblem(
                title: "\(plugin.manifest.name.shown) needs a newer Ovvi",
                text: "It is written for version \(plugin.manifest.api) of "
                    + "the plugin API; this Ovvi has version \(Self.api).",
                button: nil,
            ))
        }
    }

    /// A closed card leaves `plugins` ahead of `showWeb`, so its watches end here.
    isolated deinit {
        watching.values.forEach { $0.cancel() }
    }

    func context() -> [String: Any] {
        guard let plugin, let store = plugin.web.store else { return [:] }
        let machine = store.machine
        var context: [String: Any] = [
            "api": plugin.manifest.api, "id": plugin.label.iid, "arg": plugin.web.arg,
            "plugin": ["id": plugin.manifest.id, "version": plugin.manifest.version],
            "machine": ["id": machine.id, "name": machine.name, "remote": machine.isRemote],
            "cwd": store.pane(plugin.paneID)?.cwd ?? "/", "visible": visible, "keyboard": keyboard,
            "controls": plugin.header.values, "theme": theme, "settings": PluginSettings.shared.values(plugin.manifest),
            "entry": plugin.manifest.entryName + ".js",
        ]
        context["at"] = plugin.web.place
        context["state"] = state
        return context
    }

    func start() async {
        loaded = true
        guard let plugin, let store = plugin.web.store, state == nil else { return }
        let text = await store.machine.exec().read(home: plugin.label.statePath(session: store.session))
        let file = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        if let controls = file?["controls"] as? [String: Any] {
            plugin.header.restore(controls)
        }
        state = file?["state"].flatMap { $0 is NSNull ? nil : $0 }
    }

    func event(_ name: String, _ data: Any) {
        plugin?.web.view.callAsyncJavaScript("window.ovvi_receive?.(name, data)", arguments: ["name": name,
                                                                                              "data": data],
                                             in: nil, in: .page)
    }

    func place(_ arg: String, at landing: String?) {
        var place: [String: Any] = ["arg": arg]
        place["at"] = landing
        event("place", place)
    }

    func shown(_ yes: Bool) {
        guard yes != visible else { return }
        visible = yes
        event("visible", yes)
        guard yes else {
            watching.values.forEach { $0.cancel() }
            watching = [:]
            return
        }
        for id in watches.keys {
            watch(id)
            event("watch", id)
        }
    }

    private func watch(_ id: Int) {
        guard visible, let path = watches[id], let store = plugin?.web.store else { return }
        watching[id]?.cancel()
        watching[id] = Task { [weak self] in
            for await _ in await Files.watch(path, exec: store.machine.exec()) {
                self?.event("watch", id)
            }
        }
    }

    /// False when the file, controls and state, is over 256 KiB or not JSON.
    @discardableResult private func save() -> Bool {
        guard let plugin, let store = plugin.web.store else { return true }
        var file: [String: Any] = ["controls": plugin.header.values]
        file["state"] = state
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: .sortedKeys),
              data.count <= 256 << 10
        else { return false }
        guard data != written else { return true }
        written = data
        store.saveState(&saving, path: plugin.label.statePath(session: store.session), data: data,
                        terminalID: plugin.terminalID)
        return true
    }

    func call(_ message: [String: Any]) async -> (Any?, String?) {
        let name = message["call"] as? String ?? "", args = message["args"] as? [String: Any] ?? [:]
        do {
            guard let plugin, failure == nil || name == "card.failed" else { throw PluginError("closed", "Closed") }
            // A page still running after Remove can do nothing more.
            guard PluginTrust.shared.allows(plugin.manifest) else { throw PluginError("closed", "Removed") }
            let reply = try await answer(name, args, plugin)
            guard let reply else { return (nil, nil) }
            if let data = reply as? Data {
                return (String(decoding: data, as: UTF8.self), nil)
            }
            let data = try JSONSerialization.data(withJSONObject: reply, options: [.fragmentsAllowed, .sortedKeys])
            return (String(decoding: data, as: UTF8.self), nil)
        } catch let error as PluginError {
            return (nil, "\(error.code): \(error.text)")
        } catch {
            return (nil, "failed: \(error.localizedDescription)")
        }
    }

    private func answer(_ name: String, _ args: [String: Any], _ plugin: Plugin) async throws -> Any? {
        switch name {
        case "run": return try await run(args)
        case "console": PluginLog.add(
                plugin.manifest.id,
                "\(args["level"] as? String ?? "log"): \(args["text"] as? String ?? "")",
            )
        case "files.info": return try await info(args)
        case "files.watch", "files.unwatch": try watch(name, args)
        case _ where PluginCalls.gitWrites.contains(name): return try await serial { try await self.calls(name, args) }
        case _ where name.hasPrefix("files.") || name.hasPrefix("git."): return try await calls(name, args)
        case _ where name.hasPrefix("card.") || name.hasPrefix("state.") || name.hasPrefix("controls."):
            try own(name, args, plugin)
        default: return try await card(name, args, plugin)
        }
        return nil
    }

    private func own(_ name: String, _ args: [String: Any], _ plugin: Plugin) throws {
        switch name {
        case "card.go":
            guard let arg = args["arg"] as? String else { throw PluginError("failed", "arg is missing") }
            plugin.go(arg, at: args["at"] as? String)
        case "card.step": plugin.web.view.step?(args["back"] as? Bool == true)
        case "card.ready":
            plugin.web.ready = true
            // A change between the context and the runtime's start has no one to hear it.
            event("visible", visible)
            event("keyboard", keyboard)
        case "card.setDirty": plugin.web.dirty = args["dirty"] as? Bool == true
        case "card.failed":
            failure = .noted(plugin.manifest, PluginProblem(
                title: "\(plugin.manifest.name.shown) stopped",
                text: [args["text"], args["stack"]].compactMap { $0 as? String }
                    .filter { !$0.isEmpty }.joined(separator: "\n"),
            ))
            plugin.web.ready = true
        case "state.set": try keep(args["value"] ?? NSNull())
        case "controls.set":
            let id = args["id"] as? String ?? "", change = args["change"] as? [String: Any] ?? [:]
            if plugin.manifest.commands.contains(where: { $0.id == id }) {
                commands[id, default: [:]].merge(change) { $1 }
            } else {
                plugin.header.set(id, change)
            }
        default: throw PluginError("failed", "No call \(name)")
        }
    }

    private func keep(_ value: Any) throws {
        let kept = state
        state = value is NSNull ? nil : value
        guard save() else {
            state = kept
            throw PluginError("tooLarge", "The state is over 256 KiB, or not JSON")
        }
    }

    private func watch(_ name: String, _ args: [String: Any]) throws {
        guard let id = args["id"] as? Int else { throw PluginError("failed", "id is missing") }
        guard name == "files.watch" else {
            watches[id] = nil
            watching.removeValue(forKey: id)?.cancel()
            return
        }
        guard let path = args["path"] as? String, path.hasPrefix("/") else {
            throw PluginError("failed", "path must be an absolute path")
        }
        watches[id] = path
        watch(id)
    }

    func calls(_ name: String, _ args: [String: Any]) async throws -> Data {
        guard let plugin, let store = plugin.web.store else { throw PluginError("closed", "Closed") }
        let data = try JSONSerialization.data(withJSONObject: args)
        let calls = await PluginCalls(exec: store.machine.exec(), gitRuns: name != "run" ? store.gitRuns() : false)
        return try await calls.call(name, data)
    }

    private func run(_ args: [String: Any]) async throws -> Data {
        while runs >= 2 {
            await withCheckedContinuation { waiting.append($0) }
        }
        runs += 1
        defer {
            runs -= 1
            if !waiting.isEmpty {
                waiting.removeFirst().resume()
            }
        }
        return try await calls("run", args)
    }

    private func serial(_ body: @escaping () async throws -> Data) async throws -> Data {
        let previous = writes
        let write = Task { () -> Result<Data, any Error> in
            await previous?.value
            do {
                return try await .success(body())
            } catch {
                return .failure(error)
            }
        }
        writes = Task { _ = await write.value }
        return try await write.value.get()
    }

    func reset() {
        watching.values.forEach { $0.cancel() }
        // The page that asked is gone.
        if toast != nil {
            plugin?.web.toast = nil
        }
        (watching, watches, commands, toast) = ([:], [:], [:], nil)
    }
}
