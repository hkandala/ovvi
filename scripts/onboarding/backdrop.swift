// A plain color behind the scene's window while record-onboarding.sh films it: the window's glass blurs whatever is
// under it, so the clips show it as on a plain black (dark) or white (light) desktop. A borderless window a little
// larger than the scene's (its blur reaches past its edge), under the app's windows, until killed: the recorder shows
// it only while a film runs, and it goes by itself after BACKDROP_MAX_SECONDS (default 75) in any case. The films take
// the app's windows and this one. Usage: backdrop <black|white> <window id>
// x y w h (the scene window's number and frame in screen points, top left origin): it goes right under that window.
import AppKit

let arguments = CommandLine.arguments
let numbers = arguments.dropFirst(3).compactMap { Double($0) }
guard arguments.count == 7, let above = Int(arguments[2]), numbers.count == 4,
      let screen = NSScreen.screens.first?.frame
else {
    FileHandle.standardError.write(Data("usage: backdrop <black|white> <window id> x y w h\n".utf8))
    exit(2)
}

let margin = 80.0
let frame = NSRect(x: numbers[0] - margin, y: screen.height - numbers[1] - numbers[3] - margin,
                   width: numbers[2] + 2 * margin, height: numbers[3] + 2 * margin)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.backgroundColor = arguments[1] == "white" ? .white : .black
window.hasShadow = false
window.ignoresMouseEvents = true
// Right under the scene's window, over every other: in front of the app's window, it took the clicks meant for it.
window.order(.below, relativeTo: above)
print("shown")
fflush(stdout)
let limit = Double(ProcessInfo.processInfo.environment["BACKDROP_MAX_SECONDS"] ?? "") ?? 75
DispatchQueue.main.asyncAfter(deadline: .now() + limit) { exit(0) }
app.run()
