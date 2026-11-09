import Foundation
import HerdrKit

/// Each machine's sessions as last listed, so the new-window view shows them at once and reads again behind them
/// (ui/window#new-window). Kept in a file under the caches; a run against a throwaway session keeps them in memory
/// only.
@MainActor
enum KnownSessions {
    private static let file = URL.cachesDirectory.appending(path: "ovvi/sessions.json")
    private static let persists = !ProcessInfo.processInfo.arguments
        .contains { ["-session", "-defaultSession"].contains($0) }
    private(set) static var all: [String: [Session]] = persists ? load() : [:]

    static func keep(_ sessions: [Session], of machine: Machine) {
        guard all[machine.id] != sessions else { return }
        all[machine.id] = sessions
        guard persists else { return }
        let json = all.mapValues { $0.map { ["name": $0.name, "running": $0.running] } }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try? JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
    }

    private static func load() -> [String: [Session]] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: [Session]].self, from: $0) } ?? [:]
    }
}
