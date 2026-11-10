import Foundation
import HerdrKit

@MainActor
enum KnownSessions {
    private static let file = URL.cachesDirectory.appending(path: Bundle.main.bundleIdentifier ?? "ovvi")
        .appending(path: "sessions.json")
    private static let persists = !MachineList.isolated
    private(set) static var all: [String: [Session]] = persists ? load() : [:]

    static func of(_ machine: Machine) -> [Session]? {
        all[key(machine)]
    }

    /// Not for a machine removed meanwhile: its open windows still read it.
    static func keep(_ sessions: [Session], of machine: Machine) {
        guard !machine.isRemote || MachineList.shared.list.contains(where: { $0.target == machine.target })
        else { return }
        set(sessions, key(machine))
    }

    /// A machine removed, or one that needs a password again: its listed rows would show, then flip.
    /// ponytail: a password host's rows are forgotten only when a read finds it needs one, so the launch after a
    /// connect shows them once ahead of Connect; forget them at quit when masters say whether they needed an answer.
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
