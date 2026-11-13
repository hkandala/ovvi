import CryptoKit
import Foundation

/// A run starts the master when none lives, never with a prompt; only `connect(ask:)` may ask.
public actor SSHExec: Exec {
    public typealias Ask = @Sendable (String) async -> String?

    nonisolated let target: String
    nonisolated let environment: [String: String]
    nonisolated let socket: String
    /// The master's own options ahead of the user's config: the tests' sshd takes a config of its own.
    nonisolated let options: [String]
    /// A check costs a `kill(pid, 0)`, not a process. A reused pid reads as a live master until its relay is needed
    /// again and does not start.
    var connection: pid_t?
    private var starting: Task<Void, Error>?
    private var blocked: HerdrError?
    private var retry: (at: ContinuousClock.Instant, error: Error)?
    private var failures = 0
    private var lookup: (task: Task<String?, Error>, at: ContinuousClock.Instant)?
    private var relay: Relay?
    private var relayStart: Task<Relay?, Never>?
    var proxy: (front: SOCKSFront, users: Int)?
    /// A new master forwards the port again.
    var dynamic: (port: UInt16, pid: pid_t)?
    var forwarding: Task<UInt16, Error>?
    var ending: Task<Void, Never>?
    /// By session: the local socket ssh forwards to herdr's on the machine, on the master with `pid`.
    var herdrForwards: [String: Forward] = [:]
    var herdrForwarding: [String: Task<String, Error>] = [:]

    public init(target: String, local: ProcessExec, options: [String] = []) {
        self.target = target
        self.options = options
        environment = local.environment
        let hash = SHA256.hash(data: Data(target.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        // Per app: another Ovvi (a test's, a second build) unlinks a socket at start and ends its master at quit; it
        // must never touch this app's, or `ssh -O` (the browser proxy's forward) finds no master.
        socket = Self.folder + "/" + hash + "-\(getpid())"
    }

    public nonisolated var isRemote: Bool {
        true
    }

    /// A target the user may add: ssh would read a leading `-` as an option, and argv takes no spaces.
    public static func isValidTarget(_ target: String) -> Bool {
        !target.isEmpty && !target.hasPrefix("-") && !target.contains(where: \.isWhitespace)
    }

    public func run(_ argv: [String]) async throws -> Channel {
        try await up(nil)
        // `exec`: the run's pid is the command's own on every `sh`, so a kill reaches it.
        return try await currentRelay().run("exec " + shellQuoted(argv))
    }

    private func currentRelay() async throws -> Relay {
        if let relay, relay.alive {
            return relay
        }
        // Runs during a start wait for it, and fail with it: a slow or Perl-less host gets one session, not one per
        // run.
        if let relayStart {
            guard let started = await relayStart.value else { throw Self.noRelay(target) }
            return started
        }
        let task = Task { () -> Relay? in
            guard let channel = try? session(["perl", "-e", Relay.script]) else { return nil }
            return await Relay.start(channel)
        }
        relayStart = task
        let started = await task.value
        if relayStart == task {
            relayStart = nil
        }
        relay = started
        guard let started else {
            // A master gone with its pid reused, or with its socket deleted, serves no session: the next run
            // starts a new one.
            if await pid() != connection {
                connection = nil
                throw HerdrError.failed("The SSH connection to \(target) closed")
            }
            throw Self.noRelay(target)
        }
        return started
    }

    private static func noRelay(_ target: String) -> HerdrError {
        .failed("Ovvi needs Perl on \(target): its relay did not start")
    }

    /// Without a master it fails at once instead of opening its own connection and prompting again, and it sends none
    /// of the user's configured forwards.
    private func session(_ argv: [String]) throws -> Channel {
        try ProcessExec.spawn(["/usr/bin/ssh", "-F", "/dev/null", "-o", "ControlMaster=no", "-o", "BatchMode=yes",
                               "-o", "ProxyCommand=/usr/bin/false", "-S", socket, "--", target,
                               shellEnvelope(argv)], environment)
    }

    public func herdr() async throws -> String? {
        try await up(nil)
        // A run that failed is no answer: it is asked again at once.
        do {
            if let lookup {
                let path = try await lookup.task.value
                if path != nil || ContinuousClock.now - lookup.at < .seconds(30) {
                    return path
                }
            }
            let task = Task { try await findHerdr() }
            lookup = (task, .now)
            return try await task.value
        } catch {
            lookup = nil
            throw error
        }
    }

    public func forgetHerdr() async {
        lookup = nil
    }

    public func connect(ask: @escaping Ask) async throws {
        try await up(ask)
    }

    /// Ends the master (the app quits); a run after it starts a new one. No wait: a stopped (SIGSTOP) master never
    /// answers, and the quit must not hang on it; the `ssh -O exit` outlives the app.
    public nonisolated func disconnect() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ssh")
        process.arguments = ["-F", "/dev/null", "-S", socket, "-O", "exit", "--", target]
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // ssh leaves its forwards' socket files.
        let prefix = (socket as NSString).lastPathComponent + "-"
        for name in (try? FileManager.default.contentsOfDirectory(atPath: Self.folder)) ?? []
            where name.hasPrefix(prefix)
        {
            unlink(Self.folder + "/" + name)
        }
    }

    func up(_ ask: Ask?) async throws {
        while let starting {
            _ = try? await starting.value
        }
        if let connection, kill(connection, 0) == 0 {
            return
        }
        if ask == nil {
            if let blocked {
                throw blocked
            }
            if let retry, ContinuousClock.now < retry.at {
                throw retry.error
            }
        }
        let task = Task {
            defer { starting = nil }
            try await start(ask)
        }
        starting = task
        try await task.value
    }

    /// Starts the master and waits until it serves (`-f`: ssh goes to the background once authenticated). Without
    /// `ask`, BatchMode: a host that needs an answer fails at once and blocks.
    private func start(_ ask: Ask?) async throws {
        connection = nil
        // A master killed hard leaves its socket, and a new one does not bind over it. One that outlived an app
        // that crashed has that app's pid in its socket, so it is never used: it may still hold that app's sessions
        // (sshd allows 10); it ends by itself 10 min after its last one.
        unlink(socket)
        // Forwarding off: a machine cannot reach the Mac's agent or ports through the long-lived connection.
        // ssh's keepalive ends a dead link's master within 15 s; the next run starts a new one. LogLevel=ERROR:
        // a failure shows ssh's own error, not the server's login banner or ssh's notices (both INFO).
        var argv = ["sh", "-c", #"exec "$@" 2>&1"#, "sh", "/usr/bin/ssh", "-M", "-N", "-f",
                    "-o", "ControlPersist=10m", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3",
                    "-o", "ConnectTimeout=10", "-o", "ForwardAgent=no", "-o", "ForwardX11=no",
                    "-o", "ClearAllForwardings=yes", "-o", "StreamLocalBindMask=0177", "-o", "LogLevel=ERROR"]
        var environment = environment
        if ask == nil {
            argv += ["-o", "BatchMode=yes"]
        } else {
            // ssh runs the helper with its own stdin and stderr: the question comes out on our pipe, the answer
            // goes in through ssh's stdin. Never stored.
            environment["SSH_ASKPASS"] = Self.askpass
            environment["SSH_ASKPASS_REQUIRE"] = "force"
        }
        let channel = try ProcessExec.spawn(argv + options + ["-S", socket, "--", target], environment)
        // ConnectTimeout covers only the TCP connect and the banner: a login that hangs (a jump host, a security
        // key under BatchMode) must not hold every run. One that asks has no limit: the user answers.
        let began = ContinuousClock.now
        let limit = ask == nil ? Task {
            try await Task.sleep(for: .seconds(30))
            channel.terminate()
        } : nil
        defer { limit?.cancel() }
        var said: [String] = []
        for await line in channel.lines.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            if line.hasPrefix(Self.question), let ask {
                let prompt = Data(base64Encoded: String(line.dropFirst(Self.question.count)))
                    .map { String(decoding: $0, as: UTF8.self) } ?? ""
                guard let answer = await ask(prompt) else {
                    channel.closeInput()
                    channel.terminate()
                    let error = HerdrError.disconnected("Canceled")
                    blocked = error
                    throw error
                }
                // One line: the rest of a multi-line paste would answer ssh's next question.
                channel.write(String(answer.prefix { !$0.isNewline }))
            } else if !line.isEmpty {
                said.append(line)
            }
        }
        channel.closeInput()
        let (status, _) = await channel.exit()
        guard status == 0 else {
            throw failed(status, ContinuousClock.now - began >= .seconds(30) ? "ssh did not connect within 30 s"
                : said.joined(separator: "\n"))
        }
        connection = await pid()
        guard connection != nil else { throw failed(0, "The SSH connection did not start") }
        started()
    }

    private func started() {
        blocked = nil
        retry = nil
        failures = 0
        lookup = nil
        relay = nil
    }

    private func failed(_ status: Int32, _ text: String) -> HerdrError {
        let needsAnswer = ["Permission denied", "Host key verification failed", "passphrase",
                           "IDENTIFICATION HAS CHANGED"].contains { text.contains($0) }
        if needsAnswer {
            blocked = .disconnected(text)
            return .disconnected(text)
        }
        failures += 1
        // LogLevel=ERROR also hides ssh's "Connection closed by …" (INFO): no text says only that.
        let error = HerdrError
            .failed(text.isEmpty ? "The connection to \(target) closed (ssh exited \(status))" : text)
        retry = (.now + .seconds(min(1 << min(failures, 5), 30)), error)
        return error
    }

    func pid() async -> pid_t? {
        await control(["-O", "check"])?.stderr.split(separator: "pid=").last
            .flatMap { pid_t($0.prefix { $0.isNumber }) }
    }

    /// Nil when the master did not answer within `limit`: a master stopped with SIGSTOP never does.
    func control(_ command: [String], within limit: Duration = .seconds(5)) async
        -> (status: Int32, stderr: String)?
    {
        guard let channel = try? ProcessExec.spawn(["/usr/bin/ssh", "-F", "/dev/null", "-S", socket] + command
            + ["--", target], environment)
        else { return nil }
        channel.closeInput()
        return try? await withTimeout(limit, onTimeout: channel.terminate) { await channel.exit() }
    }

    /// The last absolute path after our marker: an rc file may print first.
    private func findHerdr() async throws -> String? {
        let marker = "ovvi-herdr"
        let shell = #"exec "${SHELL:-sh}" -lic "$0" </dev/null 2>/dev/null"#
        let text = try await output(["sh", "-c", shell, "echo \(marker); \(ProcessExec.herdrLookup)"])
        let path = text.components(separatedBy: marker).last?
            .split(separator: "\n").last.map(String.init) ?? ""
        return path.hasPrefix("/") ? path : nil
    }
}
