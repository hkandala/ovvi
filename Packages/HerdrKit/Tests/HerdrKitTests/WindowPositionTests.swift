import CoreGraphics
import HerdrKit
import Testing

@Test func `a window's position stays on the screen of its frame`() {
    // A laptop's screen (primary, with the menu bar) and an external one above it and to the left: AppKit's frame
    // (-400, 982, 2560 × 1440), that is (-400, -1440) from the laptop's top-left, y down.
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let external = CGRect(x: -400, y: -1440, width: 2560, height: 1440)
    let onExternal = CGRect(x: 100, y: 1500, width: 720, height: 460)
    #expect(onExternal.windowPosition(primary: laptop) == CGPoint(x: 100, y: -978))
    #expect(external.contains(onExternal.windowPosition(primary: laptop)))
    let onLaptop = CGRect(x: 200, y: 100, width: 720, height: 460)
    #expect(onLaptop.windowPosition(primary: laptop) == CGPoint(x: 200, y: 422))
}
