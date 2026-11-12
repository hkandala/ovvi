import Foundation
@testable import HerdrKit
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

/// Through awk a `head` left behind would hang on the FIFO. Without awk, this Mac's reader drains the pipe ahead of
/// the kill.
@Test(.timeLimit(.minutes(2))) func `a dropped follow stops its backlog`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-drop-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    let line = String(repeating: "x", count: 999)
    try Data(String(repeating: line + "\n", count: 20000).utf8).write(to: file)
    let channel = try await localExec.run(["sh", "-c", observeWrapper, "sh", "sh", "-c",
                                           ProcessExec.followScript, "sh", file.path, "0", "", "/^skip/"])
    var after = 0, closed = false
    for await text in channel.lines where text == line {
        if !closed {
            channel.closeInput()
            closed = true
            // A slow reader, as a relay over SSH: it reads on once the kill landed (no process has the file in its
            // argv), with the pipes full. A set wait runs out on a starved Mac ahead of the kill.
            let end = ContinuousClock.now + failureBound
            while try await !localExec.output(["pgrep", "-f", file.lastPathComponent]).isEmpty {
                try #require(ContinuousClock.now < end, "the follow's processes outlived the kill")
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        after += 1
    }
    // The pipes' buffers (32–65 lines), not the 20,000 lines.
    #expect(after < 10000)
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
        while case let pids = try await localExec.output(["pgrep", "-f", file.lastPathComponent]), !pids.isEmpty {
            guard ContinuousClock.now < end else {
                _ = try? await localExec.output(["kill"] + pids.split(separator: "\n").map(String.init))
                Issue.record("the follow's processes outlived the drop")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// A pi session can pass 100 MB: its backlog loads at `head`'s speed (0.9 s for 80 MB at a load of 15), not at macOS
/// `tail`'s 17 MB a second (5.3 s). Measured against `tail` on the same file, so a busy Mac slows both, from each one's
/// first line to its last: the follow starts a dozen processes ahead of its first read, `tail` one, and on a starved
/// Mac a process can take seconds to start. Each is timed twice, in turns, and the faster time counts: a stall
/// lengthens one run, not both.
@Test func `a big backlog loads fast`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-backlog-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(String(repeating: String(repeating: "x", count: 7999) + "\n", count: 5000).utf8).write(to: file)
    var tail = Duration.seconds(1000), follow = tail
    for _ in 0 ..< 2 {
        var start: ContinuousClock.Instant?
        for await _ in try await localExec.run(["tail", "-c", "+1", file.path]).lines where start == nil {
            start = .now
        }
        tail = min(tail, ContinuousClock.now - (start ?? .now))
        start = nil
        for await line in try await lineByLine(file.path, from: FileMark()) {
            if case .line = line, start == nil {
                start = .now
            } else if case .loaded = line {
                break
            }
        }
        follow = min(follow, ContinuousClock.now - (start ?? .now))
    }
    #expect(follow < tail / 2, "follow \(follow), tail \(tail)")
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
