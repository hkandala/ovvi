import AppKit
import GhosttyKit
import GhosttyTerminal
import HerdrKit

/// A plain left drag goes to the program and selects in the card. A program that reads the mouse (pi) selects from the
/// press's cell to the pointer's, both taken, in reverse video, which herdr draws black on white; libghostty takes an
/// end cell only on the far side of its 60 % point, and a cell only the program took would show white beside the
/// card's blue. So libghostty gets points at the cells' edges, and its selection takes both end cells too. A ⇧, ⌥ or ⌃
/// drag and a double or triple click select in the card alone (their cells differ from the program's); the program gets
/// such a single click on its release when the pointer stayed in its cell. ponytail: herdr reports no mouse mode; once
/// it does, follow Ghostty (a drag to a mouse program only, a ⇧-drag to the card;
/// ~/Downloads/ovvi-research/p58m/herdr-mouse-mode.patch).
extension PaneSurfaceView {
    struct Anchor {
        let column: Int, row: Int
        /// libghostty's press, in its points (top left). libghostty skips a move under 1 px, so a press within 1 px
        /// of the last move keeps that move's point: one press in a thousand near a cell's 60 % point may differ.
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
        let plain = event.modifierFlags.isDisjoint(with: [.shift, .option, .command, .control])
        anchor = event.clickCount == 1 && plain
            ? cell(event).map { Anchor(column: $0.column, row: $0.row, press: point(event)) } : nil
        click = event.clickCount == 1 && !plain ? event : nil
        if anchor != nil {
            mouse(.down, .left, event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !linkClick else { return }
        if anchor != nil {
            follow(event)
            mouse(.drag, .left, event)
            return
        }
        super.mouseDragged(with: event)
        if let click, let from = cell(click), let here = cell(event), from != here {
            self.click = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !linkClick else { return }
        if anchor != nil {
            follow(event)
            linkSurface?.sendMouseButton(state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
            mouse(.up, .left, event)
        } else {
            super.mouseUp(with: event)
            if let click {
                mouse(.down, .left, click)
                mouse(.up, .left, click)
            }
        }
        anchor = nil
        click = nil
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    /// Moves libghostty's pointer: the pointer's own point in the anchor's cell, else the edge of the pointer's cell
    /// that makes libghostty take it. Ghostty's rule for the press's cell: taken going forward when pressed before its
    /// 60 % point, going back when past it; a press on the wrong side for the drag's way is made again at the cell's
    /// other edge.
    private func follow(_ event: NSEvent) {
        var point = point(event)
        if let anchor, let metrics, let here = cell(event), here != (anchor.column, anchor.row) {
            let width = CGFloat(metrics.cellWidthPixels)
            let forward = (here.row, here.column) > (anchor.row, anchor.column)
            let into = anchor.press.x * scale - CGFloat(anchor.column) * width
            if (into < (width * 0.6).rounded()) != forward {
                press(edge(anchor.column, anchor.row, right: !forward))
            }
            point = edge(here.column, here.row, right: forward)
        }
        linkSurface?.sendMousePos(x: point.x, y: point.y)
    }

    /// Half a pixel in from the edge, so that libghostty's whole pixels land in the cell.
    private func edge(_ column: Int, _ row: Int, right: Bool) -> CGPoint {
        guard let metrics else { return .zero }
        let width = CGFloat(metrics.cellWidthPixels), height = CGFloat(metrics.cellHeightPixels)
        return CGPoint(x: (CGFloat(column) * width + (right ? width - 0.5 : 0.5)) / scale,
                       y: (CGFloat(row) + 0.5) * height / scale)
    }

    /// The release comes at the press's own point, where libghostty selects nothing (so copy on select copies nothing).
    /// libghostty counts a press within a cell's width of the last one as a double click (a word): a click at the
    /// view's far corner first starts the count again.
    private func press(_ point: CGPoint) {
        guard let surface = linkSurface, let anchor else { return }
        let far = CGPoint(x: anchor.press.x < bounds.width / 2 ? bounds.width - 1 : 0,
                          y: anchor.press.y < bounds.height / 2 ? bounds.height - 1 : 0)
        surface.sendMousePos(x: anchor.press.x, y: anchor.press.y)
        surface.sendMouseButton(state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
        for (spot, states) in [(far, [GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RELEASE]), (point, [GHOSTTY_MOUSE_PRESS])] {
            surface.sendMousePos(x: spot.x, y: spot.y)
            states.forEach { surface.sendMouseButton(state: $0, button: GHOSTTY_MOUSE_LEFT) }
        }
        self.anchor?.press = point
    }
}
