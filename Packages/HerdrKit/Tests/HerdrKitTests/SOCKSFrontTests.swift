import Foundation
@testable import HerdrKit
import Network
import Synchronization
import Testing

/// The browser proxy's front, before a stand-in for ssh's `-D` that opens only `localhost:7` and echoes there, and
/// closes any other request without a reply, as ssh does.
@Test func `front asks for localhost and refuses at once`() async throws {
    let asked = Mutex<[String]>([])
    let ssh = try await standIn { host in asked.withLock { $0.append(host) } }
    defer { ssh.cancel() }
    let upstream = try #require(ssh.port?.rawValue)
    let front = try await SOCKSFront.start { _ in upstream }
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
}

/// ssh's `-D` port that nothing answers on (its master gone, or the forward lost): the front asks for a new one, once.
@Test func `front forwards again when ssh's port is gone`() async throws {
    let ssh = try await standIn()
    defer { ssh.cancel() }
    let live = try #require(ssh.port?.rawValue), gone = try #require(SOCKSFront.freePort())
    let calls = Mutex<[UInt16?]>([])
    let front = try await SOCKSFront.start { dead in
        calls.withLock { $0.append(dead) }
        return dead == nil ? gone : live
    }
    defer { front.stop() }
    #expect(await connect(front, "devbox.localhost", 7).0 == 0)
    #expect(calls.withLock { $0 } == [nil, gone])
}

/// A listener that ends by itself (a failure) listens again on the same port, which the cards' store keeps; one
/// stopped does not.
@Test func `front listens again on its port`() async throws {
    let ssh = try await standIn()
    defer { ssh.cancel() }
    let upstream = try #require(ssh.port?.rawValue)
    let front = try await SOCKSFront.start { _ in upstream }
    let port = front.port
    let (open, page) = await connect(front, "devbox.localhost", 7)
    #expect(open == 0)
    front.current.withLock { $0.listener?.cancel() }
    var again: UInt8?
    for _ in 0 ..< 50 where again != 0 {
        try await Task.sleep(for: .milliseconds(100))
        again = await connect(front, "devbox.localhost", 7, on: port).0
    }
    #expect(again == 0)
    #expect(front.port == port)
    // The page connected before goes on.
    page.send(content: Data("ping".utf8), completion: .idempotent)
    #expect(await page.read(4) == Data("ping".utf8))
    front.stop()
    try await Task.sleep(for: .milliseconds(300))
    #expect(await connect(front, "devbox.localhost", 7, on: port).0 == nil)
}

/// A machine that cannot be reached (blocked until Connect): a general failure, at once.
@Test func `front fails at once without a machine`() async throws {
    let front = try await SOCKSFront.start { _ in throw HerdrError.disconnected("Canceled") }
    defer { front.stop() }
    #expect(await connect(front, "devbox.localhost", 7).0 == 1)
}

/// A stand-in for ssh's `-D`, which tells each host asked of it.
private func standIn(_ asked: @escaping @Sendable (String) -> Void = { _ in }) async throws -> NWListener {
    let ssh = try NWListener(using: .tcp, on: .any)
    ssh.newConnectionHandler = { connection in
        connection.start(queue: .global())
        Task {
            guard await connection.read(3) == Data([5, 1, 0]) else { return connection.cancel() }
            connection.send(content: Data([5, 0]), completion: .idempotent)
            guard let head = await connection.read(5), let name = await connection.read(Int(head[4])),
                  let port = await connection.read(2)
            else { return connection.cancel() }
            let host = String(decoding: name, as: UTF8.self)
            asked(host)
            guard host == "localhost", port == Data([0, 7]) else { return connection.cancel() }
            connection.send(content: Data([5, 0, 0, 1, 127, 0, 0, 1, 0, 7]), completion: .idempotent)
            while let data = await connection.readSome() {
                connection.send(content: data, completion: .idempotent)
            }
        }
    }
    let ready = AsyncStream<Void> { continuation in
        ssh.stateUpdateHandler = {
            if $0 == .ready {
                continuation.finish()
            }
        }
    }
    ssh.start(queue: .global())
    for await _ in ready {}
    return ssh
}

/// A page's CONNECT through the front (on `port`, else its own): its reply code, nil when nothing answers there,
/// and the connection.
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
