import AppKit
import GhosttyKit
import GhosttyTerminal
import HerdrKit
import SwiftUI

enum Links {
    /// Never silent: a path with nothing there, or an address nothing in Ovvi opens, shows a notice.
    static func open(_ link: TerminalLink, how: Opening, from terminalID: String, page: Page?) {
        guard let page else { return }
        let store = page.store
        if how == .mac, link.kind != .file {
            return onMac(link, store)
        }
        switch link.kind {
        case .web:
            guard let browser = Registry.openers(for: link.target).first else { return cannot(link, store) }
            Task { await page.open(browser, arg: link.target, from: terminalID, how: how, background: true) }
        case .mail:
            onMac(link, store)
        case .other:
            cannot(link, store)
        case .file:
            Task { await openFile(link, how: how, from: terminalID, page: page) }
        }
    }

    private static func openFile(_ link: TerminalLink, how: Opening, from terminalID: String, page: Page) async {
        let store = page.store
        let path = link.target.hasPrefix("file:") ? URL(string: link.target)?.path ?? "" : link.target
        let cwd = store.terminalPane(terminalID)?.cwd ?? "/"
        guard let found = await store.there(path, from: cwd) else {
            return store
                .notFound(path.hasPrefix("/") || path.hasPrefix("~") ? path : MachinePath.tidy("\(cwd)/\(path)"))
        }
        let url = URL(filePath: found)
        if how == .mac {
            guard !store.machine.isRemote else {
                let shown = MachinePath.short(found, remote: true)
                return store.show(Notice(text: "\(shown) is on \(store.machine.name), not on this Mac", tone: .warning))
            }
            return NSWorkspace.shared.open(url) ? () : cannot(link, store)
        }
        if !store.machine.isRemote, !found.hasSuffix("/"), ["html", "htm"].contains(url.pathExtension.lowercased()) {
            return await page.open(Registry.browser, arg: url.absoluteString, from: terminalID, how: how,
                                   background: true)
        }
        guard let plugin = Registry.openers(for: found).first else { return cannot(link, store) }
        await page.open(
            plugin,
            arg: found,
            at: link.line.map(String.init),
            from: terminalID,
            how: how,
            background: true,
        )
    }

    /// The Mac's default app for the address: the browser for a web page, Mail for `mailto:`.
    private static func onMac(_ link: TerminalLink, _ store: HostStore) {
        if let url = URL(string: link.target), NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            cannot(link, store)
        }
    }

    private static func cannot(_ link: TerminalLink, _ store: HostStore) {
        store.show(Notice(text: "Ovvi can't open \(link.target)", tone: .warning))
    }
}

/// The app finds links in libghostty's text itself (`link-url` is off): libghostty's own pattern took `/compact` and
/// the words after a path. libghostty still reports OSC 8 links, and draws their underline.
extension PaneSurfaceView {
    struct Hovered {
        let link: TerminalLink, places: [TerminalLink.Place]
    }

    /// ⌘, ⌥ or ⌘⌥ alone shows and opens links.
    static func linkKey(_ flags: NSEvent.ModifierFlags) -> Opening? {
        switch flags.intersection([.command, .control, .option, .shift]) {
        case .command: .tab
        case .option: .side
        case [.command, .option]: .mac
        default: nil
        }
    }

    /// ponytail: libghostty-spm keeps its surface handle and its text reads internal; Mirror reads the handle until
    /// the package makes `readCells` public.
    private var raw: UnsafeMutableRawPointer? {
        linkSurface.flatMap { Mirror(reflecting: $0).descendant("surface") as? UnsafeMutableRawPointer }
    }

    /// One string a cell: `""` for a wide glyph's second cell (it reads as the glyph again, and so does the pair),
    /// `" "` for a blank one. A row without wide glyphs is its text, padded: libghostty writes blanks before text as
    /// spaces and drops the ones after it, so text in the cells past its length means a wide glyph.
    private func cells(_ row: Int, columns: Int) -> [String] {
        guard let raw else { return [] }
        func read(_ first: Int, _ last: Int) -> String {
            func point(_ column: Int) -> ghostty_point_s {
                ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: UInt32(column),
                                y: UInt32(row))
            }
            var text = ghostty_text_s()
            let range = ghostty_selection_s(top_left: point(first), bottom_right: point(last), rectangle: false)
            guard ghostty_surface_read_text(raw, range, &text) else { return "" }
            defer { ghostty_surface_free_text(raw, &text) }
            return text.text.map {
                String(decoding: UnsafeRawBufferPointer(start: $0, count: Int(text.text_len)), as: UTF8.self)
            } ?? ""
        }
        let whole = read(0, columns - 1)
        if whole.count == columns || whole.count < columns && read(whole.count, columns - 1).isEmpty {
            return whole.map(String.init) + Array(repeating: " ", count: columns - whole.count)
        }
        var cells: [String] = [], previous = ""
        for column in 0 ..< columns {
            let text = read(column, column)
            let spacer = column > 0 && !text.isEmpty && text == previous && read(column - 1, column) == text
            cells.append(spacer ? "" : text.isEmpty ? " " : text)
            previous = spacer ? "" : text
        }
        return cells
    }

    private func cell(at point: NSPoint) -> TerminalLink.Place? {
        guard let metrics, metrics.cellWidthPixels > 0, metrics.cellHeightPixels > 0 else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        let column = Int(point.x * scale) / Int(metrics.cellWidthPixels)
        let row = Int((bounds.height - point.y) * scale) / Int(metrics.cellHeightPixels)
        guard (0 ..< Int(metrics.columns)).contains(column), (0 ..< Int(metrics.rows)).contains(row) else { return nil }
        return TerminalLink.Place(row: row, column: column)
    }

    func link(at point: NSPoint) -> Hovered? {
        guard let metrics, let cell = cell(at: point) else { return nil }
        let row = cell.row, column = cell.column, columns = Int(metrics.columns), rows = Int(metrics.rows)
        let line = TerminalLink.line(at: row, rows: rows) { cells($0, columns: columns) }
        guard let index = line.places.lastIndex(where: { $0.row == row && $0.column <= column }),
              let link = TerminalLink.at(index, in: line.text)
        else { return nil }
        return Hovered(link: link, places: Array(line.places[link.range]))
    }

    /// Underlines the link under the pointer, one line a row it covers, as Ghostty draws an underline, in the
    /// secondary text color.
    /// Reads the screen again only on another cell. ponytail: output that changes under a still pointer keeps the old
    /// underline until the pointer moves or a key changes.
    func hover(_ point: NSPoint?) {
        let spot = point.flatMap(cell(at:))
        guard spot == nil || spot != hoveredCell else { return }
        hoveredCell = spot
        let found = point.flatMap(link(at:))
        guard found?.link != hovered?.link || found?.places.first != hovered?.places.first else { return }
        hovered = found
        underline?.removeFromSuperlayer()
        underline = nil
        (found == nil && hoveredLink == nil ? NSCursor.arrow : .pointingHand).set()
        guard let found, let metrics, let layer else { return }
        let scale = window?.backingScaleFactor ?? 2
        let cell = CGSize(width: CGFloat(metrics.cellWidthPixels) / scale,
                          height: CGFloat(metrics.cellHeightPixels) / scale)
        let lines = CALayer()
        let stroke = Self.underline(cellHeight: CGFloat(metrics.cellHeightPixels), scale: scale)
        var color: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance { color = NSColor.secondaryLabelColor.cgColor }
        for row in Set(found.places.map(\.row)) {
            let columns = found.places.filter { $0.row == row }.map(\.column)
            let first = columns.min() ?? 0, last = columns.max() ?? 0
            let line = CALayer()
            line.backgroundColor = color
            line.frame = CGRect(x: CGFloat(first) * cell.width,
                                y: bounds.height - CGFloat(row + 1) * cell.height + stroke.bottom / scale,
                                width: CGFloat(last - first + 1) * cell.width, height: stroke.height / scale)
            lines.addSublayer(line)
        }
        layer.addSublayer(lines)
        underline = lines
    }

    /// Ghostty's underline in pixels from a cell's bottom (`font/Metrics.zig`): the font centered in the cell, the
    /// line's top at the font's underline position under the baseline, at least 1 px thick.
    private static func underline(cellHeight: CGFloat, scale: CGFloat) -> (bottom: CGFloat, height: CGFloat) {
        let font = PaneTerminal.font(scale: scale), face = font.ascender - font.descender + font.leading
        let baseline = (font.leading / 2 - font.descender - (cellHeight - face) / 2).rounded()
        let height = max(1, font.underlineThickness.rounded(.up))
        return (max(0, (baseline + font.underlinePosition).rounded() - height), height)
    }

    /// An OSC 8 link libghostty reports: libghostty reports one only while ⌘ is down, so the pointer moves there with
    /// ⌘ for a moment; first off the view, since libghostty looks for links again only on another cell than the last.
    func reported(at event: NSEvent) -> TerminalLink? {
        let point = convert(event.locationInWindow, from: nil), top = bounds.height - point.y
        linkSurface?.sendMousePos(x: -1, y: -1, modifiers: .super_)
        hoveredLink = nil
        linkSurface?.sendMousePos(x: point.x, y: top, modifiers: .super_)
        return hoveredLink.flatMap { TerminalLink.all(in: $0).first }
    }

    /// Under ⌥ or ⌘⌥ libghostty gets ⌘ alone: it draws an OSC 8 link's underline and pointing hand only with ⌘. A
    /// plain move only: libghostty's drags call mouseMoved, and they keep their own modifiers (⌥ makes a selection a
    /// rectangle).
    override func mouseMoved(with event: NSEvent) {
        _ = Self.linkKeys
        let point = convert(event.locationInWindow, from: nil), moved = event.type == .mouseMoved
        let how = moved ? Self.linkKey(event.modifierFlags) : nil
        hover(how == nil ? nil : point)
        guard how == .side || how == .mac else { return super.mouseMoved(with: event) }
        linkSurface?.sendMousePos(x: point.x, y: bounds.height - point.y, modifiers: .super_)
    }

    override func mouseExited(with event: NSEvent) {
        hover(nil)
        super.mouseExited(with: event)
    }

    /// AppKit sends flagsChanged to the first responder only: the card under the pointer may be another.
    static let linkKeys: Any? = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
        let flags = event.modifierFlags
        MainActor.assumeIsolated {
            let shown = underPointer, view = under()
            if shown !== view {
                shown?.hover(nil)
            }
            underPointer = view
            if let view, let window = view.window {
                let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                view.hover(linkKey(flags) == nil || NSEvent.pressedMouseButtons != 0 ? nil : point)
            }
        }
        return event
    }

    private weak static var underPointer: PaneSurfaceView?

    private static func under() -> PaneSurfaceView? {
        let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        guard let window = NSApp.windows.first(where: { $0.windowNumber == number }) else { return nil }
        return window.contentView?.hitTest(window.mouseLocationOutsideOfEventStream) as? PaneSurfaceView
    }

    /// libghostty reports a link again only on another cell, so the pointer leaves the view first. Only on a change to
    /// or from ⌥ or ⌘⌥: made-up moves on every ⇧ or ⌃ would reach a program that tracks the mouse.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let side = [.side, .mac].contains(Self.linkKey(event.modifierFlags))
        defer { sideHeld = side }
        guard side != sideHeld, NSEvent.pressedMouseButtons == 0, let window, Self.under() === self else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let modifiers: TerminalInputModifiers = side ? .super_ : .init(from: event.modifierFlags)
        linkSurface?.sendMousePos(x: -1, y: -1, modifiers: modifiers)
        linkSurface?.sendMousePos(x: point.x, y: bounds.height - point.y, modifiers: modifiers)
    }
}

extension PaneSurfaceView: TerminalSurfaceOpenURLDelegate, TerminalSurfaceHoverLinkDelegate {
    func terminalDidRequestOpenURL(_ url: String, kind _: TerminalOpenURLKind) {
        if let link = TerminalLink.all(in: url).first {
            openLink?(link, .tab)
        } else {
            store()?.show(Notice(text: "Ovvi can't open \(url)", tone: .warning))
        }
    }

    func terminalDidUpdateHoverLink(_ url: String?) {
        hoveredLink = url
        (url == nil && hovered == nil ? NSCursor.arrow : .pointingHand).set()
    }

    override func accessibilityTitle() -> String? {
        hovered?.link.target ?? hoveredLink
    }
}
