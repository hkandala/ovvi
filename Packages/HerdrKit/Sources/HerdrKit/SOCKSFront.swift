import Foundation
import Network
import os
import Synchronization

/// A remote machine's proxy for its browser cards (ui/browser#remote-localhost): SOCKS5 on a loopback port of
/// the app's own, in front of ssh's `-D` on the machine's ControlMaster. It does two things ssh's does not: a page that
/// asks for `<name>.localhost` reaches the machine's `localhost`, so the machine need not resolve `*.localhost`; and a
/// connection the machine cannot open gets a "refused" reply at once (ssh closes it without a reply, and WebKit then
/// waits 60 s).
final class SOCKSFront: Sendable {
    /// The listener, replaced by a new one on the front's port when it ends by itself: the cards' store keeps that
    /// port.
    let current = Mutex(Current())
    struct Current {
        var listener: NWListener?
        var port: NWEndpoint.Port?
        var stopped = false
    }

    /// ssh's `-D` port on the live master; given the port that did not answer, a new forward's.
    private let upstream: @Sendable (_ dead: UInt16?) async throws -> UInt16

    private init(upstream: @escaping @Sendable (_ dead: UInt16?) async throws -> UInt16) {
        self.upstream = upstream
    }

    /// Listens on a free loopback port.
    static func start(upstream: @escaping @Sendable (_ dead: UInt16?) async throws -> UInt16) async throws
        -> SOCKSFront
    {
        let front = SOCKSFront(upstream: upstream)
        try await front.listen(on: .any)
        return front
    }

    /// The front's port for its life.
    var port: NWEndpoint.Port {
        current.withLock { $0.port } ?? .any
    }

    func stop() {
        current.withLock {
            $0.stopped = true
            $0.listener?.cancel()
        }
    }

    private static let log = Logger(subsystem: "dev.ovvi.app", category: "proxy")

    private func listen(on port: NWEndpoint.Port) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        // The ended listener's pages still hold the port.
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] client in
            guard let self else { return client.cancel() }
            Task { await self.serve(client) }
        }
        let waiting = Mutex<CheckedContinuation<Void, Error>?>(nil)
        let served = Atomic(false)
        try await withCheckedThrowingContinuation { continuation in
            waiting.withLock { $0 = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    served.store(true, ordering: .relaxed)
                    self?.current.withLock { $0.port = $0.port ?? listener.port }
                    waiting.withLock { $0.take() }?.resume()
                case let .waiting(error), let .failed(error):
                    if served.load(ordering: .relaxed) {
                        Self.log.error("The browser proxy's listener ended: \(error, privacy: .public)")
                    }
                    listener.cancel()
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    listener.newConnectionHandler = nil
                    waiting.withLock { $0.take() }?
                        .resume(throwing: HerdrError.failed("The browser proxy did not start"))
                    if served.load(ordering: .relaxed) {
                        self?.relisten()
                    }
                default: break
                }
            }
            // Started under the lock: a `stop` after it cancels this one, and none starts after a `stop`.
            let started = current.withLock { state in
                if !state.stopped {
                    state.listener = listener
                    listener.start(queue: Self.queue)
                }
                return !state.stopped
            }
            if !started {
                continuation.resume(throwing: HerdrError.failed("The browser proxy stopped"))
            }
        }
    }

    /// A listener that served and ended without `stop` comes back on the front's port, every 2 s until one listens
    /// (the network back after a sleep) or the proxy stops.
    private func relisten() {
        Task {
            while let port = current.withLock({ $0.stopped ? nil : $0.port }) {
                do {
                    try await listen(on: port)
                    return Self.log.error("The browser proxy listens again on \(port.rawValue)")
                } catch {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private static let queue = DispatchQueue(label: "ovvi.socks")
    private static let refused = Data([5, 5, 0, 1, 0, 0, 0, 0, 0, 0])
    private static let failed = Data([5, 1, 0, 1, 0, 0, 0, 0, 0, 0])

    /// One page connection: the greeting and the CONNECT request here, then ssh's reply and the bytes both ways.
    private func serve(_ client: NWConnection) async {
        Self.start(client)
        guard let hello = await client.read(2), hello[0] == 5, hello[1] > 0,
              let methods = await client.read(Int(hello[1]))
        else { return client.cancel() }
        // No authentication: any local account can use the port while a card is open, as with ssh's own `-D`
        // (ui/browser#risks).
        guard methods.contains(0) else { return Self.answer(client, Data([5, 0xFF])) }
        client.send(content: Data([5, 0]), completion: .idempotent)
        guard let head = await client.read(4), head[0] == 5, head[1] == 1, let address = await address(client, head[3]),
              let port = await client.read(2)
        else { return client.cancel() }
        let request = Data([5, 1, 0]) + head + address + port
        guard let local = try? await upstream(nil) else { return Self.answer(client, Self.failed) }
        // ssh's `-D` port that does not answer is gone (its master ended, or lost the forward): forwarded again, once.
        var dialed = await Self.dial(local, request)
        if dialed == nil, let again = try? await upstream(local) {
            Self.log.error("ssh's forward on \(local) did not answer: forwarded again on \(again)")
            dialed = await Self.dial(again, request)
        }
        guard let ssh = dialed, let reply = await ssh.readSome() else {
            dialed?.cancel()
            return Self.answer(client, Self.refused)
        }
        client.send(content: reply, completion: .idempotent)
        let open = Mutex(2)
        let done: @Sendable () -> Void = {
            if open.withLock({ $0 -= 1; return $0 == 0 }) {
                client.cancel()
                ssh.cancel()
            }
        }
        Self.pump(client, ssh, done)
        Self.pump(ssh, client, done)
    }

    /// A connection to ssh's `-D` with the page's request sent, once ssh greeted it; nil when nothing answers there.
    private static func dial(_ local: UInt16, _ request: Data) async -> NWConnection? {
        guard let endpoint = NWEndpoint.Port(rawValue: local) else { return nil }
        let ssh = NWConnection(host: .ipv4(.loopback), port: endpoint, using: .tcp)
        start(ssh)
        ssh.send(content: request, completion: .idempotent)
        guard await ssh.read(2) == Data([5, 0]) else {
            ssh.cancel()
            return nil
        }
        return ssh
    }

    /// The request's address, a `<name>.localhost` made `localhost`.
    private func address(_ client: NWConnection, _ type: UInt8) async -> Data? {
        switch type {
        case 1: return await client.read(4)
        case 4: return await client.read(16)
        case 3:
            guard let count = await client.read(1), count[0] > 0, let name = await client.read(Int(count[0])) else {
                return nil
            }
            var host = String(decoding: name, as: UTF8.self).lowercased()
            if host.hasSuffix(".") {
                host.removeLast()
            }
            return host.hasSuffix(".localhost") ? Data([9]) + Data("localhost".utf8) : count + name
        default: return nil
        }
    }

    /// A connection that cannot connect (a refused port, an unknown name) ends at once instead of waiting.
    private static func start(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .waiting, .failed: connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private static func answer(_ client: NWConnection, _ reply: Data) {
        client.send(content: reply, contentContext: .finalMessage, isComplete: true,
                    completion: .contentProcessed { _ in client.cancel() })
    }

    /// Bytes one way, the next read once the last write went out; an end goes on as an end (half close).
    private static func pump(_ from: NWConnection, _ into: NWConnection, _ done: @escaping @Sendable () -> Void) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, end, error in
            guard error == nil else {
                from.cancel()
                into.cancel()
                return
            }
            if end {
                // Done once it went out: the other way may have ended, and done ends both.
                return into.send(content: data, contentContext: .finalMessage, isComplete: true,
                                 completion: .contentProcessed { _ in done() })
            }
            into.send(content: data, completion: .contentProcessed { error in
                if error == nil {
                    pump(from, into, done)
                } else {
                    from.cancel()
                    into.cancel()
                }
            })
        }
    }

    /// A free loopback port, as the system picks one for a socket bound to port 0; nil if none.
    static func freePort() -> UInt16? {
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        guard handle >= 0 else { return nil }
        defer { close(handle) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(handle, $0, size) == 0 && getsockname(handle, $0, &size) == 0
            }
        }
        return bound ? UInt16(bigEndian: address.sin_port) : nil
    }
}

extension NWConnection {
    /// Exactly `count` bytes; nil at the end or on an error.
    func read(_ count: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                continuation.resume(returning: error == nil && data?.count == count ? data : nil)
            }
        }
    }

    /// What arrived, at least a byte; nil at the end or on an error.
    func readSome() async -> Data? {
        await withCheckedContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, _, error in
                continuation.resume(returning: error == nil && data?.isEmpty == false ? data : nil)
            }
        }
    }
}
