import CryptoKit
import Foundation

extension SSHExec {
    struct Forward {
        let local: String, remote: String, pid: pid_t
    }

    /// The same client as This Mac's, on a local socket that the master forwards to herdr's on the machine
    /// (`ssh -O forward -L`): no process per request, one channel on the connection each.
    public func api(_ session: String) async throws -> Channel {
        let local = try await forwarded(session)
        let channel: Channel
        do {
            channel = try UnixSocket.connect(local)
        } catch {
            // No listener: the master ended. The next request forwards again, on a new one if need be.
            herdrForwards[session] = nil
            throw error
        }
        return Channel(lines: channel.lines, write: channel.write, closeInput: channel.closeInput,
                       terminate: channel.terminate,
                       exit: { [self] in
                           let result = await channel.exit()
                           return await result.status == 0 ? unanswered(session) ?? result : result
                       })
    }

    /// ssh takes a forwarded connection and closes it when the machine's end fails: herdr is not running (the
    /// caller's session list tells), its socket moved (forwarded again next time), or sshd refuses to forward it.
    private func unanswered(_ session: String) async -> (status: Int32, stderr: String)? {
        guard let listed = try? await herdrSession(session), listed.running else { return nil }
        guard let forward = herdrForwards[session], forward.remote == listed.socketPath else {
            herdrForwards[session] = nil
            return nil
        }
        return (1, "\(target) refuses to forward herdr's socket: Ovvi needs sshd's AllowStreamLocalForwarding")
    }

    private func forwarded(_ session: String) async throws -> String {
        try await up(nil)
        if let forward = herdrForwards[session], forward.pid == connection {
            return forward.local
        }
        // Requests that come meanwhile wait for one forward.
        if let task = herdrForwarding[session] {
            return try await task.value
        }
        let task = Task { try await forward(session) }
        herdrForwarding[session] = task
        defer {
            if herdrForwarding[session] == task {
                herdrForwarding[session] = nil
            }
        }
        return try await task.value
    }

    /// Per app and session (two Ovvis, or two sessions, never share one), beside the control socket, under the same
    /// length limit. ssh binds it 0600 (`StreamLocalBindMask`) in the 0700 folder, and leaves it behind when a master
    /// ends: a new forward removes it first.
    private func forward(_ session: String) async throws -> String {
        let remote = try await herdrSocket(session)
        // ssh reads `-L` as `local:remote`.
        guard !remote.contains(":") else { throw HerdrError.failed("herdr's socket path has a colon: \(remote)") }
        guard let pid = connection else { throw HerdrError.failed("The SSH connection to \(target) closed") }
        if let old = herdrForwards[session], old.pid == pid {
            _ = await control(["-O", "cancel", "-L", "\(old.local):\(old.remote)"])
        }
        let hash = SHA256.hash(data: Data(session.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        let local = socket + "-" + hash
        unlink(local)
        guard await control(["-O", "forward", "-L", "\(local):\(remote)"])?.status == 0 else {
            // A master that does not answer is gone, though `kill` passes for its pid when a new process has it.
            if await self.pid() != pid, connection == pid {
                connection = nil
            }
            throw HerdrError.failed("ssh did not forward herdr's socket on \(target)")
        }
        herdrForwards[session] = Forward(local: local, remote: remote, pid: pid)
        return local
    }
}
