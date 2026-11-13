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
