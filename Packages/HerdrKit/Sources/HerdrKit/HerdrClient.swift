import Foundation

let herdrVersion = "0.9.3"

public enum Update: Sendable {
    case snapshot(Snapshot)
    case error(HerdrError)
    case request(id: String, pane: String)
}

public actor HerdrClient {
    nonisolated let session: String
    nonisolated let exec: any Exec
    nonisolated let timeout: Duration
    nonisolated let wait: @Sendable (ContinuousClock.Instant) async -> Void

    private var out: AsyncStream<Update>.Continuation?
    private var lastRead: ContinuousClock.Instant?
    private var reading = false
    private var readAgain = false
    private var hurry = false
    private var pause: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var events: Task<Void, Never>?
    private var subscribed: [String]?
    private var asked: [String] = []

    public init(
        session: String,
        exec: any Exec,
        timeout: Duration = .seconds(10),
        wait: @escaping @Sendable (ContinuousClock.Instant) async -> Void = { try? await Task.sleep(until: $0) },
    ) {
        self.session = session
        self.exec = exec
        self.timeout = timeout
        self.wait = wait
    }

    // MARK: Requests

    nonisolated func call<Result: Decodable & Sendable>(
        _ method: String,
        _ params: [String: any Sendable] = [:],
    ) async throws -> Result {
        guard let line = jsonLine(["id": "1", "method": method, "params": params]) else {
            throw HerdrError.failed("\(method): params are not JSON")
        }
        let channel = try await exec.run([herdr(), "--session", session, "remote-api-bridge"])
        channel.write(line)
        let reply = try await withTimeout(timeout, onTimeout: channel.terminate) {
            await channel.lines.first { _ in true }
        }
        channel.closeInput()
        guard let reply else {
            let (status, stderr) = await channel.exit()
            throw HerdrError.failed("herdr exited \(status): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let decoded = try decode(Reply<Result>.self, reply)
        if let error = decoded.error {
            throw HerdrError.herdr(code: error.code, message: error.message)
        }
        guard let result = decoded.result else { throw HerdrError.failed("\(method): no result") }
        return result
    }

    public nonisolated func sessions() async throws -> [Session] {
        let list = try await exec.output([herdr(), "--session", session, "session", "list", "--json"])
        return try decode(SessionList.self, list).sessions
    }

    nonisolated func session(_ command: String) async throws {
        let channel = try await exec.run([herdr(), "--session", session, "session", command, session, "--json"])
        channel.closeInput()
        try await withTimeout(timeout, onTimeout: channel.terminate) {
            for await _ in channel.lines {}
        }
        let (status, stderr) = await channel.exit()
        guard status != 0 else { return }
        let error = try? JSONDecoder().decode(Reply<String>.self, from: Data(stderr.utf8)).error
        throw error.map { HerdrError.herdr(code: $0.code, message: $0.message) }
            ?? HerdrError.failed("herdr session \(command) exited \(status)")
    }

    public nonisolated func pane(_ paneID: String) async throws -> Pane {
        try await (call("pane.get", ["pane_id": paneID]) as PaneResult).pane
    }

    public nonisolated func program(_ paneID: String) async throws -> Program? {
        try await (call("pane.process_info", ["pane_id": paneID]) as ProcessInfoResult).processInfo.program
    }

    public nonisolated func snapshot() async throws -> Snapshot {
        var snapshot = try await (call("session.snapshot") as SnapshotResult).snapshot
        let numbers = { (version: String) in
            version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        if let version = snapshot.version, numbers(version).lexicographicallyPrecedes(numbers(herdrVersion)) {
            throw HerdrError.unsupported("herdr \(version) is too old; \(herdrVersion) or newer needed")
        }
        for layout in snapshot.layouts {
            if let tree = SplitNode(layout) {
                snapshot.trees[layout.tabID] = tree
            } else {
                let export: ExportResult = try await call("layout.export", ["tab_id": layout.tabID])
                snapshot.trees[layout.tabID] = export.layout.root
            }
        }
        return snapshot
    }

    // MARK: Updates

    public func updates() -> AsyncStream<Update> {
        precondition(out == nil, "updates() is called once per client")
        let (stream, out) = AsyncStream<Update>.makeStream()
        self.out = out
        out.onTermination = { _ in Task { await self.stop() } }
        heartbeat = Task { await self.beat() }
        return stream
    }

    public func refresh() {
        hurry = true
        pause?.cancel()
        read()
    }

    private func read() {
        guard out != nil else { return }
        if reading {
            readAgain = true
            return
        }
        reading = true
        Task { [self] in
            repeat {
                readAgain = false
                hurry = false
                let started = ContinuousClock.now
                do {
                    let snapshot = try await snapshot()
                    lastRead = .now
                    out?.yield(.snapshot(snapshot))
                    // A ring made while the stream reopens sends no event.
                    snapshot.panes.forEach { ask($0.tokens?[Tokens.request], $0.id) }
                    let agentPanes = snapshot.agents.map(\.paneID).sorted()
                    if out != nil, agentPanes != subscribed {
                        subscribe(agentPanes)
                    }
                } catch {
                    lastRead = nil
                    out?.yield(.error(error as? HerdrError ?? .failed("\(error)")))
                }
                // Events during the read: the next one starts `spacing` after this one did, so a hundred agents'
                // titles and states (an event each) are not reads back to back, each a 280 KB snapshot at 400 panes.
                if readAgain, !hurry {
                    let pause = Task { [wait] in await wait(started + Self.spacing) }
                    self.pause = pause
                    await pause.value
                }
            } while readAgain && out != nil
            reading = false
        }
    }

    static let spacing = Duration.milliseconds(250)

    private func stop() {
        out = nil
        heartbeat?.cancel()
        events?.cancel()
    }

    private func subscribe(_ agentPanes: [String]) {
        events?.cancel()
        subscribed = agentPanes
        // No workspace.metadata_updated: the app reads no workspace tokens, and herdr sends one on every token write,
        // also one that changes nothing (a mark's refresh), each a snapshot read.
        let types = [
            "workspace.created", "workspace.updated", "workspace.renamed", "workspace.moved", "workspace.reordered",
            "workspace.closed",
            "tab.created", "tab.closed", "tab.renamed", "tab.moved",
            "pane.created", "pane.closed", "pane.moved", "pane.exited", "pane.agent_detected",
            // herdr sends it on a terminal title change; a title can pick a pane's icon.
            "pane.updated", "layout.updated",
        ]
        // Each agent entry makes herdr poll that pane every 100 ms, so plain shells are left out.
        let subscriptions = types.map { ["type": $0] }
            + agentPanes.map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        let params = ["subscriptions": subscriptions]
        // Only strings: serializing cannot fail.
        let request = jsonLine(["id": "events", "method": "events.subscribe", "params": params]) ?? ""
        events = Task { [self] in
            do {
                let channel = try await exec.run([herdr(), "--session", session, "remote-api-bridge"])
                channel.write(request)
                for await line in channel.lines {
                    let message = try? JSONDecoder().decode(EventLine.self, from: Data(line.utf8))
                    // events_lost, pane_not_found: start over.
                    guard message?.error == nil else { break }
                    ask(message?.data?.pane?.tokens?[Tokens.request], message?.data?.pane?.paneID)
                    // The first line too: subscription_started means catch up on what came ahead of it.
                    read()
                }
                channel.terminate()
            } catch {}
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            subscribed = nil
            read()
        }
    }

    /// herdr sends the token again on each change of the pane until it expires.
    private func ask(_ id: String?, _ pane: String?) {
        // ponytail: a linear search of 256 ids per ring.
        guard let id, let pane, AgentRequest.isID(id), !asked.contains(id) else { return }
        asked = asked.suffix(255) + [id]
        out?.yield(.request(id: id, pane: pane))
    }

    private func beat() async {
        repeat {
            // A 2 s tick, so a read that fails mid-wait (the session stopped) is retried soon.
            if lastRead.map({ ContinuousClock.now - $0 >= .seconds(30) }) ?? true {
                read()
            }
        } while await (try? Task.sleep(for: .seconds(2))) != nil
    }

    nonisolated func herdr() async throws -> String {
        guard let path = try await exec.herdr() else { throw HerdrError.notFound }
        return path
    }
}

private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: Data(text.utf8))
    } catch {
        throw HerdrError.failed("unreadable reply from herdr: \(error)")
    }
}

struct Reply<Result: Decodable>: Decodable {
    let result: Result?
    let error: ReplyError?
}

struct ReplyError: Decodable {
    let code: String
    let message: String
}

private struct EventLine: Decodable {
    struct Payload: Decodable {
        let pane: EventPane?
    }

    let error: ReplyError?
    let data: Payload?
}

private struct EventPane: Decodable {
    let paneID: String?
    let tokens: Tokens?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id", tokens
    }
}

private struct SessionList: Decodable {
    let sessions: [Session]
}

struct PaneResult: Decodable {
    let pane: Pane
}

struct SnapshotResult: Decodable {
    let snapshot: Snapshot
}

struct ExportResult: Decodable {
    struct Layout: Decodable { let root: SplitNode }
    let layout: Layout
}

func jsonLine(_ object: [String: Any]) -> String? {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    else { return nil }
    return String(decoding: data, as: UTF8.self)
}
