import Foundation
import Network

extension SSHExec {
    /// Each call is balanced by a `closeProxy`. No password prompt: a machine that needs one fails the page until
    /// Connect.
    public func openProxy() async throws -> NWEndpoint.Port {
        if proxy == nil {
            let front = try await SOCKSFront.start { [weak self] trouble in
                guard let self else { throw HerdrError.disconnected("Closed") }
                return try await dynamicPort(after: trouble)
            }
            // Another card's start may have won meanwhile.
            if proxy == nil {
                proxy = (front, 0)
            } else {
                front.stop()
            }
        }
        proxy?.users += 1
        return proxy?.front.port ?? .any
    }

    public func closeProxy() async {
        guard let proxy else { return }
        guard proxy.users <= 1 else {
            self.proxy?.users -= 1
            return
        }
        self.proxy = nil
        proxy.front.stop()
        await cancelForward()
    }

    private func cancelForward() async {
        guard let dynamic, dynamic.pid == connection else { return }
        self.dynamic = nil
        _ = await control(["-O", "cancel", "-D", "127.0.0.1:\(dynamic.port)"])
    }

    private func dynamicPort(after trouble: SOCKSFront.Trouble?) async throws -> UInt16 {
        switch trouble {
        case let .gone(port) where dynamic?.port == port:
            dynamic = nil
        case let .stalled(port) where dynamic?.port == port:
            // The pages that stalled together wait for one check.
            let task = ending ?? Task { await endHung(port) }
            ending = task
            await task.value
            if ending == task {
                ending = nil
            }
        default: break
        }
        try await up(nil)
        if let dynamic, dynamic.pid == connection {
            return dynamic.port
        }
        if let forwarding {
            return try await forwarding.value
        }
        let task = Task { try await forward() }
        forwarding = task
        defer {
            if forwarding == task {
                forwarding = nil
            }
        }
        return try await task.value
    }

    /// A relay run crosses the link too: none in 3 s (more when the relay must start), and the master or its link
    /// hangs (stopped, or a link half open after a sleep that ServerAlive has not caught yet). It ends if it still
    /// answers here (at once: a local reply), and the next `up` starts a new one; a stopped one is left behind.
    private func endHung(_ port: UInt16) async {
        let hung = connection
        guard await (try? output(["true"], timeout: .seconds(3))) == nil, connection == hung, dynamic?.port == port
        else { return }
        _ = await control(["-O", "exit"], within: .seconds(1))
        if connection == hung {
            (dynamic, connection) = (nil, nil)
        }
    }

    /// A port ssh found taken meanwhile is tried again with another. A master that does not answer is gone, though
    /// `kill` passes for its pid when a new process has it: a new master then.
    private func forward() async throws -> UInt16 {
        for _ in 0 ..< 3 {
            guard let pid = connection, let port = SOCKSFront.freePort() else { break }
            guard await control(["-O", "forward", "-D", "127.0.0.1:\(port)"])?.status == 0 else {
                if await self.pid() != pid, connection == pid {
                    connection = nil
                    try await up(nil)
                }
                continue
            }
            dynamic = (port, pid)
            // The last card went while ssh forwarded.
            if proxy == nil {
                await cancelForward()
            }
            return port
        }
        throw HerdrError.failed("ssh did not forward a port to \(target)")
    }
}
