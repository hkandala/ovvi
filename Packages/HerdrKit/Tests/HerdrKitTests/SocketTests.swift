import Foundation
@testable import HerdrKit
import Synchronization
import Testing

/// A Unix socket server in the test: it answers each request line with `answer` (nil: silence, empty: it hangs up)
/// and counts the connections whose client closed them.
final class SocketServer: Sendable {
    let path: String
    let closed = Mutex(0)
    private let handle: Int32

    init(answer: @escaping @Sendable (String) -> String?) throws {
        path = "/tmp/ovvi-sock-\(UUID().uuidString.prefix(8))"
        handle = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(handle, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 && listen(handle, 8) == 0
            }
        }
        try #require(bound)
        Thread.detachNewThread { [self] in
            while case let client = accept(handle, nil, nil), client >= 0 {
                Thread.detachNewThread {
                    let input = FileHandle(fileDescriptor: client, closeOnDealloc: true)
                    var text = ""
                    while case let data = input.availableData, !data.isEmpty {
                        text += String(decoding: data, as: UTF8.self)
                        while let end = text.firstIndex(of: "\n") {
                            let reply = answer(String(text[..<end]))
                            text = String(text[text.index(after: end)...])
                            if reply == "" {
                                return
                            }
                            if let reply {
                                input.write(Data((reply + "\n").utf8))
                            }
                        }
                    }
                    self.closed.withLock { $0 += 1 }
                }
            }
        }
    }

    func stop() {
        Darwin.shutdown(handle, SHUT_RDWR)
        close(handle)
        unlink(path)
    }
}

private struct SocketExec: Exec {
    let path: String

    func run(_ argv: [String]) throws -> Channel {
        throw HerdrError.failed("no process: \(argv)")
    }

    func herdr() -> String? {
        nil
    }

    func api(_: String) throws -> Channel {
        try UnixSocket.connect(path)
    }
}

@Test func `a request over a socket closes its connection when answered, timed out or dropped`() async throws {
    let server = try SocketServer { line in
        line.contains("session.snapshot")
            ? #"{"id":"1","result":{"snapshot":{"workspaces":[],"tabs":[],"panes":[],"layouts":[],"agents":[]}}}"# : nil
    }
    defer { server.stop() }
    let client = HerdrClient(session: "s", exec: SocketExec(path: server.path), timeout: .seconds(1))
    _ = try await client.snapshot()
    #expect(await eventually { server.closed.withLock { $0 } == 1 })
    await #expect(throws: HerdrError.timeout) { try await client.pane("p1") }
    #expect(await eventually { server.closed.withLock { $0 } == 2 })
    let dropped = Task { try await client.pane("p1") }
    try await Task.sleep(for: .milliseconds(100))
    dropped.cancel()
    _ = await dropped.result
    #expect(await eventually { server.closed.withLock { $0 } == 3 })
    // The events stream ends with the updates.
    let updates = Task { for await _ in await client.updates() {} }
    try await Task.sleep(for: .milliseconds(300))
    updates.cancel()
    #expect(await eventually { server.closed.withLock { $0 } >= 4 })
}

@Test func `a socket that closes with no answer, or is not there, says so`() async throws {
    let server = try SocketServer { _ in "" }
    let client = HerdrClient(session: "s", exec: SocketExec(path: server.path))
    await #expect(throws: HerdrError.failed("herdr closed the connection with no answer")) {
        try await client.snapshot()
    }
    server.stop()
    await #expect(throws: HerdrError.failed("herdr's socket \(server.path): No such file or directory")) {
        try await client.snapshot()
    }
}

@Test(.enabled("herdr is not on PATH", herdrInstalled))
func `herdr's socket is asked once, and again after its server came back`() async throws {
    // A herdr that logs each run: only `session list` (the path) and `session stop` should start one.
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let herdr = try #require(await localExec.herdr())
    let logged = folder.appending(path: "herdr").path
    let log = folder.appending(path: "runs").path
    try "#!/bin/sh\necho \"$*\" >>'\(log)'\nexec '\(herdr)' \"$@\"\n".write(toFile: logged, atomically: true,
                                                                            encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: logged)
    let runs = { (try? String(contentsOfFile: log, encoding: .utf8))?.split(separator: "\n").count ?? 0 }
    let exec = ProcessExec(localExec.environment, herdr: logged, asked: .now)
    let session = "ovvi-e2e-\(UUID().uuidString.prefix(6).lowercased())"
    try #require(await shell(sessionScript, "up", session) == 0)
    defer { await shell(sessionScript, "down", session) }
    let client = HerdrClient(session: session, exec: exec)
    for _ in 0 ..< 5 {
        _ = try await client.snapshot()
    }
    #expect(runs() == 1)
    try await client.stopSession()
    await #expect(throws: HerdrError.self) { try await client.snapshot() }
    #expect(runs() == 2)
    // A deleted session has no socket; one made again under its name has a new one.
    try await client.deleteSession()
    await #expect(throws: HerdrError.failed("herdr has no session \(session)")) { try await client.snapshot() }
    try #require(await shell(sessionScript, "up", session) == 0)
    _ = try await client.snapshot()
    _ = try await client.snapshot()
    // The list, stop, delete, a list after the failed connect, and one for the new server.
    #expect(runs() == 5)
}
