// Writes a PNG as HEIC through ImageIO, keeping its alpha (sips drops it: a window's round corners), and keeps only
// its bottom <rows> when given (a capture with a menu open over the title row is taller, above the window).
// Usage: welcome-heic in.png out.heic quality [rows]
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 4, let quality = Double(arguments[3]),
      let source = CGImageSourceCreateWithURL(URL(filePath: arguments[1]) as CFURL, nil),
      let full = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let destination = CGImageDestinationCreateWithURL(URL(filePath: arguments[2]) as CFURL,
                                                        UTType.heic.identifier as CFString, 1, nil)
else { fatalError("usage: welcome-heic in.png out.heic quality [rows]") }
let rows = arguments.count > 4 ? Int(arguments[4]) ?? full.height : full.height
guard let image = full.cropping(to: CGRect(x: 0, y: full.height - rows, width: full.width, height: rows)) else {
    fatalError("cannot crop \(arguments[1])")
}

CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(arguments[2])") }
