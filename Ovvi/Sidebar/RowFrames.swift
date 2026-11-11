import SwiftUI

extension SidebarPage {
    /// Not observed: rows write their frames as the lazy stack makes them, and a body for each would make the rows in
    /// view again.
    final class RowFrames {
        var rows: [String: CGRect] = [:]
        var top: CGFloat = 0
        /// Each in its row (`WorkspaceRow.space`).
        var targets: [String: (row: String, rect: CGRect)] = [:]
        var point: CGPoint?
        var scrolling = false
        /// The selected row, asked into view before the lazy stack made it.
        var wanted: String?
        /// One hover for the list: a hover region in each row costs every scroll frame a hit test of each (half the
        /// frames at 200 spaces). Each target observes its own light: one value all observe lights every made button
        /// again.
        var pointer: String? {
            didSet {
                if pointer != oldValue {
                    oldValue.map { light($0).lit = false }
                    pointer.map { light($0).lit = true }
                    if SettlingHost.record {
                        lit.id = pointer ?? ""
                    }
                }
            }
        }

        /// The lit target, for the tests (`recordMotion`).
        let lit = Lit()
        private var lights: [String: RowLight] = [:]

        /// ponytail: a light per target made, kept with the page (a few hundred); prune with the targets if it grows.
        func light(_ id: String) -> RowLight {
            let light = lights[id] ?? RowLight()
            lights[id] = light
            return light
        }

        func aim() {
            let point = scrolling ? nil : point.map { CGPoint(x: $0.x, y: $0.y + top) }
            pointer = point.flatMap { point in
                targets.first { _, target in
                    rows[target.row].map { target.rect.offsetBy(dx: $0.minX, dy: $0.minY).contains(point) } ?? false
                }?.key
            }
        }
    }
}

@Observable
final class RowLight {
    var lit = false
}

@Observable
final class Lit {
    var id = ""
}

/// Its own view: the page reading the light would draw again at each pointer move.
struct LitValue: View {
    let lit: Lit

    var body: some View {
        Color.clear.testValue("sidebar.lit", "Lit", lit.id)
    }
}
