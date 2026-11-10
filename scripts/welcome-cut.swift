// Cuts a 2x screenshot into one HEIC piece: `swift welcome-cut.swift <in.png> <x> <y> <width> <height> <out.heic>`,
// the frame in points. (sips's crop shifts by a pixel at the left edge.)
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
let frame = arguments[2 ... 5].compactMap { Double($0) }.map { CGFloat($0 * 2) }
guard frame.count == 4, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let piece = image.cropping(to: CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])),
      let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[6]) as CFURL,
                                                "public.heic" as CFString, 1, nil)
else { fatalError("usage: welcome-cut.swift <in.png> <x> <y> <width> <height> <out.heic>") }
CGImageDestinationAddImage(out, piece, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
guard CGImageDestinationFinalize(out) else { fatalError("could not write \(arguments[6])") }
