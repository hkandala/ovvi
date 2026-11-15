// Draws Ovvi Dev's icon, the AppIconDev set beside AppIcon: Ovvi's own 1024 px icon redrawn as a blueprint, scaled to
// each of AppIcon's sizes. Run from the repo root: swift scripts/dev-icon.swift (make icons runs it).
import AppKit

let source = URL(filePath: "Ovvi/Assets.xcassets/AppIcon.appiconset")
let target = URL(filePath: "Ovvi/Assets.xcassets/AppIconDev.appiconset")

func bitmap(_ side: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// The mark: the 1024 px icon (a tile from 96 to 928 with corners of 184, and three cards) redrawn as a blueprint, as
/// Xcode's beta: a blue tile with a faint grid and the cards in white outline.
func mark() {
    let tile = NSRect(x: 96, y: 96, width: 832, height: 832)
    let blue = NSGradient(
        starting: NSColor(srgbRed: 0.23, green: 0.55, blue: 1, alpha: 1),
        ending: NSColor(srgbRed: 0.08, green: 0.31, blue: 0.78, alpha: 1),
    )!
    NSBezierPath(roundedRect: tile, xRadius: 184, yRadius: 184).addClip()
    blue.draw(in: tile, angle: -90)
    for line in 1 ..< 16 {
        let offset = 96 + CGFloat(line) * 52, width: CGFloat = line % 4 == 0 ? 4 : 2
        NSColor(white: 1, alpha: line % 4 == 0 ? 0.22 : 0.1).setFill()
        NSRect(x: offset - width / 2, y: 96, width: width, height: 832).fill()
        NSRect(x: 96, y: offset - width / 2, width: 832, height: width).fill()
    }
    let cards = [
        (NSRect(x: 254, y: 477, width: 372, height: 258), 0.1),
        (NSRect(x: 329, y: 385, width: 372, height: 262), 0.2),
        (NSRect(x: 400, y: 293, width: 374, height: 265), 0.34),
    ]
    for (card, fill) in cards {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: card, xRadius: 40, yRadius: 40).addClip()
        blue.draw(in: tile, angle: -90)
        NSColor(white: 1, alpha: fill).setFill()
        card.fill()
        NSGraphicsContext.restoreGraphicsState()
        let outline = NSBezierPath(roundedRect: card.insetBy(dx: 8, dy: 8), xRadius: 32, yRadius: 32)
        outline.lineWidth = 16
        NSColor.white.setStroke()
        outline.stroke()
    }
}

guard let original = NSImage(contentsOf: source.appending(path: "icon_512x512@2x.png")) else {
    throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: source.path])
}

let marked = NSImage(size: NSSize(width: 1024, height: 1024))
marked.addRepresentation(bitmap(1024) {
    original.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    mark()
})
try? FileManager.default.removeItem(at: target)
try FileManager.default.copyItem(at: source, to: target)
for name in try FileManager.default.contentsOfDirectory(atPath: target.path) where name.hasSuffix(".png") {
    guard let side = NSImageRep(contentsOf: target.appending(path: name))?.pixelsWide else { continue }
    let rep = bitmap(side) { marked.draw(in: NSRect(x: 0, y: 0, width: side, height: side)) }
    try rep.representation(using: .png, properties: [:])?.write(to: target.appending(path: name))
}
