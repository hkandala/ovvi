import Foundation
@testable import HerdrKit
import Testing

@Test func `envelope runs the argv unchanged`() async throws {
    let argv = ["printf", "%s|", "it's", "a b", "$HOME", "\"q\"", "`x`", "ü\n2", "'\u{301}; echo no"]
    let exec = localExec
    let out = try await exec.output(["sh", "-c", shellEnvelope(argv)])
    #expect(out == "it's|a b|$HOME|\"q\"|`x`|ü\n2|'\u{301}; echo no|")
}

@Test func `targets that are not options`() {
    #expect(SSHExec.isValidTarget("user@devbox"))
    #expect(!SSHExec.isValidTarget("-oProxyCommand=x"))
    #expect(!SSHExec.isValidTarget("a b"))
    #expect(!SSHExec.isValidTarget(""))
}

@Test func `relay carries runs over one process`() async throws {
    let local = localExec
    let relay = try await Relay.started(local.environment)
    let failing = try relay.run("echo out; echo err >&2; exit 3")
    let echo = try relay.run("cat")
    let sleeping = try relay.run("sleep 100")
    echo.write(#"{"a": "b c"}"#)
    echo.closeInput()
    #expect(await echo.lines.reduce([]) { $0 + [$1] } == [#"{"a": "b c"}"#])
    #expect(await echo.exit() == (0, ""))
    #expect(await failing.lines.reduce([]) { $0 + [$1] } == ["out"])
    #expect(await failing.exit() == (3, "err\n"))
    sleeping.terminate()
    #expect(await sleeping.exit().status == 9)
    let watching = try relay.run(shellQuoted([
        "sh",
        "-c",
        observeWrapper,
        "sh",
        "sh",
        "-c",
        "while :; do echo t; sleep 0.1; done",
    ]))
    #expect(await watching.lines.first { _ in true } == "t")
    watching.terminate()
    #expect(await watching.exit().status == 9)
}

extension Relay {
    /// The machine's relay, here on This Mac.
    static func started(_ environment: [String: String]) async throws -> Relay {
        try #require(await start(ProcessExec.spawn(["perl", "-e", script], environment), timeout: failureBound))
    }
}

struct RelayExec: Exec {
    let relay: Relay

    static func start() async throws -> RelayExec {
        try await RelayExec(relay: Relay.started(localExec.environment))
    }

    func run(_ argv: [String]) throws -> Channel {
        try relay.run("exec " + shellQuoted(argv))
    }

    func herdr() -> String? {
        nil
    }

    var isRemote: Bool {
        true
    }
}

@Test func `upload copies a file whole`() async throws {
    let exec = try await RelayExec.start()
    let folder = URL.temporaryDirectory.appending(path: "ovvi-upload-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "it's a\nfile.bin")
    let bytes = Data((0 ..< 100_001).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    try bytes.write(to: file)
    let copy = try await URL(filePath: exec.upload(file))
    #expect(copy.lastPathComponent == file.lastPathComponent)
    #expect(copy.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "ovvi-drops-\(getuid())")
    #expect(try Data(contentsOf: copy) == bytes)
    try FileManager.default.removeItem(at: copy.deletingLastPathComponent())
    await #expect(throws: HerdrError.failed("\(folder.lastPathComponent) is not a file")) {
        try await exec.upload(folder)
    }
}

@Test func `relay passes NUL bytes unchanged`() async throws {
    let relay = try await Relay.started(localExec.environment)
    let run = try relay
        .run(#"printf 'a\000b c\000\n'; i=0; while [ $i -lt 20000 ]; do printf 'x/y z\000'; i=$((i+1)); done"#)
    run.closeInput()
    let lines = await run.lines.reduce([]) { $0 + [$1] }
    #expect(lines.first == "a\0b c\0")
    #expect(lines.count == 2 && lines[1] == String(repeating: "x/y z\0", count: 20000))
}
