import AppKit
import Carbon.HIToolbox
import GhosttyTerminal
import HerdrKit
import SwiftUI

/// herdr's frames carry none of the app's input modes (cursor keys, kitty keyboard, mouse), so libghostty would encode
/// keys and clicks for a plain terminal: keys whose bytes depend on those modes go to herdr by name, clicks and the
/// wheel go as cells, and herdr encodes them for the app.
final class PaneSurfaceView: AppTerminalView {
    weak var terminal: PaneTerminal?
    /// The in-memory session's own sizes carry no cell size.
    private(set) var metrics: TerminalGridMetrics?
    private var dragged: (column: Int, row: Int)?
    private var commandClick = false
    var linkClick = false
    weak var linkSurface: TerminalSurface?
    /// An OSC 8 link libghostty reports.
    var hoveredLink: String?
    var hovered: Hovered?, hoveredCell: TerminalLink.Place?
    var linkTint: CALayer?
    var fakesCommand = false
    var openLink: ((TerminalLink, Opening) -> Void)?
    private var scrolled: CGFloat = 0

    /// A plain left drag's start (`Selection.swift`).
    var anchor: Anchor?

    var wantsKeyboard = false
    var onKeyboard: (() -> Void)?
    var onReturn: (() -> Void)?
    var tileScale: () -> CGFloat = { WindowPages.tile }
    var store: () -> HostStore? = { nil }
    var still: CALayer?
    var stillWatch: NSKeyValueObservation?
    var stillFrames = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        delegate = self
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Terminal")
        registerForDraggedTypes(Self.dropTypes)
        // libghostty-spm would paste a path on This Mac, also on a remote card.
        acceptsFileDrops = false
    }

    func takeKeyboard() {
        wantsKeyboard = window == nil
        claimed = true
        claimKeyboard()
    }

    /// The registry drops the other views' claims (`dropClaim`), so that an earlier one cannot steal the keyboard back.
    /// Per window: a claim in one window leaves another's alone.
    private var claimed = false

    func dropClaim() {
        wantsKeyboard = false
        claimed = false
    }

    /// After SwiftUI's update: a first responder set during one is undone.
    private func claimKeyboard() {
        DispatchQueue.main.async { [weak self] in
            guard let self, claimed else { return }
            // Out of the window for a moment (SwiftUI moves it to a new host when a split closes), or in a kept page
            // out of view (the overview's): claim it once it is in view again, or the keyboard goes nowhere.
            guard let window, !isHiddenOrHasHiddenAncestor else {
                wantsKeyboard = true
                return
            }
            guard !window.panelOpen else { return }
            window.makeFirstResponder(self)
            // Also when it is the first responder already (no becomeFirstResponder then).
            terminal?.hasKeyboard = window.firstResponder === self
        }
    }

    /// SwiftUI moves the view to a new host when the layout changes (a split); leaving the window drops the first
    /// responder, so it takes the keyboard back once it is in again. Not when another terminal asked for it since:
    /// that claim dropped this one.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, claimed, window?.firstResponder === self {
            wantsKeyboard = true
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        purgeable(window == nil)
        // A view that left the window leaves without resignFirstResponder; the flag must not stay on.
        terminal?.hasKeyboard = window?.firstResponder === self
        if wantsKeyboard, window != nil {
            wantsKeyboard = false
            claimKeyboard()
        }
    }

    override var acceptsFirstResponder: Bool {
        !(superview is MiniTerminal.Mini) && super.acceptsFirstResponder
    }

    private var inMiniature = false

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        inMiniature = superview is MiniTerminal.Mini
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        dropSmallStill()
        if inMiniature, claimed, window != nil, window?.firstResponder !== self {
            claimKeyboard()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        terminal?.hasKeyboard = became
        if became {
            claimed = true
            onKeyboard?()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            terminal?.hasKeyboard = false
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        if [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)), !event.isARepeat, !hasMarkedText() {
            onReturn?()
        }
        if !hasMarkedText(), let key = Self.herdrKey(event) {
            terminal?.keys([key])
        } else if event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command, .control],
                  event.charactersIgnoringModifiers == "f"
        {
            // ⌃⌘F: AppKit's window toggles full screen only for keys no view takes; libghostty takes all.
            window?.toggleFullScreen(nil)
        } else if hasMarkedText() || !event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
        } else if CommandList.keyWindow?.run({ $0.matches(event) }) != true {
            // A ⌘ key no menu item took runs the key window's command for it: the menu bar may still hold another
            // window's list (a floating window's has no ⌘D). Else (⌘0 at the default size, ⌘9 without a ninth
            // tab) libghostty, with no key bindings, would type its character: AppKit's beep instead.
            NSSound.beep()
        }
    }

    /// herdr's rule: a right click opens the pane's menu (the card's context menu, up the responder chain), also in
    /// a mouse app. A ⌥-right click goes to the program with ⌥ stripped, as with herdr's
    /// `right_click_passthrough_modifier = "alt"`. libghostty gets none: its Copy menu is in the card's menu.
    private var rightToProgram = false

    override func rightMouseDown(with event: NSEvent) {
        // Only ⌥, as herdr matches the modifiers exactly: ⌥⇧ opens the menu.
        rightToProgram = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
        guard rightToProgram else {
            nextResponder?.rightMouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        mouse(.down, .right, event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if rightToProgram {
            mouse(.drag, .right, event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        if rightToProgram {
            mouse(.up, .right, event)
        }
    }

    /// Middle clicks skip libghostty, which could paste its selection as typed input.
    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouse(.down, .middle, event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouse(.drag, .middle, event)
    }

    override func otherMouseUp(with event: NSEvent) {
        mouse(.up, .middle, event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let cell = cell(event), let metrics else { return }
        // Trackpads report points, wheels report lines.
        scrolled += event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY * scale / CGFloat(metrics.cellHeightPixels) : event.scrollingDeltaY
        let lines = Int(scrolled)
        scrolled -= CGFloat(lines)
        if lines != 0 {
            // A positive delta shows earlier lines: up.
            terminal?.scroll(lines: -lines, column: cell.column, row: cell.row, modifiers: modifiers(event))
        }
    }

    func mouse(_ action: TerminalStream.MouseAction, _ button: TerminalStream.MouseButton,
               _ event: NSEvent)
    {
        // Back and forward buttons are other buttons too, not middle clicks.
        guard button != .middle || event.buttonNumber == 2, let cell = cell(event) else { return }
        // A ⌘-click opens a link (libghostty); none of it goes to herdr.
        if action == .down {
            commandClick = event.modifierFlags.contains(.command)
        }
        guard !commandClick else { return }
        if action == .drag, let dragged, dragged == cell {
            return
        }
        dragged = action == .up ? nil : cell
        // A right click comes here only with ⌥, which herdr's pass-through strips.
        terminal?.mouse(action, button, column: cell.column, row: cell.row,
                        modifiers: modifiers(event) & ~(button == .right ? 4 : 0))
    }

    var scale: CGFloat {
        window?.backingScaleFactor ?? 2
    }

    func cell(_ event: NSEvent) -> (column: Int, row: Int)? {
        guard let metrics, metrics.cellWidthPixels > 0, metrics.cellHeightPixels > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let column = Int(point.x * scale) / Int(metrics.cellWidthPixels)
        let row = Int((bounds.height - point.y) * scale) / Int(metrics.cellHeightPixels)
        return (min(max(column, 0), Int(metrics.columns) - 1), min(max(row, 0), Int(metrics.rows) - 1))
    }

    /// crossterm bits: 1 shift, 2 ctrl, 4 alt.
    private func modifiers(_ event: NSEvent) -> Int {
        let flags = event.modifierFlags
        return (flags.contains(.shift) ? 1 : 0) | (flags.contains(.control) ? 2 : 0)
            | (flags.contains(.option) ? 4 : 0)
    }

    private static let names: [UInt16: String] = [
        kVK_Return: "enter", kVK_ANSI_KeypadEnter: "enter", kVK_Tab: "tab", kVK_Delete: "backspace", kVK_Escape: "esc",
        kVK_LeftArrow: "left", kVK_RightArrow: "right", kVK_DownArrow: "down", kVK_UpArrow: "up",
        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6",
        kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
    ].reduce(into: [:]) { $0[UInt16($1.key)] = $1.value }

    /// The US character of each letter, digit and symbol key (kVK_ANSI_*), for Ctrl chords on
    /// layouts whose letters are not Latin.
    private static let ansi: [UInt16: String] = {
        var keys = [UInt16: String](uniqueKeysWithValues: zip(
            0...,
            "asdfhgzxcv_bqweryt123465=97-80]ou[ip_lj'k;\\,/nm.",
        )
        .filter { $0.1 != "_" }
        .map { (UInt16($0.0), String($0.1)) })
        keys[49] = "space"
        keys[50] = "`"
        return keys
    }()

    /// herdr's name (`pane.send_keys`) for a key whose bytes depend on the app's input modes:
    /// arrows, Esc, F-keys, any of them with modifiers, Ctrl chords; plus macOS line editing
    /// (Cmd+←/→/⌫, Option+←/→), which `keybind = clear` took from libghostty. nil leaves the
    /// key to libghostty: text, IME, dead keys, Option characters, other Cmd keys, and plain
    /// Enter, Tab and Backspace, which are the same bytes in every mode and stay off the slower
    /// bridge path. Home, End, Page Up/Down and Delete have no herdr names; libghostty sends
    /// them as xterm does.
    /// Option follows Settings ▸ Terminal ▸ Option key (`macos-option-as-alt`); ⌥← and ⌥→ move by word with every
    /// choice.
    static func herdrKey(_ event: NSEvent) -> String? {
        let flags = event.modifierFlags
        let control = flags.contains(.control), option = flags.contains(.option), shift = flags.contains(.shift)
        let named = names[event.keyCode]
        if flags.contains(.command) {
            guard !control, !option else { return nil }
            return ["left": "ctrl+a", "right": "ctrl+e", "backspace": "ctrl+u"][named ?? ""]
        }
        if option, !control, !shift, let word = ["left": "alt+b", "right": "alt+f"][named ?? ""] {
            return word
        }
        let prefix = (control ? "ctrl+" : "") + (option ? "alt+" : "")
        if let named {
            if !control, !option, !shift, ["enter", "tab", "backspace"].contains(named) {
                return nil
            }
            return prefix + (shift && named != "esc" ? "shift+" : "") + named
        }
        // The layout's letter (Dvorak, AZERTY), else the key's US character (Ctrl+С on a Russian
        // layout is Ctrl+C). Shift stays: under the kitty keyboard protocol Ctrl+Shift+S is its own key (pi's
        // extensions bind them); herdr sends Ctrl+S's byte to a program without it.
        guard control else { return nil }
        let chord = prefix + (shift ? "shift+" : "")
        if let letter = event.charactersIgnoringModifiers?.lowercased(), letter.count == 1,
           letter.first?.isASCII == true, letter.first?.isLetter == true
        {
            return chord + letter
        }
        return ansi[event.keyCode].map { chord + $0 }
    }
}

extension PaneSurfaceView {
    override func viewDidUnhide() {
        super.viewDidUnhide()
        if wantsKeyboard, window != nil {
            wantsKeyboard = false
            claimKeyboard()
        }
    }

    override func accessibilityIdentifier() -> String {
        terminal.map { "terminal.\($0.paneID)" } ?? ""
    }

    /// ponytail: grid size until VoiceOver gets the screen text (design: accessibility).
    override func accessibilityValue() -> Any? {
        metrics.map { "\($0.rows) \($0.columns)" }
    }
}

extension PaneSurfaceView: TerminalSurfaceGridResizeDelegate, TerminalSurfaceLifecycleDelegate {
    func terminalDidResize(_ size: TerminalGridMetrics) {
        if let metrics, metrics.columns != size.columns || metrics.rows != size.rows {
            terminal?.hold()
        }
        metrics = size
        hover(nil)
    }

    /// A new surface starts focused (a filled cursor) until it first loses the keyboard, and
    /// libghostty-spm has no public way to set a surface's focus; resigning is the one that
    /// tells the surface it is not focused.
    func terminalDidAttachSurface(_ surface: TerminalSurface) {
        linkSurface = surface
        if window?.firstResponder !== self {
            _ = resignFirstResponder()
        }
        coverNewSurface()
    }

    func terminalDidDetachSurface() {}
}
