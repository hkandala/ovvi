import CoreGraphics

public extension CGRect {
    /// The top-left corner as SwiftUI's `WindowPlacement` takes a position on macOS: AppKit's x, and y down from the
    /// top of a screen as tall as the main one (`NSScreen.main`, the screen with the key window), whose height
    /// SwiftUI flips it by (`AppKitWindowController.sizeAndPlaceWindow`, macOS 27). It adds no screen origin.
    func windowPosition(mainHeight: CGFloat) -> CGPoint {
        CGPoint(x: minX, y: mainHeight - maxY)
    }
}
