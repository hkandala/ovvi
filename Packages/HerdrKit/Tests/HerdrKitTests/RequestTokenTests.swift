import Foundation
@testable import HerdrKit
import Testing

@Test func `a pane's ring delivers one request per id, only a UUID, the last 256 remembered`() async throws {
    let exec = FakeExec()
    let updates = try await started(client(exec), exec)
    let id = "7f9c2b1e-4d0a-4c55-9a51-0b6c3e2d8f10"
    let ring = { (pane: String, id: String) in
        exec.event(#"{"event":"pane_updated","data":{"pane":{"pane_id":"\#(pane)","tokens":{"ovvi-req":"\#(id)"}}}}"#)
    }
    let others = (0 ..< 256).map { _ in UUID().uuidString.lowercased() }
    ring("w1:p2", id)
    ring("w1:p2", id)
    ring("w1:p2", "../x")
    ring("w1:p3", id.uppercased())
    others.forEach { ring("w1:p3", $0) }
    ring("w1:p4", id)
    var requests: [(String, String)] = []
    for await update in updates {
        guard case let .request(id, pane) = update else { continue }
        requests.append((id, pane))
        if pane == "w1:p4" {
            break
        }
    }
    #expect(requests.map(\.0) == [id] + others + [id])
    #expect(requests.first?.1 == "w1:p2")
}

@Test func `a ring in a snapshot, which the stream missed, delivers its request once`() async throws {
    let exec = FakeExec()
    let (id, other) = ("7f9c2b1e-4d0a-4c55-9a51-0b6c3e2d8f10", "8f9c2b1e-4d0a-4c55-9a51-0b6c3e2d8f10")
    exec.state.withLock {
        $0.panes = [#"{"pane_id":"w1:p2","tab_id":"w1:t1","tokens":{"ovvi-req":"\#(id)","ovvi-shown":"1"}}"#]
    }
    let updates = try await started(client(exec), exec)
    exec.event(#"{"event":"pane_updated","data":{"pane":{"pane_id":"w1:p3","tokens":{"ovvi-req":"\#(id)"}}}}"#)
    exec.event(#"{"event":"pane_updated","data":{"pane":{"pane_id":"w1:p4","tokens":{"ovvi-req":"\#(other)"}}}}"#)
    var requests: [String] = []
    for await case let .request(ring, pane) in updates {
        requests.append("\(pane) \(ring)")
        if pane == "w1:p4" {
            break
        }
    }
    #expect(requests == ["w1:p2 \(id)", "w1:p4 \(other)"])
}
