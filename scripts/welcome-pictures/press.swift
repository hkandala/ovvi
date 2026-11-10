// Presses the app's menu item or button with the title given, through accessibility (no events): `press.swift <pid>
// <title>`. A menu that is open shows its items in the app's tree.
import ApplicationServices
import Foundation

let pid = pid_t(CommandLine.arguments[1]) ?? 0, title = CommandLine.arguments[2]

func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
    if value(element, kAXTitleAttribute) as? String == title {
        return element
    }
    guard depth < 40 else { return nil }
    for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = find(child, depth: depth + 1) {
            return found
        }
    }
    return nil
}

guard let item = find(AXUIElementCreateApplication(pid), depth: 0) else {
    FileHandle.standardError.write(Data("no \(title)\n".utf8))
    exit(1)
}

exit(AXUIElementPerformAction(item, kAXPressAction as CFString) == .success ? 0 : 1)
