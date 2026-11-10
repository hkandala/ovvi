// A mouse drag through several points (screen points, top left), holding at each for its seconds: XCUITest drags to
// one point only. A negative hold prints "held" and holds until a line on stdin (at most 30 s).
// Usage: drag <x> <y> (<x> <y> <hold>)...
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard args.count >= 5, (args.count - 2) % 3 == 0 else { fatalError("usage: drag <x> <y> (<x> <y> <hold>)...") }
let start = CGPoint(x: args[0], y: args[1])
let points = [start] + stride(from: 2, to: args.count, by: 3).map { CGPoint(x: args[$0], y: args[$0 + 1]) }

onlyIntoTheApp(points)

warp(to: start)
post(.leftMouseDown, start)
Thread.sleep(forTimeInterval: 0.3)
var point = start
for index in stride(from: 2, to: args.count, by: 3) {
    let next = CGPoint(x: args[index], y: args[index + 1])
    glide(from: point, to: next)
    point = next
    if args[index + 2] < 0 {
        print("held")
        fflush(stdout)
        // At most 30 s: not left down for every app when no line comes.
        var input = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
        _ = poll(&input, 1, 30000)
    } else {
        Thread.sleep(forTimeInterval: args[index + 2])
    }
}

post(.leftMouseUp, point)
