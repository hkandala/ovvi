import AppKit
import SwiftUI

/// A `RowTable` row: its header, the accent pill when lit, a light fill under the pointer, then a symbol or a program
/// tile, the title, the note, the detail or › and the keycaps, placed as `MenuRow` lays them out. For accessibility
/// the header and the row are two elements, as SwiftUI's were.
final class RowView: NSView {
    static let id = NSUserInterfaceItemIdentifier("row")
    private var act: () -> Void = {}
    private var hover: () -> Void = {}
    private var item: FilterList.Item?
    private var header: String?
    private var first = false
    private var lit = false
    private var height: CGFloat = 32
    private var gap: CGFloat = 0
    private var hovered = false
    private var pressed = false
    private var symbol: NSImage?
    private let headerView = NSView()
    private let press = Press()
    private static let title = NSFont.systemFont(ofSize: 13), note = NSFont.systemFont(ofSize: 12)
    private static let headerFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let cap = NSFont.systemFont(ofSize: 10, weight: .semibold)

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways,
                                                              .inVisibleRect], owner: self))
        setAccessibilityElement(false)
        headerView.setAccessibilityElement(true)
        headerView.setAccessibilityRole(.staticText)
        press.setAccessibilityElement(true)
        press.setAccessibilityRole(.button)
        addSubview(headerView)
        addSubview(press)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func show(_ table: RowTable, _ row: Int) {
        let item = table.items[row]
        (self.item, header, first, lit) = (item, RowTable.header(table.items, row), row == 0, row == table.lit)
        (height, gap) = (table.rowHeight, row < table.items.count - 1 ? RowTable.spacing : table.inset)
        act = { table.act(item) }
        hover = { table.hover(item) }
        symbol = item.pane?.iconID ?? item.program == nil ? item.symbol.flatMap(NSImage.symbol)
            .map { image in
                let image = image.withSymbolConfiguration(.init(pointSize: 13, weight: .regular, scale: .medium))
                    ?? image
                let tint = lit ? RowInk.white(1) : RowInk.primary
                return NSImage(size: image.size, flipped: false) { bounds in
                    image.draw(in: bounds)
                    tint.set()
                    bounds.fill(using: .sourceAtop)
                    return true
                }
            } : nil
        press.setAccessibilityIdentifier("\(table.name).\(item.id)")
        press.setAccessibilityLabel([item.title, item.detail, item.keys.joined()].filter { !$0.isEmpty }
            .joined(separator: ", "))
        press.setAccessibilityValue(item.note ?? "")
        press.setAccessibilitySelected(lit)
        press.act = act
        press.isHidden = false
        headerView.isHidden = header == nil
        headerView.setAccessibilityIdentifier(header.map { "\(table.name).section.\($0)" })
        headerView.setAccessibilityLabel(header)
        needsLayout = true
        needsDisplay = true
    }

    /// Out of the table, kept for reuse: no element for a test or VoiceOver to find, no pointer on it.
    func removed() {
        (press.isHidden, headerView.isHidden, hovered, pressed) = (true, true, false, false)
    }

    /// The row under its header, above the gap to the next (the list's inset after the last).
    private var rowRect: NSRect {
        NSRect(x: 0, y: bounds.height - gap - height, width: bounds.width, height: height)
    }

    override func layout() {
        super.layout()
        headerView.frame = NSRect(x: 8, y: 0, width: bounds.width - 16, height: rowRect.minY)
        press.frame = rowRect
    }

    override func draw(_: NSRect) {
        guard let item else { return }
        if let header {
            let font = Self.headerFont, line = font.ascender - font.descender + font.leading
            (header as NSString).draw(at: NSPoint(x: 8, y: pixel((first ? 0 : 6) + (RowTable.headerHeight - line) / 2)),
                                      withAttributes: [.font: font, .foregroundColor: RowInk.secondary])
        }
        let row = rowRect
        if lit || hovered || pressed {
            (lit ? NSColor(Color.accentColor) : RowInk.primary.withAlphaComponent(pressed ? 0.08 : 0.05)).setFill()
            NSBezierPath(cgPath: Path(roundedRect: row, cornerRadius: 8, style: .continuous).cgPath).fill()
        }
        // The tile at the window's scale, read as it draws: a row is made before it is in a window.
        let icon = (item.pane?.iconID ?? item.program).flatMap {
            Tile.image($0, letter: item.pane?.letter, scale: window?.backingScaleFactor ?? 2)
        } ?? symbol
        if let icon {
            icon.draw(in: NSRect(x: pixel(row.minX + 8 + (22 - icon.size.width) / 2),
                                 y: pixel(row.midY - icon.size.height / 2), width: icon.size.width,
                                 height: icon.size.height))
        }
        var end = row.maxX - 8
        for key in item.keys.reversed() {
            let size = (key as NSString).size(withAttributes: [.font: Self.cap])
            let width = max(10, size.width) + 8, height = size.height + 2
            end -= width
            drawCap(key, in: NSRect(x: pixel(end), y: pixel(row.midY - height / 2), width: width, height: height))
            end -= 3
        }
        drawTexts(item, in: row, end: item.keys.isEmpty ? end : end + 3 - 8)
    }

    /// The title takes the room it needs first, as `MenuRow`'s; the note and the detail get what is left.
    private func drawTexts(_ item: FilterList.Item, in row: NSRect, end: CGFloat) {
        let start = row.minX + 8 + 22 + 8
        let detail = [item.detail, item.opens ? "›" : ""].filter { !$0.isEmpty }.joined(separator: " ")
        let title: [NSAttributedString.Key: Any] = [.font: Self.title,
                                                    .foregroundColor: lit ? RowInk.white(1) : RowInk.primary]
        let titleRoom = min(width(item.title, title),
                            end - start - 4 - (item.note == nil ? 0 : 8) - (detail.isEmpty ? 0 : 8))
        draw(item.title, title, left: start, room: titleRoom, in: row)
        var left = start + max(0, titleRoom)
        if let note = item.note {
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.note,
                                                             .foregroundColor: lit ? RowInk.white(0.6) : RowInk
                                                                 .tertiary]
            let room = min(width(note, attributes), end - left - 8 - 4)
            draw(note, attributes, left: left + 8, room: room, in: row)
            left += 8 + max(0, room)
        }
        if !detail.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.title,
                                                             .foregroundColor: lit ? RowInk.white(0.75) : RowInk
                                                                 .secondary]
            let room = min(width(detail, attributes), end - left - 4)
            draw(detail, attributes, left: end - max(0, room), room: room, in: row)
        }
    }

    /// One line at `left` on the pixel grid, centered in the row's height; cut in its middle when the room is less
    /// than it needs.
    private func draw(_ text: String, _ attributes: [NSAttributedString.Key: Any], left: CGFloat, room: CGFloat,
                      in row: NSRect)
    {
        guard room > 0 else { return }
        let font = attributes[.font] as? NSFont ?? Self.title
        let line = ceil(font.ascender - font.descender + font.leading), needed = width(text, attributes)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        var attributes = attributes
        attributes[.paragraphStyle] = style
        (text as NSString).draw(with: NSRect(x: pixel(left), y: (row.midY - line / 2).rounded(),
                                             width: room < needed ? room : needed + 2, height: line),
                                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    /// A keycap as `Keycap` draws it on the palette's glass, drawn: a glass view per keycap took most of a key's time.
    private func drawCap(_ key: String, in rect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let shape = { (inset: CGFloat) in
            NSBezierPath(cgPath: Path(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: 4 - inset,
                                      style: .continuous).cgPath)
        }
        let cap = RowInk.cap(dark: dark, lit: lit)
        cap.fill.setFill()
        shape(0).fill()
        // The rim is brightest at the top and the bottom, as the glass lights it.
        for (band, alpha) in cap.rim.enumerated() {
            let edge = RowInk.white(alpha), side = RowInk.white(alpha * cap.sides)
            let ring = shape(CGFloat(band) * 0.5 + 0.25)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(cgPath: ring.cgPath.copy(strokingWithWidth: 0.5, lineCap: .butt, lineJoin: .round,
                                                  miterLimit: 1)).setClip()
            NSGradient(colors: [edge, side, side, edge], atLocations: [0, 0.35, 0.65, 1], colorSpace: .sRGB)?
                .draw(in: rect, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }
        if let outline = cap.outline {
            let edge = shape(-0.25)
            edge.lineWidth = 0.5
            outline.setStroke()
            edge.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.cap,
                                                         .foregroundColor: lit ? RowInk.white(1) : RowInk.primary]
        let size = (key as NSString).size(withAttributes: attributes)
        (key as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                               withAttributes: attributes)
    }

    private func width(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }

    /// On the pixel grid, as SwiftUI places its views.
    private func pixel(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? 2
        return (value * scale).rounded() / scale
    }

    /// Only the row lights, not its header nor the gap after it.
    private func point(_ event: NSEvent) {
        let over = rowRect.contains(convert(event.locationInWindow, from: nil))
        if over != hovered {
            hovered = over
            needsDisplay = true
        }
        if over {
            hover()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        point(event)
    }

    override func mouseMoved(with event: NSEvent) {
        point(event)
    }

    override func mouseExited(with _: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = rowRect.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let acts = pressed && rowRect.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if acts {
            act()
        }
    }

    /// The row's element, as the SwiftUI button was. Its clicks go on to the row, its next responder.
    private final class Press: NSView {
        var act: () -> Void = {}

        override func accessibilityPerformPress() -> Bool {
            act()
            return true
        }
    }
}

/// Program tiles as images, made once per icon and scale by SwiftUI's own `ProgramTile`.
@MainActor
private enum Tile {
    private static var images: [String: NSImage] = [:]

    static func image(_ icon: String, letter: String?, scale: CGFloat) -> NSImage? {
        let key = "\(icon) \(letter ?? "") \(scale)"
        if let image = images[key] {
            return image
        }
        let renderer = ImageRenderer(content: ProgramTile(icon: icon, letter: letter).environment(
            \.displayScale,
            scale,
        ))
        renderer.scale = scale
        let image = renderer.nsImage
        images[key] = image
        return image
    }
}
