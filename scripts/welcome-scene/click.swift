// Clicks at x y (screen points), only inside the app's window (OVVI_APP_PID), then puts the pointer back.
let numbers = CommandLine.arguments.dropFirst().compactMap { Double($0) }
let point = CGPoint(x: numbers[0], y: numbers[1])
onlyIntoTheApp([point])
let back = CGEvent(source: nil)?.location ?? point
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGWarpMouseCursorPosition(point)
    Thread.sleep(forTimeInterval: 0.1)
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

Thread.sleep(forTimeInterval: 0.15)
CGWarpMouseCursorPosition(back)
