import CoreGraphics
import HerdrKit
import Testing

/// SwiftUI sets a placed window's AppKit origin to (x, main screen's height - y - the window's height).
private func placed(_ frame: CGRect, mainHeight: CGFloat) -> CGPoint {
    let position = frame.windowPosition(mainHeight: mainHeight)
    return CGPoint(x: position.x, y: mainHeight - position.y - frame.height)
}

@Test func `a placed window keeps its frame on any screen, whichever screen is main`() {
    // A laptop's screen (primary, 982 pt tall) and a taller external one (1440 pt) above it and to the left.
    let onExternal = CGRect(x: 100, y: 1500, width: 720, height: 460)
    let onLaptop = CGRect(x: 200, y: 100, width: 720, height: 460)
    for frame in [onExternal, onLaptop] {
        for mainHeight: CGFloat in [982, 1440] {
            #expect(placed(frame, mainHeight: mainHeight) == frame.origin)
        }
    }
}
