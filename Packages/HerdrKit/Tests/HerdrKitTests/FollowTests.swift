import Foundation
@testable import HerdrKit
import Synchronization
import Testing

private func lineByLine(_ path: String, from mark: FileMark,
                        skip: String = "0") async throws -> AsyncStream<FollowedLine>
{
    let batches = try await localExec.follow(path, from: mark, skip: skip)
    let (stream, continuation) = AsyncStream<FollowedLine>.makeStream()
    let task = Task {
        for await batch in batches {
            batch.forEach { continuation.yield($0) }
        }
        continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
}

@Test func `follow reads whole lines and goes on from its mark`() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ovvi-follow-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "t.jsonl")
    func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    var lines = try await lineByLine(file.path, from: FileMark()).makeAsyncIterator()
    // A file not written yet says so, then is waited for.
    guard case .missing? = await lines.next() else { Issue.record("not missing"); return }
    try Data("a\n{\"b\":".utf8).write(to: file)
    guard case let .opened(first, restarted)? = await lines.next() else { Issue.record("not opened"); return }
    #expect(restarted && first.offset == 0)
    guard case .line("a", _)? = await lines.next(), case .loaded? = await lines.next() else {
        Issue.record("no a"); return
    }
    try append("2}\n")
    guard case let .line(line, mark)? = await lines.next() else { Issue.record("no b"); return }
    #expect(line == #"{"b":2}"#)
    #expect(mark.offset == 10)

    try append("c\n")
    var again = try await lineByLine(file.path, from: mark).makeAsyncIterator()
    guard case .opened(_, false)? = await again.next(), case .line("c", _)? = await again.next() else {
        Issue.record("no resume"); return
    }
    try FileManager.default.removeItem(at: file)
    try Data("d\n".utf8).write(to: file)
    var rotated = try await lineByLine(file.path, from: mark).makeAsyncIterator()
    guard case .opened(_, true)? = await rotated.next(), case .line("d", _)? = await rotated.next() else {
        Issue.record("no restart"); return
    }

    let big = folder.appending(path: "big.jsonl")
    try Data(("first\n" + String(repeating: "é", count: 150_000) + "\nlast\n").utf8).write(to: big)
    var whole = try await lineByLine(big.path, from: FileMark()).makeAsyncIterator()
    guard case .opened(_, true)? = await whole.next(), case .line("first", _)? = await whole.next(),
          case .line(_, _)? = await whole.next(), case let .line("last", end)? = await whole.next(),
          case .loaded? = await whole.next() else { Issue.record("not whole"); return }
    #expect(end.offset == 300_012)
}

@Test func `follow skips the lines no parser reads`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-skip-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(#"{"type":"blob","é":1}\#n{"keep":1}\#n{"type":"blob"}\#n{"ke"#.utf8).write(to: file)
    var lines = try await lineByLine(file.path, from: FileMark(), skip: #"/^[{]"type":"blob"/"#)
        .makeAsyncIterator()
    guard case .opened? = await lines.next(), case let .line(#"{"keep":1}"#, mark)? = await lines.next(),
          case .loaded? = await lines.next() else { Issue.record("not skipped"); return }
    #expect(mark.offset == 34)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"ep":2}\#n"#.utf8))
    try handle.close()
    guard case let .line(#"{"keep":2}"#, last)? = await lines.next() else { Issue.record("no last"); return }
    #expect(last.offset == 61)
}

/// A `head` left behind sends the whole backlog. The reader is a slow one, as a relay over SSH: it reads only as it
/// takes lines, so the follow waits on full pipes until the kill. `ProcessExec`'s reader drains the pipe at once, so
/// through it the whole backlog could pass before a starved Mac ran the kill. The package's only `FileHandle.bytes`
/// reader: they share one blocking reader (see `ProcessExec.chunks`).
@Test(.timeLimit(.minutes(2))) func `a dropped follow stops its backlog`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-drop-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    let line = String(repeating: "x", count: 999)
    try Data(String(repeating: line + "\n", count: 20000).utf8).write(to: file)
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", observeWrapper, "sh", "sh", "-c", ProcessExec.followScript, "sh", file.path, "0", "",
                         "/^skip/"]
    process.standardInput = input
    process.standardOutput = output
    try process.run()
    var after = 0, closed = false
    for try await text in output.fileHandleForReading.bytes.lines where text == line {
        if !closed {
            try input.fileHandleForWriting.close()
            closed = true
            // Reads on once the kill landed: no process has the file in its argv.
            let end = ContinuousClock.now + failureBound
            while case let pids = try await localExec.output(["pgrep", "-f", file.lastPathComponent],
                                                             timeout: failureBound), !pids.isEmpty
            {
                guard ContinuousClock.now < end else {
                    _ = try? await localExec.output(["kill"] + pids.split(separator: "\n").map(String.init))
                    Issue.record("the follow's processes outlived the kill")
                    return
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        after += 1
    }
    // The pipes' buffers, not the 20,000 lines.
    #expect(after < 1000, "\(after) lines after the drop")
}

/// macOS's sh can lose the wrapper's one kill (pending in its trap as it goes on to `exec tail`), and `tail` then
/// lives on. awk's pattern holds the file's name, so a left awk shows too.
@Test(.timeLimit(.minutes(3)), arguments: [false, true])
func `a dropped follow leaves no process`(awk: Bool) async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-left-\(UUID().uuidString).jsonl")
    let skip = awk ? "/^\(file.lastPathComponent)/" : "0"
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(("first\n" + String(repeating: "x", count: 300_000) + "\nlast\n").utf8).write(to: file)
    for _ in 0 ..< 3 {
        for await line in try await lineByLine(file.path, from: FileMark(), skip: skip) {
            if case .loaded = line {
                break
            }
        }
        // A left process lives forever; the wait covers a starved Mac, where a retry's `sleep` takes seconds to start.
        let end = ContinuousClock.now + failureBound
        while case let pids = try await localExec.output(["pgrep", "-f", file.lastPathComponent],
                                                         timeout: failureBound), !pids.isEmpty
        {
            guard ContinuousClock.now < end else {
                _ = try? await localExec.output(["kill"] + pids.split(separator: "\n").map(String.init))
                Issue.record("the follow's processes outlived the drop")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// A pi session can pass 100 MB, and macOS's `tail` copies 17 MB a second: the backlog goes out through `head` from a
/// seek, and `tail` reads the file only from the backlog's end (the check of its last byte, then the follow).
@Test func `a big backlog goes out through head, never tail`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "backlog.jsonl"), calls = folder.appending(path: "tail-calls")
    try Data(String(repeating: String(repeating: "x", count: 99) + "\n", count: 1000).utf8).write(to: file)
    let tail = folder.appending(path: "tail")
    try Data("#!/bin/sh\necho \"$*\" >>'\(calls.path)'\nexec /usr/bin/tail \"$@\"\n".utf8).write(to: tail)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tail.path)
    var env = localExec.environment
    env["PATH"] = folder.path + ":/usr/bin:/bin"
    var lines = 0
    // A line written after the backlog comes through the follow's own `tail`.
    following: for await batch in try await ProcessExec(env, herdr: nil, asked: .now)
        .follow(file.path, from: FileMark())
    {
        for line in batch {
            if case .line("y", _) = line {
                break following
            } else if case .line = line {
                lines += 1
            } else if case .loaded = line {
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("y\n".utf8))
                try handle.close()
            }
        }
    }
    #expect(lines == 1000)
    let starts = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n")
        .filter { $0.hasSuffix(file.path) }.map { $0.split(separator: " ")[1] }
    // The check of the backlog's last byte, then the follow.
    #expect(starts == ["+100000", "+100001"], "\(starts)")
}

@Test func `a burst comes in few batches`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-burst-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("a\n".utf8).write(to: file)
    var batches = try await localExec.follow(file.path, from: FileMark()).makeAsyncIterator()
    var lines = 0
    while lines < 1 {
        lines += try await batches.next()?.count(where: {
            if case .line = $0 {
                true
            } else {
                false
            }
        }) ?? 0
    }
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(String(repeating: #"{"type":"user","message":{"content":"Question"}}"# + "\n",
                                             count: 600).utf8))
    try handle.close()
    var count = 0
    // Without batches, one per line: stop at the third.
    while lines < 601, count < 3, let batch = try await batches.next() {
        lines += batch.count
        count += 1
        // Busy: the rest of the burst comes meanwhile, also from `tail` on a starved Mac.
        try await Task.sleep(for: .seconds(2))
    }
    #expect(lines == 601 && count <= 2)
}

@Test func `watch prints a file each time it changes`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-watch-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    var lines = try await localExec.watch(["/nonexistent/x.json", file.path]).makeAsyncIterator()
    #expect(await lines.next() == "")
    try Data("{\"status\":\n\"idle\"}".utf8).write(to: file)
    #expect(await lines.next() == #"{"status":"idle"}"#)
    try Data(#"{"status":"busy"}"#.utf8).write(to: file)
    #expect(await lines.next() == #"{"status":"busy"}"#)
}

@Test(arguments: [
    ("claude-transcript", ClaudeTranscript.unread, [
        #"{"type":"api-request-blob","sessionId":"s","hash":"h","blob":"x"}"#,
        #"{"parentUuid":"p","isSidechain":false,"attachment":{"type":"hook_success"},"type":"attachment"}"#,
    ]),
    ("codex-rollout", CodexRollout.unread, [
        #"{"timestamp":"2026-10-28T12:17:47Z","ordinal":5,"type":"response_item","payload":{"type":"message"}}"#,
    ]),
])
func `follow drops only what the parser skips`(name: String, unread: String, extra: [String]) async throws {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init) + extra
    let read = name == "codex-rollout" ? CodexRollout.read : ClaudeTranscript.read
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-unread-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: file)
    var whole = ChatHistory(), followed = ChatHistory(), count = 0
    lines.forEach { _ = read($0, &whole) }
    for await line in try await lineByLine(file.path, from: FileMark(), skip: unread) {
        if case .loaded = line {
            break
        }
        if case let .line(text, _) = line {
            _ = read(text, &followed)
            count += 1
        }
    }
    #expect(followed.entries.map(\.kind) == whole.entries.map(\.kind) && followed.model == whole.model)
    #expect(count <= lines.count - extra.count)
}

/// The shell loop the watch replaced (`tr` and `sleep 0.3`, two processes every 0.3 s): the reference for when a change
/// shows.
private let shellWatch = #"""
o=x
while :; do
  n=; for f; do
    case $f in /*) ;; *) f=$HOME/$f ;; esac
    [ -f "$f" ] && n=$(tr -d '\n' <"$f") && break
  done
  [ "$n" != "$o" ] && printf '%s\n' "$n" && o=$n
  sleep 0.3
done
"""#

/// The same lines as the shell loop, here and through the relay, and no later: both watch at once (a reference timed
/// with it, lessons.md), and in all the new one is at most one 0.3 s check per change behind.
@Test func `watch shows each state as the shell loop did, as soon`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-watch-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let paths = ["/nonexistent/x.json", file.path]
    for exec in try await [localExec as any Exec, RelayExec.start()] {
        try? FileManager.default.removeItem(at: file)
        let seen = Mutex<[String: [(String, ContinuousClock.Instant)]]>([:])
        let readers = try await [("new", exec.watch(paths)), ("old", exec.lines(shellWatch, paths))]
            .map { name, lines in
                Task {
                    for await line in lines {
                        seen.withLock { $0[name, default: []].append((line, .now)) }
                    }
                }
            }
        defer { readers.forEach { $0.cancel() } }
        let states = ["idle", "busy", "waiting", "idle", "shell"]
        let count = { (name: String) in seen.withLock { $0[name]?.count ?? 0 } }
        #expect(await eventually { count("new") == 1 && count("old") == 1 })
        for (index, state) in states.enumerated() {
            try Data("{\"status\":\n\"\(state)\"}".utf8).write(to: file, options: .atomic)
            #expect(await eventually { count("new") == index + 2 && count("old") == index + 2 })
        }
        let (new, old) = seen.withLock { ($0["new"] ?? [], $0["old"] ?? []) }
        #expect(new.map(\.0) == old.map(\.0) && new.map(\.0) == [""] + states.map { "{\"status\":\"\($0)\"}" })
        let behind = zip(new, old).dropFirst().reduce(Duration.zero) { $0 + ($1.0.1 - $1.1.1) }
        #expect(behind <= .milliseconds(300) * states.count, "\(behind) behind the shell loop")
    }
}
