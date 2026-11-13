import AppKit

/// A menu item's target is weak: the item keeps this as `representedObject`.
final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire() {
        run()
    }
}

/// For a nested run loop (a menu, a modal alert) in async code: no other main actor job runs inside a job, so it runs
/// from a run-loop block instead, in the default mode so it waits out another menu's tracking. Returns its result once
/// it ended.
@MainActor
func outsideMainQueue<T: Sendable>(_ run: @escaping () -> T) async -> T {
    await withCheckedContinuation { done in
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) { done.resume(returning: run()) }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}

extension NSMenu {
    /// Returns once the menu closed, after the picked item's action. Not for a view that left its window meanwhile.
    func popUp(at point: NSPoint, in view: NSView) async {
        await outsideMainQueue {
            if view.window != nil {
                self.popUp(positioning: nil, at: point, in: view)
            }
        }
    }
}
