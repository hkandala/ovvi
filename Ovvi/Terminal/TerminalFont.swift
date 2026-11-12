import AppKit
import GhosttyTerminal

extension PaneTerminal {
    static let fontSize = 13
    static let fontSizes = 8 ... 32

    /// `keybind = clear`: app shortcuts reach the menu. No padding, so that cells map from the view's origin; no
    /// scrollback, herdr keeps it. No links of libghostty's but OSC 8 ones: the app finds them (`Links.swift`).
    ///
    /// A selection draws its text in the theme's text color, as Ghostty's own Alabaster and Afterglow themes do, so a
    /// program's colors (one chosen for the other appearance, a dark text color) never hide it. Light: Ghostty's
    /// Alabaster selection, `#000000` on `#BFDBFE`. Dark: Afterglow's `#D0D0D0` on the system blue at 0.25 over
    /// Afterglow's background, 7.6 to 1 (Ghostty's `#303030` is hardly darker than a card).
    /// ponytail: always blue; follow the accent color (`NSColor.selectedTextBackgroundColor`) if users ask.
    static let controller = TerminalController(theme: TerminalTheme(
        light: .alabaster.selectionBackground("BFDBFE").selectionForeground("000000"),
        dark: .afterglow.selectionBackground("1B3A58").selectionForeground("D0D0D0"),
    )) {
        $0.withCustom("keybind", "clear")
        $0.withBackgroundOpacity(0)
        $0.withWindowPaddingX(0)
        $0.withWindowPaddingY(0)
        $0.withCustom("window-padding-balance", "false")
        $0.withCustom("scrollback-limit", "0")
        $0.withCustom("link-url", "false")
    }

    static let systemFont = NSFont.monospacedSystemFont(ofSize: 0, weight: .regular).familyName ?? "Menlo"

    static var fonts: [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        // SF Mono, when installed, is the first choice already.
        return Set(names.compactMap { NSFont(name: $0, size: 0)?.familyName }
            .filter { !$0.hasPrefix(".") && $0 != "SF Mono" }).sorted()
    }

    private static var lastGrid = ""

    /// Reads the stored size, not a caller's copy: SwiftUI keeps a shortcut's first action.
    static func stepFontSize(_ step: Int) {
        let settings = AppSettings()
        settings.fontSize = clamped(clamped(settings.fontSize) + step)
    }

    static func configure() {
        let settings = AppSettings(), grid = "\(settings.terminalFont) \(settings.fontSize)"
        if grid != lastGrid {
            PaneViewRegistry.recent.forEach { $0.hold() }
            lastGrid = grid
        }
        controller.setTerminalConfiguration(TerminalConfiguration {
            $0.withFontFamily(settings.terminalFont.isEmpty ? systemFont : settings.terminalFont)
            $0.withFontSize(Float(clamped(settings.fontSize)))
            $0.withCursorStyle(settings.cursorStyle)
            // Unset, Ghostty also follows DEC mode 12; false only makes the default still. A program's DECSCUSR wins
            // either way.
            if !settings.cursorBlink {
                $0.withCursorStyleBlink(false)
            }
            // Always set: on CI's machine libghostty's default sends Alt.
            $0.withCustom("macos-option-as-alt", settings.optionKey.ghostty)
            // The system pasteboard: libghostty's `true` writes only a selection clipboard, which nothing reads.
            if settings.copyOnSelect {
                $0.withCustom("copy-on-select", "clipboard")
            }
        })
    }

    /// A hand-edited default (`defaults write`) can be out of range.
    private static func clamped(_ size: Int) -> Int {
        min(max(size, fontSizes.lowerBound), fontSizes.upperBound)
    }
}
