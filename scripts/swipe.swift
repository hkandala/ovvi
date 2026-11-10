// A two-finger trackpad swipe at x y (screen points, top left): a scroll that begins, moves `step` pt sideways `steps`
// times 16 ms apart and ends, then momentum that decays for about 0.6 s, as a trackpad sends. With `pause` ms, the
// fingers rest that long ahead of the lift, and an empty momentum follows at once. With `vertical` 1, the scroll goes
// up or down. With `option` 1, ⌥ is held. Posted to the HID system: the sandboxed UI test runner cannot post events,
// and the app takes scrolls posted to its pid without scrolling.
// Usage: swipe <x> <y> <step> <steps> [pause [vertical [option]]]
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard args.count >= 4 else { fatalError("usage: swipe <x> <y> <step> <steps> [pause [vertical [option]]]") }
let point = CGPoint(x: args[0], y: args[1]), steps = Int(args[3]), pause = args.count > 4 ? args[4] / 1000 : 0
let vertical = args.count > 5 && args[5] == 1, option = args.count > 6 && args[6] == 1

onlyIntoTheApp([point])

func post(_ delta: Double, _ field: CGEventField, _ phase: Int64, wait: Bool = true) {
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: vertical ? Int32(delta.rounded()) : 0,
                              wheel2: vertical ? 0 : Int32(delta.rounded()), wheel3: 0) else { return }
    event.setIntegerValueField(field, value: phase)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.flags = option ? .maskAlternate : []
    event.location = point
    event.post(tap: .cghidEventTap)
    if wait {
        Thread.sleep(forTimeInterval: 0.016)
    }
}

warp(to: point)
// kCGScrollPhaseBegan, Changed, Ended; then kCGMomentumScrollPhaseBegin, Continue, End.
post(0, .scrollWheelEventScrollPhase, 1)
for _ in 0 ..< steps {
    post(args[2], .scrollWheelEventScrollPhase, 2)
}

Thread.sleep(forTimeInterval: pause)
// Fingers that rested lift with an empty momentum right after, as a trackpad's: with none, AppKit goes on at the last
// moves' speed for about 9 pt.
post(0, .scrollWheelEventScrollPhase, 4, wait: pause == 0)
let count = pause > 0 ? 2 : 41
for index in 0 ..< count {
    post(pause > 0 ? 0 : args[2] * pow(0.9, Double(index)), .scrollWheelEventMomentumPhase,
         index == 0 ? 1 : index == count - 1 ? 3 : 2)
}
