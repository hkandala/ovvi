import Foundation
import os

/// onTimeout must make body end.
func withTimeout<T: Sendable>(
    _ duration: Duration,
    onTimeout: @escaping @Sendable () -> Void,
    _ body: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: body)
        group.addTask {
            try await Task.sleep(for: duration)
            throw HerdrError.timeout
        }
        defer { group.cancelAll() }
        do {
            guard let value = try await group.next() else { throw HerdrError.timeout }
            return value
        } catch {
            onTimeout()
            throw error
        }
    }
}

/// Whole groups of 3 bytes, so no padding inside the stream.
func base64Lines(_ data: Data) -> [String] {
    stride(from: 0, to: data.count, by: 49152).map { data[$0 ..< min($0 + 49152, data.count)].base64EncodedString() }
}

/// observe ignores stdin's end, so this wrapper ends it then. The watcher lets go of stdout and stderr, so a run
/// that exits by itself (a failed handshake) ends the stream with its status and reason; fd 3 because a background
/// job's stdin is /dev/null. The watcher kills until the run is gone: macOS's sh (bash 3.2) can lose one TERM, in
/// `wait` or in an `exec` while a trap is pending, and the chat's `tail -F` then runs forever. Once the run ends
/// the watcher goes too, so it never kills a reused pid.
/// ponytail: an observe wrapper killed by SIGKILL (the relay's `k`, the 1 s fallback) leaves its watcher, which may
/// signal a pid reused within the second after the run ended; a pidfd where the shell has one.
let observeWrapper = #"exec 3<&0; "$@" & c=$!; { cat <&3 >/dev/null; while kill $c; do sleep 1; done; }"#
    + #" >/dev/null 2>&1 & w=$!; "#
    + "wait $c 2>/dev/null; s=$?; kill $w 2>/dev/null; exit $s"

public extension Logger {
    init(ovvi category: String) {
        self.init(subsystem: Bundle.main.bundleIdentifier ?? "dev.ovvi.app", category: category)
    }
}

/// The machine's login shell may be bash, zsh or fish, so it gets only base64, which every shell passes through.
public func shellEnvelope(_ argv: [String]) -> String {
    #"sh -c 'eval "$(printf %s "$1" | base64 -d)"' sh "# + Data(shellQuoted(argv).utf8).base64EncodedString()
}

func shellQuoted(_ argv: [String]) -> String {
    argv.map(\.shellQuoted).joined(separator: " ")
}

public extension String {
    /// In single quotes for `sh`, with its own single quotes kept. By code unit: as a Character, a `'` with a
    /// combining mark after it is no `'`, and `sh` would end the quote there.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: #"'\''"#, options: .literal) + "'"
    }
}
