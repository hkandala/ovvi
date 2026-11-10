// A trackpad pinch: the pointer to x y (screen points, top left), then a magnify gesture that begins, changes by
// `step` (0.1 is 10 % larger) `steps` times 16 ms apart and ends, as a trackpad sends.
// Usage: pinch <x> <y> <step> <steps>
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard args.count == 4 else { fatalError("usage: pinch <x> <y> <step> <steps>") }
let point = CGPoint(x: args[0], y: args[1])

onlyIntoTheApp([point])

/// A gesture event (type 29) of HID type zoom (8) with its magnification (field 113) and phase (field 132: 1 began, 2
/// changed, 4 ended).
func post(_ phase: Int64, _ magnification: Double) {
    guard let event = CGEvent(source: nil), let type = CGEventType(rawValue: 29) else { fatalError("no gesture event") }
    event.type = type
    event.location = point
    event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8)
    event.setDoubleValueField(CGEventField(rawValue: 113)!, value: magnification)
    event.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
    event.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.016)
}

warp(to: point)
post(1, 0)
for _ in 0 ..< Int(args[3]) {
    post(2, args[2])
}

post(4, 0)
