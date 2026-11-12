import Foundation
import Synchronization

public protocol Exec: Sendable {
    func run(_ argv: [String]) async throws -> Channel
    func herdr() async throws -> String?
    func forgetHerdr() async
    func read(home path: String) async -> String?
    var isRemote: Bool { get }
}

public extension Exec {
    var isRemote: Bool {
        false
    }

    func forgetHerdr() async {}

    func read(home path: String) async -> String? {
        let text = try? await output(["sh", "-c", #"cat "$HOME/$1" 2>/dev/null"#, "sh", path], timeout: .seconds(5))
        return text?.isEmpty == false ? text : nil
    }

    /// Each writer goes through its own temporary file; last writer wins. Only the user can read it.
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

    /// ponytail: the whole file is queued on the machine's one relay at once, ahead of its panes' streams and keys, so
    /// files over 16 MB (herdr's limit for a dropped image) are refused; stream it with backpressure if bigger files
    /// are needed.
    public func upload(_ file: URL) async throws -> String {
        let name = file.lastPathComponent
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw HerdrError.failed("\(name) is not a file") }
        guard values.fileSize ?? 0 <= 16 << 20 else { throw HerdrError.failed("\(name) is over 16 MB") }
        // ponytail: ten minutes for 16 MB; a progress bar when slow links need longer.
        let folder = try await checkedOutput(["sh", "-c", Self.uploadScript, "sh", name],
                                             input: base64Lines(Data(contentsOf: file)), timeout: .seconds(600))
        guard folder.hasPrefix("/") else { throw HerdrError.failed("Copying \(name) failed") }
        return folder + "/" + name
    }

    /// Prints only the new folder, whose name holds no line break (a file's may): the path is put together here. The
    /// shared folder must be the user's own, not a link another user made.
    static var uploadScript: String {
        #"""
        umask 077; r=${TMPDIR:-/tmp}; r=${r%/}/ovvi-drops-$(id -u)
        mkdir -p "$r" && [ ! -h "$r" ] && [ -O "$r" ] && chmod 700 "$r" || exit 1
        find "$r" -mindepth 1 -maxdepth 1 -mtime +0 -exec rm -rf {} + 2>/dev/null
        d=$(mktemp -d "$r/XXXXXXXX") && base64 -d >"$d/$1" && echo "$d"
        """#
    }
}

public struct Channel: Sendable {
    public let lines: AsyncStream<String>
    /// One line, no line break in it: over a remote machine's relay the rest would be read as a relay command.
    public let write: @Sendable (String) -> Void
    /// Every long-running command the app starts exits when its stdin closes (talking-to-herdr, Running commands).
    public let closeInput: @Sendable () -> Void
    public let terminate: @Sendable () -> Void
    public let exit: @Sendable () async -> (status: Int32, stderr: String)
}

public final class ProcessExec: Exec {
    let environment: [String: String]
    private let lookup: Mutex<Lookup>
    /// The login shell's bound: it runs the user's rc files. Tests on a starved Mac pass a longer one.
    private let shellLimit: Duration
    static let shellLimit = Duration.seconds(3)
    private struct Lookup {
        var path: String?
        var asked: ContinuousClock.Instant
    }

    public convenience init() async {
        Self.prepare()
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
        let (found, herdr) = await Self.loginShell(env)
        env.merge(found.filter { Self.isUserKey($0.key) }) { $1 }
        self.init(env, herdr: herdr, asked: .now)
    }

    static func prepare() {
        // A write to a child that already exited must fail, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        // A GUI app's soft limit is 256 fds; the first snapshot asks every pane at once, three pipes per run.
        var files = rlimit()
        if getrlimit(RLIMIT_NOFILE, &files) == 0, files.rlim_cur < rlim_t(OPEN_MAX) {
            files.rlim_cur = min(files.rlim_max, rlim_t(OPEN_MAX))
            setrlimit(RLIMIT_NOFILE, &files)
        }
    }

    init(_ environment: [String: String], herdr: String?, asked: ContinuousClock.Instant,
         shellLimit: Duration = shellLimit)
    {
        self.environment = environment
        self.shellLimit = shellLimit
        lookup = Mutex(Lookup(path: herdr, asked: asked))
    }

    public func run(_ argv: [String]) async throws -> Channel {
        try Self.spawn(argv, environment)
    }

    /// Read here, not by `cat`: on a busy Mac a process takes as long to start as a plugin's page takes to load, and
    /// the page waits for its state file.
    public func read(home path: String) async -> String? {
        let file = URL(filePath: environment["HOME"] ?? NSHomeDirectory()).appending(path: path)
        let text = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    public func forgetHerdr() async {
        lookup.withLock { $0 = Lookup(path: nil, asked: .now - .seconds(60)) }
    }

    public func herdr() async -> String? {
        if let path = lookup.withLock({ $0.path }), FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Missing or gone since: ask again at most every 30 s (it runs the user's rc files); nil in between.
        // `asked` is set as the run starts, and the shell's bound (under 30 s) keeps the run inside the window, so
        // one runs at a time.
        let ask = lookup.withLock {
            guard ContinuousClock.now - $0.asked >= .seconds(30) else { return false }
            $0.asked = .now
            return true
        }
        guard ask else { return nil }
        return await lookUp(within: shellLimit)
    }

    /// herdr's path from a login shell that answered, for what must not change once shown (the welcome's pages): a
    /// nil from `herdr()` may be a shell that ran out of its 3 s on a busy Mac, kept for 30 s. This bound is only for a
    /// hung rc file.
    public func answeredHerdr(within limit: Duration = .seconds(30)) async -> String? {
        if let path = await herdr() {
            return path
        }
        return await lookUp(within: limit)
    }

    private func lookUp(within limit: Duration) async -> String? {
        let path = await Self.loginShell(environment, within: limit).herdr
        // An ask that ended late never drops a path found meanwhile (an install's ask); a stale one is checked above.
        lookup.withLock { $0 = Lookup(path: path ?? $0.path, asked: .now) }
        return path
    }

    /// A GUI app does not get the shell's environment, so ask the login shell, in one run, for its
    /// variables and for herdr.
    static func loginShell(_ env: [String: String], within limit: Duration = shellLimit) async
        -> (vars: [String: String], herdr: String?)
    {
        let marker = "ovvi-env-\(UUID().uuidString)"
        guard let channel = try? spawn(
            [env["SHELL"] ?? "/bin/zsh", "-lic",
             "echo \(marker); /usr/bin/env; echo \(marker); \(Self.herdrLookup); echo \(marker)"],
            env,
        ) else { return ([:], nil) }
        // Closed stdin reads like /dev/null.
        channel.closeInput()
        return await (try? withTimeout(limit, onTimeout: channel.terminate) {
            var vars: [String: String] = [:]
            var herdr: String?
            var seen = 0
            // Stop at the last marker: a process the shell started may keep stdout open.
            for await line in channel.lines {
                if line.hasSuffix(marker) { // an rc file may print without a final newline
                    seen += 1
                    if seen == 3 {
                        break
                    }
                } else if seen == 1, let equals = line.firstIndex(of: "=") {
                    vars[String(line[..<equals])] = String(line[line.index(after: equals)...])
                } else if seen == 2 {
                    // The last line: a hook may print first. An alias or function is not a path.
                    herdr = line.hasPrefix("/") ? line : nil
                }
            }
            return (vars, herdr)
        }) ?? ([:], nil)
    }

    /// herdr's path in a login shell: on its PATH, else where herdr's installer puts it (`$HOME/.local/bin`), which a
    /// shell's PATH may not have (macOS's zsh has not).
    static let herdrLookup = #"command -v herdr || command -v "$HOME/.local/bin/herdr""#

    /// The rest of the app's environment (`__CFBundleIdentifier`, `XPC_*`, `DYLD_*`) must not reach a pane.
    static func isUserKey(_ key: String) -> Bool {
        ["PATH", "HOME", "SSH_AUTH_SOCK"].contains(key) || key.hasPrefix("XDG_")
    }

    /// A pipe's output until EOF. Not `FileHandle.bytes`: with several pipes open at once it
    /// stalls (seen on macOS 27 with a second bridge run while the events stream is open).
    private static func chunks(_ handle: FileHandle) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        // The handler holds the handle until EOF or until the reader stops: once a fast child's Process
        // and Pipe are released, nothing else does, and EOF never arrived (seen on CI as a 10 s timeout
        // after `sh -c` exited).
        handle.readabilityHandler = { _ in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        continuation.onTermination = { _ in handle.readabilityHandler = nil }
        return stream
    }

    private static func split(_ handle: FileHandle,
                              into lines: AsyncStream<String>.Continuation) -> Task<Void, Never>
    {
        let output = chunks(handle)
        return Task {
            var buffer = LineBuffer()
            for await data in output {
                for line in buffer.take(data) {
                    lines.yield(line)
                }
            }
            if let rest = buffer.rest {
                lines.yield(rest)
            }
            lines.finish()
        }
    }

    /// The end of a pipe's output as text. Only the tail: long-lived streams may log for hours.
    private static func tail(_ handle: FileHandle) -> Task<String, Never> {
        let output = chunks(handle)
        return Task {
            var data = Data()
            for await chunk in output {
                data = (data + chunk).suffix(8192)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func spawn(_ argv: [String], _ environment: [String: String]) throws -> Channel {
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = argv
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let (ended, endedContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = {
            endedContinuation.yield($0.terminationStatus)
            endedContinuation.finish()
        }
        try process.run()
        let pid = process.processIdentifier

        let (lines, linesContinuation) = AsyncStream<String>.makeStream()
        let reader = split(stdout.fileHandleForReading, into: linesContinuation)
        let errors = tail(stderr.fileHandleForReading)
        // Running until reaped: after that, its pid may belong to another process.
        let kill: @Sendable () -> Void = {
            if process.isRunning {
                Darwin.kill(pid, SIGKILL)
            }
        }
        // Ends the stream too, so a reader never waits on a child that ignores the signal, and stops
        // both pipe readers, so a grandchild that keeps a pipe open cannot keep them alive.
        let terminate: @Sendable () -> Void = {
            kill()
            linesContinuation.finish()
            reader.cancel()
            errors.cancel()
        }
        // A dropped stream terminates; one that ended at EOF leaves stderr to finish for `exit`. Not on the dropping
        // thread: a cancel runs this where it is called (the main actor, when a chat card leaves view), and the kill
        // and the pipes' handlers took up to 0.8 s there on a loaded Mac.
        linesContinuation.onTermination = { reason in
            DispatchQueue.global().async {
                if case .cancelled = reason {
                    terminate()
                } else {
                    kill()
                }
            }
        }
        let status = Task { await ended.first { _ in true } ?? -1 }
        let input = stdin.fileHandleForWriting
        // A full pipe blocks this queue, never the caller (keystrokes come from the main actor).
        let writes = DispatchQueue(label: "ovvi.exec.stdin")
        return Channel(
            lines: lines,
            write: { line in writes.async { try? input.write(contentsOf: Data((line + "\n").utf8)) } },
            closeInput: { writes.async { try? input.close() } },
            terminate: terminate,
            exit: { await (status.value, errors.value) },
        )
    }
}

struct LineBuffer {
    private var data = Data()
    private(set) var scanned = 0

    /// Only the chunk's bytes are scanned: a scan from the start per chunk costs O(n²) on a 280 KB snapshot line.
    mutating func take(_ chunk: Data) -> [String] {
        var from = data.endIndex, lines: [String] = []
        data.append(chunk)
        while true {
            let newline = data[from...].firstIndex(of: UInt8(ascii: "\n"))
            scanned += data.distance(from: from, to: newline.map { data.index(after: $0) } ?? data.endIndex)
            guard let newline else { break }
            lines.append(String(decoding: data[..<newline], as: UTF8.self))
            data.removeSubrange(...newline)
            from = data.startIndex
        }
        return lines
    }

    var rest: String? {
        data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }
}
