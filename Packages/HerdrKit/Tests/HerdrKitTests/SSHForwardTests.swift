import Foundation
@testable import HerdrKit
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
        let options = ["-F", path + "/ssh_config"]
        let listening = await eventually {
            try? await Task.sleep(for: .milliseconds(200))
            return await localExec.succeeds(#"exec ssh -o BatchMode=yes "$@" true"#, options + [alias])
        }
        try #require(listening)
        return TestSSHD(alias: alias, folder: folder, options: options, server: server)
    }

    func stop() {
        server.terminate()
        try? FileManager.default.removeItem(at: folder)
    }
}

private func mode(_ path: String) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int
}

@Test(.enabled("herdr is not on PATH", herdrInstalled), .enabled("no sshd") {
    FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd")
})
func `a remote machine's requests go over a forwarded socket, after a server restart and a dropped connection too`()
    async throws
{
    let sshd = try await TestSSHD.start()
    defer { sshd.stop() }
    let session = "ovvi-e2e-\(UUID().uuidString.prefix(6).lowercased())"
    try #require(await shell(sessionScript, "up", session) == 0)
    defer { await shell(sessionScript, "down", session) }
    let exec = SSHExec(target: sshd.alias, local: localExec, options: sshd.options)
    let client = HerdrClient(session: session, exec: exec)
    _ = try await client.snapshot()
    let forwards = await exec.herdrForwards
    let local = try #require(forwards[session]?.local)
    #expect(mode(local) == 0o600 && mode(SSHExec.folder) == 0o700)
    // The app's pid in the name: another Ovvi on the Mac has its own.
    #expect(local.hasPrefix(exec.socket + "-") && exec.socket.hasSuffix("-\(getpid())"))

    // herdr's server ends and starts again: the same forward reaches the new one.
    try await client.stopSession()
    await #expect(throws: HerdrError.self) { try await client.snapshot() }
    try await client.deleteSession()
    try #require(await shell(sessionScript, "up", session) == 0)
    _ = try await client.snapshot()

    // The master dies and leaves its sockets: a new master forwards again over the stale file.
    let dropped = try #require(await exec.connection)
    kill(dropped, SIGKILL)
    #expect(await eventually { kill(dropped, 0) != 0 })
    #expect(FileManager.default.fileExists(atPath: local))
    _ = try await client.snapshot()
    let (connection, again) = await (exec.connection, exec.herdrForwards)
    #expect(connection != dropped && again[session]?.pid == connection)

    exec.disconnect()
    #expect(!FileManager.default.fileExists(atPath: local))
}

@Test(.enabled("herdr is not on PATH", herdrInstalled), .enabled("no sshd") {
    FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd")
})
func `a host that refuses to forward a socket says so`() async throws {
    let sshd = try await TestSSHD.start("AllowStreamLocalForwarding no")
    defer { sshd.stop() }
    let session = "ovvi-e2e-\(UUID().uuidString.prefix(6).lowercased())"
    try #require(await shell(sessionScript, "up", session) == 0)
    defer { await shell(sessionScript, "down", session) }
    let exec = SSHExec(target: sshd.alias, local: localExec, options: sshd.options)
    defer { exec.disconnect() }
    let refused = "\(sshd.alias) refuses to forward herdr's socket: Ovvi needs sshd's AllowStreamLocalForwarding"
    await #expect(throws: HerdrError.failed(refused)) { try await HerdrClient(session: session, exec: exec).snapshot() }
}
