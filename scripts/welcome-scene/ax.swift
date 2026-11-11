// The scene's window, read and placed through accessibility (no events): `ax.swift <pid> window [x y w h]` prints the
// main window's id and frame, after moving it when a frame is given; `screen` prints the main display's size; `close`
// closes the app's other windows; `front` brings the app in front; `park` moves the pointer off it; `find <id>` prints
// the screen frame of each element with that accessibility identifier (a prefix with a trailing `*`, or
// `title:<title>` for a button or a menu's item); `set <text>` puts text in the focused field, as typing leaves it.
import ApplicationServices
import Foundation

let arguments = CommandLine.arguments
let pid = pid_t(arguments[1])!
let app = AXUIElementCreateApplication(pid)

func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute) else {
        return nil
    }
    var point = CGPoint.zero, extent = CGSize.zero
    // Both are AXValues: the attributes' type.
    AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
    AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

func show(_ rect: CGRect) -> String {
    "\(Int(rect.minX)) \(Int(rect.minY)) \(Int(rect.width)) \(Int(rect.height))"
}

/// The largest normal window of the pid, by the window server's list (its number is screencapture's id).
func mainWindow() -> (id: Int, frame: CGRect)? {
    let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { window -> (Int, CGRect)? in
        guard window[kCGWindowOwnerPID as String] as? Int32 == pid, window[kCGWindowLayer as String] as? Int == 0,
              let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                  .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }), bounds.width > 400
        else { return nil }
        return (window[kCGWindowNumber as String] as? Int ?? 0, bounds)
    }.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }
}

switch arguments[2] {
case "front":
    // In front, so clicks reach it: a launch behind the app in front stays behind on macOS 26.
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    if let window = (value(app, kAXWindowsAttribute) as? [AXUIElement])?.first {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    Thread.sleep(forTimeInterval: 0.3)
case "screen":
    let bounds = CGDisplayBounds(CGMainDisplayID())
    print(Int(bounds.width), Int(bounds.height))
case "close":
    // Every window of the app but its largest (Settings, say).
    let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    let largest = windows.max { (frame($0)?.width ?? 0) < (frame($1)?.width ?? 0) }
    for window in windows where window != largest {
        if let button = value(window, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(unsafeBitCast(button, to: AXUIElement.self), kAXPressAction as CFString)
        }
    }
case "park":
    // The pointer off the window, so no hover shows in a picture: the menu bar's empty middle.
    CGWarpMouseCursorPosition(CGPoint(x: 900, y: 4))
case "window":
    if arguments.count >= 7, let window = (value(app, kAXWindowsAttribute) as? [AXUIElement])?
        .max(by: { (frame($0)?.width ?? 0) < (frame($1)?.width ?? 0) })
    {
        let numbers = arguments[3 ... 6].compactMap { Double($0) }
        var point = CGPoint(x: numbers[0], y: numbers[1]), size = CGSize(width: numbers[2], height: numbers[3])
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        Thread.sleep(forTimeInterval: 0.5)
    }
    guard let window = mainWindow() else { exit(1) }
    print(window.id, show(window.frame))
case "find":
    let wanted = arguments[3]
    func matches(_ element: AXUIElement) -> String? {
        if wanted.hasPrefix("title:") {
            // One word: callers split the line at spaces.
            let title = String(wanted.dropFirst(6))
            return [kAXTitleAttribute, kAXDescriptionAttribute].contains { value(element, $0) as? String == title }
                ? "title" : nil
        }
        guard let id = value(element, kAXIdentifierAttribute) as? String else { return nil }
        return (wanted.hasSuffix("*") ? id.hasPrefix(wanted.dropLast()) : id == wanted) ? id : nil
    }
    func walk(_ element: AXUIElement, depth: Int) {
        if let id = matches(element), let rect = frame(element) {
            print(id, show(rect), value(element, kAXValueAttribute) as? String ?? "")
        }
        guard depth < 60 else { return }
        for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            walk(child, depth: depth + 1)
        }
    }
    walk(app, depth: 0)
case "set":
    // The focused field: no walk of the tree, which holds the app's main thread while a film runs.
    guard let focused = value(app, kAXFocusedUIElementAttribute),
          AXUIElementSetAttributeValue(unsafeBitCast(focused, to: AXUIElement.self), kAXValueAttribute as CFString,
                                       arguments[3] as CFString) == .success
    else { exit(1) }
default:
    exit(2)
}
