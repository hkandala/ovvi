// Marks a built Ovvi Dev.app: Ovvi's own 1024 px icon with the mark below, scaled to each size as the bundle's
// AppIcon.icns, then signs the app again (ad hoc).
// Usage: swift scripts/dev-icon.swift <AppIcon.appiconset> <app>
import AppKit

let args = CommandLine.arguments
let source = URL(filePath: args[1]), app = URL(filePath: args[2])
let iconset = FileManager.default.temporaryDirectory.appending(path: "ovvi-dev-\(getpid()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func run(_ argv: String...) throws {
    let process = try Process.run(URL(filePath: argv[0]), arguments: Array(argv.dropFirst()))
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad, userInfo: ["argv": argv]) }
}

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
// The catalog's own names and sizes, as iconutil wants them.
for name in try FileManager.default.contentsOfDirectory(atPath: source.path) where name.hasSuffix(".png") {
    guard let side = NSImageRep(contentsOf: source.appending(path: name))?.pixelsWide else { continue }
    let rep = bitmap(side) { marked.draw(in: NSRect(x: 0, y: 0, width: side, height: side)) }
    try rep.representation(using: .png, properties: [:])?.write(to: iconset.appending(path: name))
}

let contents = app.appending(path: "Contents")
try run("/usr/bin/iconutil", "-c", "icns", "-o", contents.appending(path: "Resources/AppIcon.icns").path, iconset.path)
// Without the asset catalog's icon name, macOS takes the bundle's .icns.
try? run("/usr/libexec/PlistBuddy", "-c", "Delete :CFBundleIconName", contents.appending(path: "Info.plist").path)
try run("/usr/bin/codesign", "--force", "--sign", "-", "--preserve-metadata=entitlements,flags", app.path)
