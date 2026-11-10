import Foundation
import Network
import os
import Synchronization

/// In front of ssh's `-D`: a page that asks for `<name>.localhost` reaches the machine's `localhost`, so the
/// machine need not resolve `*.localhost`; and a connection the machine cannot open gets a "refused" reply at
/// once (ssh closes it without a reply, and WebKit then waits 60 s).
final class SOCKSFront: Sendable {
    /// Replaced by a new one on the front's port when it ends by itself: the cards' store keeps that port.
    let current = Mutex(Current())
    struct Current {
        var listener: NWListener?
        var port: NWEndpoint.Port?
        var stopped = false
    }

    enum Trouble: Sendable, Equatable {
        case gone(UInt16)
        case stalled(UInt16)
    }

    private let upstream: @Sendable (Trouble?) async throws -> UInt16

    private init(upstream: @escaping @Sendable (Trouble?) async throws -> UInt16) {
        self.upstream = upstream
    }

    static func start(upstream: @escaping @Sendable (Trouble?) async throws -> UInt16) async throws -> SOCKSFront {
        let front = SOCKSFront(upstream: upstream)
        try await front.listen(on: .any)
        return front
    }

    var port: NWEndpoint.Port {
        current.withLock { $0.port } ?? .any
    }

    func stop() {
        current.withLock {
            $0.stopped = true
            $0.listener?.cancel()
        }
    }

    private static let log = Logger(ovvi: "proxy")

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

    private func serve(_ client: NWConnection) async {
        Self.start(client)
        guard let hello = await client.read(2), hello[0] == 5, hello[1] > 0,
              let methods = await client.read(Int(hello[1]))
        else { return client.cancel() }
        // No authentication: any local account can use the port while a card is open, as with ssh's own `-D`.
        guard methods.contains(0) else { return Self.answer(client, Data([5, 0xFF])) }
        client.send(content: Data([5, 0]), completion: .idempotent)
        guard let head = await client.read(4), head[0] == 5, head[1] == 1, let address = await address(client, head[3]),
              let port = await client.read(2)
        else { return client.cancel() }
        guard var local = try? await upstream(nil) else { return Self.answer(client, Self.failed) }
        // Nothing listens on ssh's `-D` port: the forward is gone (its master ended, or lost it).
        var connected = await Self.connect(local)
        if connected == nil, let again = try? await upstream(.gone(local)) {
            Self.log.error("ssh's forward on \(local) was gone: forwarded again on \(again)")
            (local, connected) = await (again, Self.connect(again))
        }
        guard var ssh = connected else { return Self.answer(client, Self.refused) }
        // ssh holds its greeting until the machine opened the connection, and closes without it when it cannot.
        let request = Data([5, 1, 0]) + head + address + port
        ssh.send(content: request, completion: .idempotent)
        var reading = Task { [ssh] in await ssh.read(2) }
        var greeted = await Self.greeting(reading, within: Self.patience)
        // No answer in time: a hung master or link gets a new master, and the page one more try on it; a master that
        // answers has a slow machine, which gets longer. Never a page that waits for ever.
        if greeted == nil {
            if let again = try? await upstream(.stalled(local)), again != local, let fresh = await Self.connect(again) {
                Self.log.error("ssh did not answer on \(local): a new master forwards on \(again)")
                ssh.cancel()
                ssh = fresh
                fresh.send(content: request, completion: .idempotent)
                reading = Task { await fresh.read(2) }
                greeted = await Self.greeting(reading, within: Self.patience)
            } else {
                greeted = await Self.greeting(reading, within: .seconds(30))
            }
        }
        guard greeted == true, let reply = await ssh.readSome() else {
            ssh.cancel()
            return Self.answer(client, Self.refused)
        }
        client.send(content: reply, completion: .idempotent)
        let open = Mutex(2)
        let done: @Sendable () -> Void = { [ssh] in
            if open.withLock({ $0 -= 1; return $0 == 0 }) {
                client.cancel()
                ssh.cancel()
            }
        }
        Self.pump(client, ssh, done)
        Self.pump(ssh, client, done)
    }

    /// How long ssh may take to open a page's connection on the machine: one trip there and back, well under a second
    /// (CI's localhost: milliseconds).
    static let patience = Duration.seconds(5)

    private static func greeting(_ reading: Task<Data?, Never>, within limit: Duration) async -> Bool? {
        await withCheckedContinuation { continuation in
            let waiting = Mutex<CheckedContinuation<Bool?, Never>?>(continuation)
            let timer = Task {
                try? await Task.sleep(for: limit)
                waiting.withLock { $0.take() }?.resume(returning: nil)
            }
            Task {
                let greeted = await reading.value == Data([5, 0])
                timer.cancel()
                waiting.withLock { $0.take() }?.resume(returning: greeted)
            }
        }
    }

    private static func connect(_ local: UInt16) async -> NWConnection? {
        guard let port = NWEndpoint.Port(rawValue: local) else { return nil }
        let ssh = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        let opened = await withCheckedContinuation { continuation in
            let waiting = Mutex<CheckedContinuation<Bool, Never>?>(continuation)
            ssh.stateUpdateHandler = { state in
                switch state {
                case .ready: waiting.withLock { $0.take() }?.resume(returning: true)
                case .waiting, .failed: ssh.cancel()
                case .cancelled: waiting.withLock { $0.take() }?.resume(returning: false)
                default: break
                }
            }
            ssh.start(queue: queue)
        }
        return opened ? ssh : nil
    }

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
    func read(_ count: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                continuation.resume(returning: error == nil && data?.count == count ? data : nil)
            }
        }
    }

    func readSome() async -> Data? {
        await withCheckedContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, _, error in
                continuation.resume(returning: error == nil && data?.isEmpty == false ? data : nil)
            }
        }
    }
}
