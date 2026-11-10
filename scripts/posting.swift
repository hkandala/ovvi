// The e2e helper prepends this file to each script that posts events.
import CoreGraphics
import Foundation

/// Refuses unless the tests' app (the pid the e2e helper passes in OVVI_APP_PID) owns the window in front at each
/// point: posted events never reach another app, the user's own Ovvi, or a panel over the app's window.
func onlyIntoTheApp(_ points: [CGPoint]) {
    let app = Int(ProcessInfo.processInfo.environment["OVVI_APP_PID"] ?? "") ?? 0
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    for point in points {
        let front = windows.first { window in
            let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            // Below the Dock's level: the windows above it (the Dock's own, the menu bar, the cursor, a drag's image,
            // macOS's overlay while UI tests drive it) let events through, or are no app's.
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            return layer < Int(CGWindowLevelForKey(.dockWindow))
                && (window[kCGWindowAlpha as String] as? Double ?? 0) > 0 && bounds?.contains(point) == true
        }
        guard app > 0, front?[kCGWindowOwnerPID as String] as? Int == app else {
            let owner = front
                .map { "\($0[kCGWindowOwnerName as String] ?? "") (pid \($0[kCGWindowOwnerPID as String] ?? 0))" }
            fatalError("\(point) is in \(owner ?? "no window"), not the tests' app's (pid \(app))")
        }
    }
}

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func warp(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    Thread.sleep(forTimeInterval: 0.3)
}

func glide(from start: CGPoint, to end: CGPoint) {
    for step in 1 ... 20 {
        let part = Double(step) / 20
        post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * part, y: start.y + (end.y - start.y) * part))
        Thread.sleep(forTimeInterval: 0.015)
    }
}
