import CoreGraphics

public extension CGRect {
    /// The top-left corner as SwiftUI's `WindowPlacement` takes an absolute position: from the top-left of the
    /// primary screen (the one at AppKit's origin), y down, for every screen. `primary` is that screen's frame.
    func windowPosition(primary: CGRect) -> CGPoint {
        CGPoint(x: minX, y: primary.maxY - maxY)
    }
}
