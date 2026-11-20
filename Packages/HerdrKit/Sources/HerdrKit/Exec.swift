import Foundation

public protocol Exec: Sendable {
    func run(_ argv: [String]) async throws -> Channel
    func herdr() async throws -> String?
    func forgetHerdr() async
    func read(home path: String) async -> String?
    /// Each writer goes through its own temporary file, then a rename; last writer wins. Only the user can read it.
    func write(home path: String, _ line: String) async
    func remove(home path: String) async
    /// A connection to the session's herdr API socket: the socket itself on This Mac, a relay run joined to it on a
    /// remote machine. Every herdr request and the events stream go through one.
    func api(_ session: String) async throws -> Channel
    var isRemote: Bool { get }
}

public extension Exec {
    var isRemote: Bool {
        false
    }

    func forgetHerdr() async {}

    func read(home path: String) async -> String? {
        await read(home: path, timeout: .seconds(5))
    }

    /// Through the machine's shell.
    func read(home path: String, timeout: Duration) async -> String? {
        let text = try? await output(["sh", "-c", #"cat "$HOME/$1" 2>/dev/null"#, "sh", path], timeout: timeout)
        return text?.isEmpty == false ? text : nil
    }

    func write(home path: String, _ line: String) async {
        let script = #"umask 077; f="$HOME/$1"; mkdir -p "${f%/*}" && cat >"$f.$$" && mv "$f.$$" "$f""#
        await succeeds(script, [path], input: [line])
    }

    func remove(home path: String) async {
        _ = try? await output(["sh", "-c", #"rm -f "$HOME/$1""#, "sh", path])
    }

    func output(_ argv: [String], timeout: Duration = .seconds(10)) async throws -> String {
        let channel = try await run(argv)
        channel.closeInput()
        return try await withTimeout(timeout, onTimeout: channel.terminate) {
            await channel.lines.reduce(into: "") { $0 += $1 + "\n" }
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Exec {
    func checkedOutput(_ argv: [String], input: [String] = [],
                       timeout: Duration = .seconds(10)) async throws -> String
    {
        let channel = try await run(argv)
        input.forEach(channel.write)
        channel.closeInput()
        let output = try await withTimeout(timeout, onTimeout: channel.terminate) {
            await channel.lines.reduce(into: []) { $0.append($1) }.joined(separator: "\n")
        }
        let (status, stderr) = await channel.exit()
        guard status == 0 else {
            let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrError.failed(text.isEmpty ? "\(argv[0]) failed (\(status))" : text)
        }
        return output
    }

    @discardableResult
    public func succeeds(_ script: String, _ arguments: [String], input: [String] = []) async -> Bool {
        guard let channel = try? await run(["sh", "-c", script, "sh"] + arguments) else { return false }
        input.forEach(channel.write)
        channel.closeInput()
        return await channel.exit().status == 0
    }
}

public struct Channel: Sendable {
    public let lines: AsyncStream<String>
    /// One line, no line break in it: over a remote machine's relay the rest would be read as a relay command.
    public let write: @Sendable (String) -> Void
    /// Every long-running command the app starts exits when its stdin closes.
    public let closeInput: @Sendable () -> Void
    public let terminate: @Sendable () -> Void
    public let exit: @Sendable () async -> (status: Int32, stderr: String)
    /// A local process's own.
    var pid: pid_t?
}
