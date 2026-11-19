@testable import HerdrKit
import Testing

private func pane(title: String, cwd: String = "/tmp", tokens: String = "{}", revision: Int = 3) -> String {
    #"{"pane_id":"w1:p1","tab_id":"w1:t1","terminal_id":"term_1","cwd":"\#(cwd)","focused":true,"#
        + #""terminal_title_stripped":"\#(title)","agent_status":"working","tokens":\#(tokens),"#
        + #""revision":\#(revision)}"#
}

private func updated(_ pane: String) -> String {
    #"{"data":{"pane":\#(pane),"type":"pane_updated"},"event":"pane_updated"}"#
}

@Test(.timeLimit(.minutes(1)))
func `a title alone comes from its event; any other change of the pane reads a snapshot`() async throws {
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

    for other in [pane(title: "claude b", cwd: "/usr", revision: 7),
                  pane(title: "claude c", tokens: #"{"ovvi-chat":"x"}"#, revision: 8)]
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
