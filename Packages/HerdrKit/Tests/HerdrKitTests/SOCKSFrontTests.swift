import Foundation
@testable import HerdrKit
import Network
import Synchronization
import Testing

/// The stand-in closes any request but `localhost:7` without a reply, as ssh does.
@Test func `front asks for localhost and refuses at once`() async throws {
    let asked = Mutex<[String]>([])
    let ssh = try await standIn { host in asked.withLock { $0.append(host) } }
    defer { ssh.cancel() }
    let upstream = try #require(ssh.port?.rawValue)
    let troubles = Mutex<[SOCKSFront.Trouble]>([])
    let front = try await SOCKSFront.start { trouble in
        if let trouble {
            troubles.withLock { $0.append(trouble) }
        }
        return upstream
    }
    defer { front.stop() }

    let (open, page) = await connect(front, "Devbox.localhost.", 7)
    #expect(open == 0)
    page.send(content: Data("ping".utf8), completion: .idempotent)
    #expect(await page.read(4) == Data("ping".utf8))
    page.cancel()
    let (refused, _) = await connect(front, "devbox.localhost", 8)
    #expect(refused == 5)
    let (other, _) = await connect(front, "db.internal", 7)
    #expect(other == 5)
    #expect(asked.withLock { $0 } == ["localhost", "localhost", "db.internal"])
    // ssh's close is the machine's answer, not a lost forward.
    #expect(troubles.withLock { $0 }.isEmpty)
}

@Test func `front forwards again when ssh's port is gone`() async throws {
    let ssh = try await standIn()
    defer { ssh.cancel() }
    let live = try #require(ssh.port?.rawValue), gone = try #require(SOCKSFront.freePort())
    let calls = Mutex<[SOCKSFront.Trouble?]>([])
    let front = try await SOCKSFront.start { trouble in
        calls.withLock { $0.append(trouble) }
        return trouble == nil ? gone : live
    }
    defer { front.stop() }
    #expect(await connect(front, "devbox.localhost", 7).0 == 0)
    #expect(calls.withLock { $0 } == [nil, .gone(gone)])
}

@Test(.timeLimit(.minutes(1))) func `front leaves a -D that hangs`() async throws {
    let hung = try NWListener(using: .tcp, on: .any)
    hung.newConnectionHandler = { $0.start(queue: .global()) }
    try await ready(hung)
    defer { hung.cancel() }
    let ssh = try await standIn()
    defer { ssh.cancel() }
    let stalled = try #require(hung.port?.rawValue), live = try #require(ssh.port?.rawValue)
    let calls = Mutex<[SOCKSFront.Trouble?]>([])
    let front = try await SOCKSFront.start { trouble in
        calls.withLock { $0.append(trouble) }
        return trouble == nil ? stalled : live
    }
    defer { front.stop() }
    #expect(await connect(front, "devbox.localhost", 7).0 == 0)
    #expect(calls.withLock { $0 } == [nil, .stalled(stalled)])
}

@Test func `front listens again on its port`() async throws {
    let ssh = try await standIn()
    defer { ssh.cancel() }
    let upstream = try #require(ssh.port?.rawValue)
    let front = try await SOCKSFront.start { _ in upstream }
    let port = front.port
    let (open, page) = await connect(front, "devbox.localhost", 7)
    #expect(open == 0)
    // No public call fails a listener: the inner one ends, as Network.framework ends a listener that fails.
    front.current.withLock { $0.listener?.cancel() }
    var again: UInt8?
    for _ in 0 ..< 50 where again != 0 {
        try await Task.sleep(for: .milliseconds(100))
        again = await connect(front, "devbox.localhost", 7, on: port).0
    }
    #expect(again == 0)
    #expect(front.port == port)
    page.send(content: Data("ping".utf8), completion: .idempotent)
    #expect(await page.read(4) == Data("ping".utf8))
    front.stop()
    try await Task.sleep(for: .milliseconds(300))
    #expect(await connect(front, "devbox.localhost", 7, on: port).0 == nil)
}

@Test func `front fails at once without a machine`() async throws {
    let front = try await SOCKSFront.start { _ in throw HerdrError.disconnected("Canceled") }
    defer { front.stop() }
    #expect(await connect(front, "devbox.localhost", 7).0 == 1)
}

private func standIn(_ asked: @escaping @Sendable (String) -> Void = { _ in }) async throws -> NWListener {
    let ssh = try NWListener(using: .tcp, on: .any)
    ssh.newConnectionHandler = { connection in
        connection.start(queue: .global())
        Task {
            // ssh holds its greeting until the machine opened the connection, and closes without it when it cannot.
            guard await connection.read(3) == Data([5, 1, 0]), let head = await connection.read(5),
                  let name = await connection.read(Int(head[4])),
                  let port = await connection.read(2)
            else { return connection.cancel() }
            let host = String(decoding: name, as: UTF8.self)
            asked(host)
            guard host == "localhost", port == Data([0, 7]) else { return connection.cancel() }
            connection.send(content: Data([5, 0, 5, 0, 0, 1, 127, 0, 0, 1, 0, 7]), completion: .idempotent)
            while let data = await connection.readSome() {
                connection.send(content: data, completion: .idempotent)
            }
        }
    }
    try await ready(ssh)
    return ssh
}

private func ready(_ listener: NWListener) async throws {
    let ready = AsyncStream<Void> { continuation in
        listener.stateUpdateHandler = {
            if $0 == .ready {
                continuation.finish()
            }
        }
    }
    listener.start(queue: .global())
    for await _ in ready {}
}

private func connect(_ front: SOCKSFront, _ host: String, _ port: UInt16,
                     on local: NWEndpoint.Port? = nil) async -> (UInt8?, NWConnection)
{
    let page = NWConnection(host: .ipv4(.loopback), port: local ?? front.port, using: .tcp)
    page.stateUpdateHandler = {
        if case .waiting = $0 {
            page.cancel()
        }
    }
    page.start(queue: .global())
    page.send(content: Data([5, 1, 0]), completion: .idempotent)
    guard await page.read(2) == Data([5, 0]) else { return (nil, page) }
    page.send(content: Data([5, 1, 0, 3, UInt8(host.utf8.count)]) + Data(host.utf8)
        + Data([UInt8(port >> 8), UInt8(port & 0xFF)]), completion: .idempotent)
    return await (page.read(10)?[1], page)
}
