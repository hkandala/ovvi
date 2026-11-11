// A file's icon in a window of its own, dragged from x y to tx ty (screen points, top left): a drag from Finder
// sometimes starts nothing on CI. Exits 0 when a drop took the file, 1 when the drop is refused, 2 when no drag begins
// within 5 s or ends within 10 s. A path `text:<text>` drags that text instead.
// Usage: file-drag <path> <x> <y> <tx> <ty>
import AppKit

let args = CommandLine.arguments.dropFirst(2).compactMap { Double($0) }
guard args.count == 4 else { fatalError("usage: file-drag <path> <x> <y> <tx> <ty>") }
let url = URL(filePath: CommandLine.arguments[1])
let text = CommandLine.arguments[1].hasPrefix("text:") ? String(CommandLine.arguments[1].dropFirst(5)) : nil
let start = CGPoint(x: args[0], y: args[1]), end = CGPoint(x: args[2], y: args[3])

// Ahead of its own window, which covers the start.
onlyIntoTheApp([start, end])
let began = DispatchSemaphore(value: 0)

final class Source: NSView, NSDraggingSource {
    private var dragging = false

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: text.map { $0 as NSString } ?? url as NSURL)
        item.setDraggingFrame(bounds, contents: layer?.contents)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_: NSDraggingSession, willBeginAt _: NSPoint) {
        began.signal()
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
        exit(operation.isEmpty ? 1 : 0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let height = NSScreen.screens[0].frame.height, size = 64.0
let panel = NSPanel(
    contentRect: NSRect(x: args[0] - size / 2, y: height - args[1] - size / 2, width: size, height: size),
    // The app under test stays active.
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false,
)
panel.level = .floating
let source = Source()
source.wantsLayer = true
source.layer?.contents = text == nil ? NSWorkspace.shared.icon(forFile: url.path)
    : NSWorkspace.shared.icon(for: .plainText)
panel.contentView = source
panel.orderFrontRegardless()

/// `orderFrontRegardless` returns ahead of the window server showing the panel, and a press then lands on Ovvi's
/// window. On a busy runner a drag session can begin after a release posted on a timer, and then it never ends.
func drag() {
    warp(to: start)
    post(.leftMouseDown, start)
    Thread.sleep(forTimeInterval: 0.3)
    post(.leftMouseDragged, CGPoint(x: start.x + 8, y: start.y))
    guard began.wait(timeout: .now() + 5) == .success else {
        // Not left down for every app.
        post(.leftMouseUp, start)
        fputs("no drag began: the press did not start one\n", stderr)
        exit(2)
    }
    glide(from: start, to: end)
    Thread.sleep(forTimeInterval: 0.5)
    post(.leftMouseUp, end)
}

var pressed = false

func pressWhenShown() {
    let shown = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
        .contains { $0[kCGWindowNumber as String] as? Int == panel.windowNumber }
    guard shown else { return DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: pressWhenShown) }
    pressed = true
    Thread.detachNewThread(drag)
}

DispatchQueue.main.async(execute: pressWhenShown)

DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    // Which part waited: the window server showing the panel, or the drag after the press.
    fputs("no drag ended (\(pressed ? "pressed" : "its window never showed"))\n", stderr)
    exit(2)
}

app.run()
