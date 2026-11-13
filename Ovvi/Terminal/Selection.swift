import AppKit
import HerdrKit

/// A plain left drag selects in the card and goes to the program too, so a program that reads the mouse (pi) selects
/// and copies on its own. A ⇧, ⌥ or ⌃ drag and a double or triple click select in the card alone; the program gets such
/// a single click on its release when the pointer stayed in its cell. ponytail: such a program's selection draws beside
/// the card's, in reverse video that herdr draws black on white, so a cell only the program took shows white: an end
/// cell (libghostty takes one only past its 60 % point), and for a frame after each move, since the card's selection
/// moves at once and the program's comes back through herdr. herdr reports no mouse mode; once it does, follow Ghostty
/// (a drag to a mouse program only, a ⇧-drag to the card; ~/Downloads/ovvi-research/p58m/herdr-mouse-mode.patch).
extension PaneSurfaceView {
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
        dragging = event.clickCount == 1 && plain
        click = event.clickCount == 1 && !plain ? event : nil
        if dragging {
            mouse(.down, .left, event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !linkClick else { return }
        super.mouseDragged(with: event)
        if dragging {
            mouse(.drag, .left, event)
        } else if let click, let from = cell(click), let here = cell(event), from != here {
            self.click = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !linkClick else { return }
        super.mouseUp(with: event)
        if dragging {
            mouse(.up, .left, event)
        } else if let click {
            mouse(.down, .left, click)
            mouse(.up, .left, click)
        }
        dragging = false
        click = nil
    }
}
