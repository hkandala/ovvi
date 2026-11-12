import AppKit
import GhosttyKit
import GhosttyTerminal

/// A left drag goes to the program and selects in the card. A program that reads the mouse (pi) selects from the
/// press's cell to the pointer's, both taken, in reverse video, which herdr draws as black on white; libghostty takes
/// an
/// end cell only on the far side of its 60 % point. A cell the program took and the card did not showed white beside
/// the card's blue. So in a plain drag libghostty gets points at the cells' edges, and its selection takes both end
/// cells too: it covers the program's.
extension PaneSurfaceView {
    struct Anchor {
        let column: Int, row: Int
        /// libghostty's press, in its points (top left).
        var press: CGPoint
    }

    override func mouseDown(with event: NSEvent) {
        // ⌘-click on a link: in a new tab, ⌥-click: to the side, ⌘⌥-click: in the Mac's app for it. Elsewhere a
        // ⌥-click is the program's (a shell moves its cursor), a ⌘-click libghostty's (an OSC 8 link).
        let how = Self.linkKey(event.modifierFlags)
        let link = how.flatMap { how in
            link(at: convert(event.locationInWindow, from: nil))?.link ?? (how == .tab ? nil : reported(at: event))
        }
        linkClick = link != nil
        if let link, let how {
            openLink?(link, how)
            return
        }
        super.mouseDown(with: event)
        mouse(.down, .left, event)
        // A multi-click, a ⇧-click (extends) and an ⌥-drag (a rectangle) follow libghostty's own rules.
        let plain = event.modifierFlags.isDisjoint(with: [.shift, .option, .command, .control])
        anchor = event.clickCount == 1 && plain ? cell(event).map { Anchor(column: $0.column, row: $0.row,
                                                                           press: point(event)) } : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !linkClick else { return }
        if anchor != nil {
            let point = selecting(event)
            linkSurface?.sendMousePos(x: point.x, y: point.y)
        } else {
            super.mouseDragged(with: event)
        }
        mouse(.drag, .left, event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !linkClick else { return }
        if anchor != nil {
            let point = selecting(event)
            linkSurface?.sendMousePos(x: point.x, y: point.y)
            linkSurface?.sendMouseButton(state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
        } else {
            super.mouseUp(with: event)
        }
        mouse(.up, .left, event)
        anchor = nil
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    /// The point libghostty gets: the pointer's in the anchor's cell, else the edge of the pointer's cell that makes
    /// libghostty take it. Ghostty's rule for the press's cell: taken going forward when pressed before its 60 % point,
    /// going back when past it; a press on the wrong side for the drag's way is made again at the cell's other edge.
    private func selecting(_ event: NSEvent) -> CGPoint {
        guard let anchor, let metrics, let here = cell(event), here != (anchor.column, anchor.row) else {
            return point(event)
        }
        let width = CGFloat(metrics.cellWidthPixels)
        let forward = (here.row, here.column) > (anchor.row, anchor.column)
        let into = anchor.press.x * scale - CGFloat(anchor.column) * width
        if (into < (width * 0.6).rounded()) != forward {
            press(edge(anchor.column, anchor.row, right: !forward))
        }
        return edge(here.column, here.row, right: forward)
    }

    /// Half a pixel in from the edge, so that libghostty's whole pixels land in the cell.
    private func edge(_ column: Int, _ row: Int, right: Bool) -> CGPoint {
        guard let metrics else { return .zero }
        let width = CGFloat(metrics.cellWidthPixels), height = CGFloat(metrics.cellHeightPixels)
        return CGPoint(x: (CGFloat(column) * width + (right ? width - 0.5 : 0.5)) / scale,
                       y: (CGFloat(row) + 0.5) * height / scale)
    }

    /// libghostty counts a press within a cell's width of the last one as a double click (a word): a click at the
    /// view's far corner first starts the count again.
    private func press(_ point: CGPoint) {
        guard let surface = linkSurface, let anchor else { return }
        let far = CGPoint(x: anchor.press.x < bounds.width / 2 ? bounds.width - 1 : 0,
                          y: anchor.press.y < bounds.height / 2 ? bounds.height - 1 : 0)
        surface.sendMouseButton(state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
        for (spot, states) in [(far, [GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RELEASE]), (point, [GHOSTTY_MOUSE_PRESS])] {
            surface.sendMousePos(x: spot.x, y: spot.y)
            states.forEach { surface.sendMouseButton(state: $0, button: GHOSTTY_MOUSE_LEFT) }
        }
        self.anchor?.press = point
    }
}
