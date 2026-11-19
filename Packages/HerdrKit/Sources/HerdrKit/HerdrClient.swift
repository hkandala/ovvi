import Foundation
import os
import Synchronization

let herdrVersion = "0.9.3"

public enum Update: Sendable {
    case snapshot(Snapshot)
    case error(HerdrError)
    case request(id: String, pane: String)
    /// A pane whose title or tokens alone changed, from herdr's event instead of a snapshot read.
    case pane(Pane)
}

public actor HerdrClient {
    nonisolated let session: String
    nonisolated let exec: any Exec
    nonisolated let timeout: Duration
    nonisolated let wait: @Sendable (ContinuousClock.Instant) async -> Void

    private var out: AsyncStream<Update>.Continuation?
    private var lastRead: ContinuousClock.Instant?
    var reading = false
    private var readAgain = false
    private var hurry = false
    private var pause: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var events: Task<Void, Never>?
    private var subscribed: [String]?
    private var asked: [String] = []
    /// The panes of the last snapshot, with the titles events brought since.
    private var known: [String: Pane] = [:]
    /// The titles events brought during the read that runs: only these may stand over its snapshot, as herdr counts
    /// revisions again from 0 when it restarts.
    private var arrived: [String: Pane] = [:]

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
        let channel = try await exec.api(session)
        channel.write(line)
        let reply = try await withTimeout(timeout, onTimeout: channel.terminate) {
            await channel.lines.first { _ in true }
        }
        channel.closeInput()
        guard let reply else {
            let text = await channel.exit().stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrError.failed(text.isEmpty ? "herdr closed the connection with no answer" : text)
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

    public nonisolated func stopSession() async throws {
        try await session("stop")
    }

    /// The session must be stopped.
    public nonisolated func deleteSession() async throws {
        try await session("delete")
    }

    private nonisolated func session(_ command: String) async throws {
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
        if let version = snapshot.version, version.compare(herdrVersion, options: .numeric) == .orderedAscending {
            throw HerdrError.unsupported("herdr \(version) is too old; \(herdrVersion) or newer needed")
        }
        for layout in snapshot.layouts {
            if let tree = SplitNode(layout) {
                snapshot.trees[layout.tabID] = tree
            } else {
                // The split ids no longer parse (herdr changed their form): one call per tab from now on.
                if !Self.exported.exchange(true, ordering: .relaxed) {
                    Self.log.warning("herdr's split ids did not parse: each tab's tree comes from layout.export")
                }
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
                arrived = [:]
                do {
                    var snapshot = try await snapshot()
                    lastRead = .now
                    // A title that came during the read can be newer than the snapshot's.
                    for (index, pane) in snapshot.panes.enumerated() {
                        if let new = arrived[pane.id], new.revision ?? 0 > pane.revision ?? 0 {
                            snapshot.panes[index] = new
                        }
                    }
                    known = Dictionary(snapshot.panes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

    static let spacing = Duration.milliseconds(500)
    private static let log = Logger(ovvi: "herdr")
    private static let exported = Atomic(false)

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
                let channel = try await exec.api(session)
                channel.write(request)
                for await line in channel.lines {
                    let message = try? JSONDecoder().decode(EventLine.self, from: Data(line.utf8))
                    // events_lost, pane_not_found: start over.
                    guard message?.error == nil else { break }
                    ask(message?.data?.ring?.tokens?[Tokens.request], message?.data?.ring?.paneID)
                    if let pane = message?.data?.pane, message?.event == "pane_updated", inPlace(pane) {
                        continue
                    }
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

    /// A working agent retitles its terminal on and on, and each `ovvi` command rings with a token that expires 3 s
    /// later: those changes come from the event itself, not from a 280 KB snapshot read.
    private func inPlace(_ pane: Pane) -> Bool {
        guard let old = known[pane.id] else { return false }
        // Older than what a read brought since.
        if let new = pane.revision, let had = old.revision, new <= had {
            return true
        }
        var same = old
        same.title = pane.title
        same.tokens = pane.tokens
        same.revision = pane.revision
        guard same == pane else { return false }
        known[pane.id] = pane
        arrived[pane.id] = pane
        if pane.title != old.title || pane.tokens != old.tokens {
            out?.yield(.pane(pane))
        }
        return true
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
    let event: String?
    let error: ReplyError?
    let data: EventData?
}

/// The ring's two fields alone, so a pane that does not decode whole still rings; and the whole pane, as a snapshot
/// has it.
private struct EventData: Decodable {
    let ring: EventPane?
    let pane: Pane?

    enum CodingKeys: String, CodingKey {
        case pane
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ring = try? container.decode(EventPane.self, forKey: .pane)
        pane = try? container.decode(Pane.self, forKey: .pane)
    }
}

private struct EventPane: Decodable {
    let paneID: String?
    let tokens: Tokens?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id", tokens
    }
}

struct SessionList: Decodable {
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
