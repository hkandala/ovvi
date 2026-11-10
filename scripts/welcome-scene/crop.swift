// Keeps the bottom <height> pixel rows of a PNG, in place: `crop <file> <height>`. A menu open from the title row
// makes the window's picture taller at its top.
import Foundation
import ImageIO
import UniformTypeIdentifiers

let url = URL(filePath: CommandLine.arguments[1]), height = Int(CommandLine.arguments[2]) ?? 0
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.height > height,
      let cropped = image.cropping(to: CGRect(x: 0, y: image.height - height, width: image.width, height: height)),
      let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(0) }
CGImageDestinationAddImage(out, cropped, CGImageSourceCopyPropertiesAtIndex(source, 0, nil))
exit(CGImageDestinationFinalize(out) ? 0 : 1)
