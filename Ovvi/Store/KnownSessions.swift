import Foundation
import HerdrKit

/// Each machine's sessions as last listed, so the new-window view shows them at once and reads again behind them
/// (ui/window#new-window). By SSH target (This Mac by its id), in a file under the app's own caches; an isolated run
/// (`-session`, `-machines`) keeps them in memory only.
@MainActor
enum KnownSessions {
    private static let file = URL.cachesDirectory.appending(path: Bundle.main.bundleIdentifier ?? "ovvi")
        .appending(path: "sessions.json")
    private static let persists = !MachineList.isolated
    private(set) static var all: [String: [Session]] = persists ? load() : [:]

    static func of(_ machine: Machine) -> [Session]? {
        all[key(machine)]
    }

    static func keep(_ sessions: [Session], of machine: Machine) {
        set(sessions, key(machine))
    }

    /// A machine removed, or one that needs a password again: its old rows would show, then flip.
    static func forget(_ machine: Machine) {
        set(nil, key(machine))
    }

    private static func key(_ machine: Machine) -> String {
        machine.isRemote ? machine.target : machine.id
    }

    private static func set(_ sessions: [Session]?, _ key: String) {
        guard all[key] != sessions else { return }
        all[key] = sessions
        guard persists, let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try? data.write(to: file, options: .atomic)
    }

    private static func load() -> [String: [Session]] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: [Session]].self, from: $0) } ?? [:]
    }
}
