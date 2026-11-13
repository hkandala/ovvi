import HerdrKit
import Testing

@Test func `a chord reads any order and aliases, and writes the Mac's order`() {
    #expect(Chord("Shift+CMD+K")?.description == "shift+cmd+k")
    #expect(Chord("alt+command+left")?.description == "option+cmd+left")
    #expect(Chord("control+shift+tab")?.description == "ctrl+shift+tab")
    #expect(Chord("cmd++")?.key == "plus" && Chord("cmd+plus") == Chord("cmd++"))
    #expect(Chord("cmd+-")?.key == "-" && Chord("ctrl+esc")?.key == "escape")
    #expect(Chord(modifiers: ["cmd"], key: "T")?.description == "cmd+t")
}

@Test func `a chord needs cmd, ctrl or option, one known key, and each modifier once`() {
    for bad in ["k", "shift+k", "cmd+", "cmd+f1", "cmd+cmd+k", "hyper+k", "cmd+ab", "cmd+ ", ""] {
        #expect(Chord(bad) == nil, "\(bad)")
    }
    #expect(Chord(modifiers: ["shift"], key: "k") == nil)
}
