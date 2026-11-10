// Lists the windows of a pid: id, x, y, width, height (points), layer, name.
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1]) ?? 0
let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
for window in list where window[kCGWindowOwnerPID as String] as? Int == pid {
    let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
        .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
    let values: [Any] = [window[kCGWindowNumber as String] ?? 0, Int(bounds.minX), Int(bounds.minY), Int(bounds.width),
                         Int(bounds.height), window[kCGWindowLayer as String] ?? 0,
                         window[kCGWindowName as String] ?? ""]
    print(values.map { "\($0)" }.joined(separator: " "))
}
