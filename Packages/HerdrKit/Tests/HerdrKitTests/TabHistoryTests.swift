import HerdrKit
import Testing

private func shown(_ ids: String...) -> TabHistory {
    var history = TabHistory()
    ids.forEach { history.show($0) }
    return history
}

@Test func `a tab shown again moves to the newest place: cycles never repeat`() {
    let history = shown("a", "b", "c", "a", "b", "c", "b")
    #expect(history.ids == ["a", "c", "b"] && history.place == 2)
    #expect(history.trail(-1, from: "b", max: 10) { _ in true } == [1, 0])
}

@Test func `a step adds nothing; a show after Back drops the tabs ahead`() {
    var history = shown("a", "b", "c", "d")
    history.place = 1
    history.show("b")
    #expect(history.ids == ["a", "b", "c", "d"] && history.place == 1)
    #expect(history.trail(1, from: "b", max: 10) { _ in true } == [2, 3])
    history.show("d")
    #expect(history.ids == ["a", "b", "d"] && history.place == 2)
    history.place = 0
    history.show("e")
    #expect(history.ids == ["a", "e"])
}

@Test func `steps go past closed tabs; the history keeps the last 100`() {
    let history = shown("a", "b", "c")
    #expect(history.trail(-1, from: "c", max: 10) { $0 != "b" } == [0])
    let long = (0 ..< 150).reduce(into: TabHistory()) { $0.show("\($1)") }
    #expect(long.ids.count == 100 && long.ids.first == "50" && long.place == 99)
}
