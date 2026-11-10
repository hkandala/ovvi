import AppKit
import GhosttyTerminal
import HerdrKit
import SwiftUI

enum Links {
    struct Target {
        let plugin: PluginManifest, arg: String, line: String?
    }

    static func trimmed(_ text: String) -> String {
        var text = Substring(text)
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        func unopened(_ last: Character) -> Bool {
            let closes = text.count(where: { $0 == last })
            if let open = pairs[last] {
                return text.count(where: { $0 == open }) < closes
            }
            return "\"'".contains(last) && closes % 2 == 1
        }
        while let last = text.last, ".,;:!?".contains(last) || unopened(last) {
            text.removeLast()
        }
        return String(text)
    }

    private static func target(_ text: String, store: HostStore, cwd: String) async -> Target? {
        let url = URL(string: text), scheme = Self.scheme(text)
        if scheme != nil, url?.isWebAddress == true {
            return Registry.openers(for: text).first.map { Target(plugin: $0, arg: text, line: nil) }
        }
        guard scheme == nil || scheme == "file" else { return nil }
        var path = scheme == "file" ? url?.path ?? "" : text
        let line = path.firstMatch(of: lineSuffix)
        if let line {
            path = String(path[..<line.range.lowerBound])
        }
        guard !path.isEmpty, let found = await store.there(path, from: cwd) else { return nil }
        let landing = line.map { String($0.1) }
        if !store.machine.isRemote, !found.hasSuffix("/"),
           ["html", "htm"].contains(URL(filePath: found).pathExtension.lowercased())
        {
            return Target(plugin: Registry.browser, arg: URL(filePath: found).absoluteString, line: nil)
        }
        return Registry.openers(for: found).first.map { Target(plugin: $0, arg: found, line: landing) }
    }

    private static let lineSuffix = /:(\d+)(?::\d+)?$/

    /// A link's scheme, only with `://`: `notes.md:12` is a path and its line.
    private static func scheme(_ text: String) -> String? {
        text.contains("://") ? URL(string: text)?.scheme?.lowercased() : nil
    }

    /// False for one that opens nothing for sure: a ⌥-click on it is the program's.
    static func open(_ text: String, how: Opening, from terminalID: String, page: Page?) -> Bool {
        guard let page else { return false }
        let text = trimmed(text), named = file(text)
        let cwd = page.store.terminalPane(terminalID)?.cwd ?? "/"
        guard named != nil || likely(text, remote: page.store.machine.isRemote, cwd: cwd) else { return false }
        Task {
            guard let target = await target(text, store: page.store, cwd: cwd) else {
                if let named {
                    page.store.notFound(named)
                }
                return
            }
            await page.open(target.plugin, arg: target.arg, at: target.line, from: terminalID, how: how,
                            background: true)
        }
        return true
    }

    private static func file(_ text: String) -> String? {
        let scheme = scheme(text), path = text.replacing(lineSuffix, with: "")
        if scheme == "file" {
            return URL(string: path)?.path
        }
        guard scheme == nil, path.hasPrefix("/") || path.hasPrefix("~/"), !(path as NSString).pathExtension.isEmpty
        else { return nil }
        return path
    }

    private static func likely(_ text: String, remote: Bool, cwd: String) -> Bool {
        let scheme = scheme(text)
        if scheme != nil && URL(string: text)?.isWebAddress == true || remote && scheme == nil {
            return true
        }
        guard scheme == nil else { return scheme == "file" }
        let path = (text.replacing(lineSuffix, with: "") as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: path.hasPrefix("/") ? path : "\(cwd)/\(path)")
    }
}

extension PaneSurfaceView {
    /// libghostty reports a link only while ⌘ is down, so the pointer moves there with ⌘ for a moment; first off the
    /// view, since libghostty looks for links again only on another cell than the last.
    func link(at event: NSEvent) -> String? {
        let point = convert(event.locationInWindow, from: nil), top = bounds.height - point.y
        linkSurface?.sendMousePos(x: -1, y: -1, modifiers: .super_)
        hoveredLink = nil
        linkSurface?.sendMousePos(x: point.x, y: top, modifiers: .super_)
        return hoveredLink
    }

    static func sideKey(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .control, .option, .shift]) == .option
    }

    /// Under ⌥ alone libghostty gets ⌘: it draws a link's underline and pointing hand only with ⌘ or ⌃. A plain move
    /// only: libghostty's drags call mouseMoved, and they keep their own modifiers (⌥ makes a selection a rectangle).
    override func mouseMoved(with event: NSEvent) {
        guard event.type == .mouseMoved, Self.sideKey(event.modifierFlags) else { return super.mouseMoved(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        linkSurface?.sendMousePos(x: point.x, y: bounds.height - point.y, modifiers: .super_)
    }

    /// libghostty reports a link again only on another cell, so the pointer leaves the view first. Only on a change of
    /// ⌥ alone: made-up moves on every ⇧ or ⌃ would reach a program that tracks the mouse.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let side = Self.sideKey(event.modifierFlags)
        defer { sideHeld = side }
        guard side != sideHeld, NSEvent.pressedMouseButtons == 0, let window,
              NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber,
              window.contentView?.hitTest(window.mouseLocationOutsideOfEventStream)?.isDescendant(of: self) == true
        else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let modifiers: TerminalInputModifiers = side ? .super_ : .init(from: event.modifierFlags)
        linkSurface?.sendMousePos(x: -1, y: -1, modifiers: modifiers)
        linkSurface?.sendMousePos(x: point.x, y: bounds.height - point.y, modifiers: modifiers)
    }
}

extension PaneSurfaceView: TerminalSurfaceOpenURLDelegate, TerminalSurfaceHoverLinkDelegate {
    func terminalDidRequestOpenURL(_ url: String, kind _: TerminalOpenURLKind) {
        _ = openLink?(url, .tab)
    }

    func terminalDidUpdateHoverLink(_ url: String?) {
        hoveredLink = url
        (url == nil ? NSCursor.arrow : .pointingHand).set()
    }

    override func accessibilityTitle() -> String? {
        hoveredLink
    }
}
