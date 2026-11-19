import Foundation
@testable import HerdrKit
import Synchronization
import Testing

/// An sshd of this user's own on a free port, with its own keys and config, so nothing reads or writes `~/.ssh`.
private struct TestSSHD {
    /// One per server: SSHExec's sockets are per target and app.
    let alias: String
    let folder: URL
    let options: [String]
    let server: Channel

    static func start(_ extra: String = "") async throws -> TestSSHD {
        let alias = "ovvi-sshd-\(UUID().uuidString.prefix(6))"
        let folder = URL(filePath: "/tmp/" + alias)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.path
        let port = try #require(SOCKSFront.freePort())
        _ = try await localExec.checkedOutput(["sh", "-c", """
        cd "$1" && ssh-keygen -q -t ed25519 -N '' -f host && ssh-keygen -q -t ed25519 -N '' -f client &&
        cp client.pub keys && cat >sshd_config <<EOF && cat >ssh_config <<EOF
        Port $2
        ListenAddress 127.0.0.1
        HostKey $1/host
        AuthorizedKeysFile $1/keys
        PidFile $1/pid
        UsePAM no
        StrictModes no
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        $3
        EOF
        Host \(alias)
          HostName 127.0.0.1
          Port $2
          IdentityFile $1/client
          IdentitiesOnly yes
          StrictHostKeyChecking no
          UserKnownHostsFile $1/known_hosts
        EOF
        """, "sh", path, String(port), extra])
        let server = try ProcessExec.spawn(["/usr/sbin/sshd", "-D", "-f", path + "/sshd_config", "-E", path + "/log"],
                                           localExec.environment)
        let sshd = TestSSHD(alias: alias, folder: folder, options: ["-F", path + "/ssh_config"], server: server)
        let listening = await eventually {
            try? await Task.sleep(for: .milliseconds(200))
            return await localExec.succeeds(#"exec ssh -o BatchMode=yes "$@" true"#, sshd.options + [alias])
        }
        // sshd outlives the test process: one that never let a login in would listen on.
        if !listening {
            sshd.stop()
        }
        try #require(listening)
        return sshd
    }

    func stop() {
        server.terminate()
        try? FileManager.default.removeItem(at: folder)
    }
}

@Test(.enabled("herdr is not on PATH", herdrInstalled), .enabled("under a sandbox", unsandboxed), .enabled("no sshd") {
    FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd")
})
func `a remote machine's requests go through the relay, after a server restart and a dropped connection too`()
    async throws
{
    let sshd = try await TestSSHD.start()
    defer { sshd.stop() }
    let session = "ovvi-e2e-\(UUID().uuidString.prefix(6).lowercased())"
    try #require(await shell(sessionScript, "up", session) == 0)
    defer { await shell(sessionScript, "down", session) }
    let exec = SSHExec(target: sshd.alias, local: localExec, options: sshd.options, relayTimeout: failureBound)
    defer { exec.disconnect() }
    let client = HerdrClient(session: session, exec: exec, timeout: failureBound)
    _ = try await client.snapshot()
    #expect(await exec.herdrSockets[session] != nil)

    // herdr's server ends and starts again: a request with no answer looks for the socket again.
    try await client.stopSession()
    await #expect(throws: HerdrError.self) { try await client.snapshot() }
    #expect(await exec.herdrSockets[session] == nil)
    try await client.deleteSession()
    try #require(await shell(sessionScript, "up", session) == 0)
    _ = try await client.snapshot()

    // The master dies: the next request starts a new one, and its relay.
    let dropped = try #require(await exec.connection)
    kill(dropped, SIGKILL)
    #expect(await eventually { kill(dropped, 0) != 0 })
    _ = try await client.snapshot()
    #expect(await exec.connection != dropped)

    // The events stream comes through the relay: a title arrives from its event.
    let titled = Mutex(false)
    let watch = Task {
        for await update in await client.updates() {
            if case let .pane(new) = update, new.title?.hasPrefix("relay-title") == true {
                titled.withLock { $0 = true }
            }
        }
    }
    defer { watch.cancel() }
    let pane = try #require(await client.newWorkspace(label: "relay", cwd: "/tmp"))
    var turn = 0
    #expect(await eventually {
        turn += 1
        // A title now and then, a new one each time: the pane must be in a snapshot first to come in place.
        if turn % 50 == 1 {
            try? await client.sendInput("printf '\\033]0;relay-title \(turn)\\007'", keys: ["enter"], pane: pane.id)
        }
        return titled.withLock { $0 }
    })
}

@Test(.enabled("herdr is not on PATH", herdrInstalled), .enabled("under a sandbox", unsandboxed), .enabled("no sshd") {
    FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd")
})
func `a host that forwards no sockets still answers`() async throws {
    let sshd = try await TestSSHD.start("AllowStreamLocalForwarding no")
    defer { sshd.stop() }
    let session = "ovvi-e2e-\(UUID().uuidString.prefix(6).lowercased())"
    try #require(await shell(sessionScript, "up", session) == 0)
    defer { await shell(sessionScript, "down", session) }
    let exec = SSHExec(target: sshd.alias, local: localExec, options: sshd.options, relayTimeout: failureBound)
    defer { exec.disconnect() }
    let client = HerdrClient(session: session, exec: exec, timeout: failureBound)
    _ = try await client.snapshot()
}
