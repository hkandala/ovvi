@testable import HerdrKit
import Testing

private func pane(title: String, cwd: String = "/tmp", tokens: String = "{}", status: String = "working",
                  revision: Int = 3) -> String
{
    #"{"pane_id":"w1:p1","tab_id":"w1:t1","terminal_id":"term_1","cwd":"\#(cwd)","focused":true,"#
        + #""terminal_title_stripped":"\#(title)","agent_status":"\#(status)","tokens":\#(tokens),"#
        + #""revision":\#(revision)}"#
}

private func updated(_ pane: String) -> String {
    #"{"data":{"pane":\#(pane),"type":"pane_updated"},"event":"pane_updated"}"#
}

@Test(.timeLimit(.minutes(1)))
func `a title or a token alone comes from its event; any other change reads a snapshot`() async throws {
    let exec = FakeExec()
    exec.state.withLock { $0.panes = [pane(title: "claude a")] }
    let client = client(exec)
    var updates = try await started(client, exec).makeAsyncIterator()
    func title() async -> String? {
        while let update = await updates.next() {
            if case let .pane(new) = update {
                return new.id == "w1:p1" ? new.title : nil
            }
        }
        return nil
    }

    exec.event(updated(pane(title: "claude b", revision: 4)))
    #expect(await title() == "claude b")
    // The same pane again (a revision later): nothing to read, nothing to show.
    exec.event(updated(pane(title: "claude b", revision: 5)))
    // One older than the last: no title back.
    exec.event(updated(pane(title: "claude a", revision: 2)))
    exec.event(updated(pane(title: "claude c", revision: 6)))
    #expect(await title() == "claude c")
    #expect(exec[\.reads] == 0)

    // A token alone (a ring, Ovvi's chat mark) comes in place too.
    exec.event(updated(pane(title: "claude c", tokens: #"{"ovvi-chat":"x"}"#, revision: 7)))
    #expect(await title() == "claude c")
    #expect(exec[\.reads] == 0)

    for other in [pane(title: "claude c", cwd: "/usr", revision: 8),
                  pane(title: "claude c", status: "idle", revision: 9)]
    {
        let reads = exec[\.reads]
        exec.event(updated(other))
        #expect(await eventually { await !client.reading && exec[\.reads] > reads })
    }
}

@Test(.timeLimit(.minutes(1))) func `a title that comes during a read stays over the read's older one`() async throws {
    let exec = FakeExec()
    exec.state.withLock { $0.panes = [pane(title: "claude a")] }
    let client = client(exec)
    var updates = try await started(client, exec).makeAsyncIterator()
    exec.state.withLock { $0.hold = true }
    await client.refresh()
    #expect(await eventually { exec[\.inFlight] == 1 })
    exec.event(updated(pane(title: "claude b", revision: 4)))
    var titles: [String?] = []
    while let update = await updates.next() {
        switch update {
        case let .pane(new):
            titles.append(new.title)
            exec.state.withLock { $0.hold = false }
        // The opening reads' snapshots come first.
        case let .snapshot(snapshot) where !titles.isEmpty: titles.append(snapshot.panes.first?.title)
        default: break
        }
        if titles.count == 2 {
            break
        }
    }
    #expect(titles == ["claude b", "claude b"])
}

@Test(.timeLimit(.minutes(1))) func `an agent's title reads until a read brings its session`() async throws {
    let exec = FakeExec()
    let agent = #"{"pane_id":"w1:p1","tab_id":"w1:t1","terminal_id":"term_1","agent":"codex","#
        + #""terminal_title_stripped":"codex","revision":3}"#
    exec.state.withLock { $0.panes = [agent] }
    let client = client(exec)
    let updates = try await started(client, exec)
    // herdr took a session meanwhile, with no event: a title event reads.
    let titled = agent.replacingOccurrences(of: "\"codex\",\"revision\":3", with: "\"codex x\",\"revision\":4")
    exec.event(updated(titled))
    #expect(await eventually { await !client.reading && exec[\.reads] == 1 })
    // Once a read brings the session, titles come in place again.
    exec.state.withLock {
        $0.panes = [titled.replacingOccurrences(
            of: "\"codex x\"",
            with: #""codex x","agent_session":{"agent":"codex","value":"s1"}"#,
        )]
    }
    await client.refresh()
    #expect(await eventually { await !client.reading && exec[\.reads] == 2 })
    exec.event(updated(exec.state.withLock { $0.panes[0] }.replacingOccurrences(
        of: "\"codex x\",",
        with: "\"codex y\",",
    )
    .replacingOccurrences(of: "\"revision\":4", with: "\"revision\":5")))
    var title: String?
    var iterator = updates.makeAsyncIterator()
    while let update = await iterator.next() {
        if case let .pane(new) = update {
            title = new.title
            break
        }
    }
    #expect(title == "codex y" && exec[\.reads] == 2)
}
