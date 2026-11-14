// Marks a built Ovvi Tip.app: Ovvi's own icon at each size with an orange DEV badge, as the bundle's AppIcon.icns,
// then signs the app again (ad hoc). Usage: swift scripts/tip-icon.swift <AppIcon.appiconset> <app>
import AppKit

let args = CommandLine.arguments
let source = URL(filePath: args[1]), app = URL(filePath: args[2])
let iconset = FileManager.default.temporaryDirectory.appending(path: "ovvi-tip-\(getpid()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func run(_ argv: String...) throws {
    let process = try Process.run(URL(filePath: argv[0]), arguments: Array(argv.dropFirst()))
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad, userInfo: ["argv": argv]) }
}

for name in try FileManager.default.contentsOfDirectory(atPath: source.path) where name.hasSuffix(".png") {
    guard let image = NSImage(contentsOf: source.appending(path: name)),
          let bitmap = image.representations.first.flatMap({ NSBitmapImageRep(
              bitmapDataPlanes: nil, pixelsWide: $0.pixelsWide, pixelsHigh: $0.pixelsHigh, bitsPerSample: 8,
              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
              bitsPerPixel: 0,
          ) })
    else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: name]) }
    let side = CGFloat(bitmap.pixelsWide)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    // The artwork's tile spans 96 to 928 of 1024: the badge sits on its bottom edge, right of center.
    let badge = NSRect(x: side * 0.5, y: side * 0.06, width: side * 0.4, height: side * 0.17)
    NSColor(srgbRed: 1, green: 0.58, blue: 0.04, alpha: 1).setFill()
    NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2).fill()
    if side >= 64 {
        let font = NSFont.systemFont(ofSize: badge.height * 0.62, weight: .heavy)
        let text = NSAttributedString(string: "DEV", attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = text.size()
        text.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])?.write(to: iconset.appending(path: name))
}

let contents = app.appending(path: "Contents")
try run("/usr/bin/iconutil", "-c", "icns", "-o", contents.appending(path: "Resources/AppIcon.icns").path, iconset.path)
// Without the asset catalog's icon name, macOS takes the bundle's .icns.
try? run("/usr/libexec/PlistBuddy", "-c", "Delete :CFBundleIconName", contents.appending(path: "Info.plist").path)
try run("/usr/bin/codesign", "--force", "--sign", "-", "--preserve-metadata=entitlements,flags", app.path)
