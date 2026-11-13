import HerdrKit
import SwiftUI

/// An action's keys: the first shows in the menu bar, the palette and tooltips; a key monitor runs the others
/// (`KeyboardShortcut.second`).
struct Hotkey: Identifiable {
    let id: String
    let title: String
    let group: String
    let keys: [KeyboardShortcut]
    /// Where the keys work, for conflicts: nil everywhere; `terminal`, `browser`, `plugin` (every plugin card) or
    /// `plugin.<id>` (that plugin's cards).
    var scope: String?
    /// Shown in the Keyboard Shortcuts panel (⌘/).
    var top = false
    /// The panel shows the set as one row while each keeps its default: "Show Tab 1–9", "⌘ 1–9".
    var family: (title: String, keys: String)?

    init(_ id: String, _ title: String, _ group: String, keys chords: [String], scope: String? = nil,
         top: Bool = false, family: (title: String, keys: String)? = nil)
    {
        (self.id, self.title, self.group, self.scope, self.top, self.family) = (id, title, group, scope, top, family)
        keys = chords.compactMap(KeyboardShortcut.init(chord:))
        assert(keys.count == chords.count, "\(id): a default key that does not read")
    }

    init(_ id: String, _ title: String, _ group: String, _ chords: String..., scope: String? = nil, top: Bool = false,
         family: (title: String, keys: String)? = nil)
    {
        self.init(id, title, group, keys: chords, scope: scope, top: top, family: family)
    }

    /// A plugin's command, with the key its manifest names.
    init(_ manifest: PluginManifest, _ command: PluginManifest.Command) {
        id = "plugin.\(manifest.id).\(command.id)"
        (title, group, scope) = (command.title, manifest.name, "plugin.\(manifest.id)")
        keys = command.key.flatMap(KeyboardShortcut.init(chord:)).map { [$0] } ?? []
    }
}

/// Every action's keys, and the user's changes to them: `keys` in settings.json, chords per action id (an empty list
/// is no key).
@MainActor @Observable
final class Hotkeys {
    static let shared = Hotkeys()
    private(set) var saved = (PluginPackages.value("keys", in: Registry.settings) as? [String: Any])?
        .compactMapValues { $0 as? [String] } ?? [:]

    /// macOS's and AppKit's own keys, ahead of the app's in the menu bar: no action can take them.
    static let fixed = [
        Hotkey("macos.quit", "Quit Ovvi", "macOS", "cmd+q"), Hotkey("macos.hide", "Hide Ovvi", "macOS", "cmd+h"),
        Hotkey("macos.hide-others", "Hide Others", "macOS", "option+cmd+h"),
        Hotkey("macos.minimize", "Minimize", "macOS", "cmd+m"), Hotkey("macos.undo", "Undo", "macOS", "cmd+z"),
        Hotkey("macos.redo", "Redo", "macOS", "shift+cmd+z"), Hotkey("macos.cut", "Cut", "macOS", "cmd+x"),
        Hotkey("macos.copy", "Copy", "macOS", "cmd+c"), Hotkey("macos.paste", "Paste", "macOS", "cmd+v"),
        Hotkey("macos.select-all", "Select All", "macOS", "cmd+a"),
        Hotkey("macos.full-screen", "Enter Full Screen", "macOS", "ctrl+cmd+f"),
        Hotkey("macos.windows", "Move Focus to Next Window", "macOS", "cmd+`"),
        Hotkey("macos.emoji", "Emoji & Symbols", "macOS", "ctrl+cmd+space"),
    ]

    static let groups = ["App", "Sessions", "Spaces", "Tabs", "Panes", "Terminal", "Edit", "Browser", "Plugins"]

    var all: [Hotkey] {
        Self.app + Registry.all.flatMap { manifest in manifest.commands.map { Hotkey(manifest, $0) } }
    }

    func keys(_ hotkey: Hotkey) -> [KeyboardShortcut] {
        saved[hotkey.id].map { $0.compactMap(KeyboardShortcut.init(chord:)) } ?? hotkey.keys
    }

    func changed(_ hotkey: Hotkey) -> Bool {
        saved[hotkey.id] != nil
    }

    /// The action, other than `hotkey`, that `key` already runs where `hotkey` works.
    func clash(_ key: KeyboardShortcut, for hotkey: Hotkey, in list: [Hotkey]? = nil) -> Hotkey? {
        ((list ?? all) + Self.fixed)
            .first { $0.id != hotkey.id && Self.overlap($0.scope, hotkey.scope) && keys($0).contains(key) }
    }

    private static func overlap(_ one: String?, _ other: String?) -> Bool {
        guard let one, let other else { return true }
        return one == other || [one, other].contains("plugin") && (one + other).contains("plugin.")
    }

    func set(_ hotkey: Hotkey, _ keys: [KeyboardShortcut]) {
        saved[hotkey.id] = keys == hotkey.keys ? nil : keys.map(\.chord)
        save()
    }

    func resetAll() {
        saved = [:]
        save()
    }

    private func save() {
        do {
            try PluginPackages.set(saved.isEmpty ? nil : saved, "keys", in: Registry.settings)
        } catch {
            PluginInstalls.shared.couldNotSave(error)
        }
    }

    static func keys(_ id: String) -> [KeyboardShortcut] {
        assert(byID[id] != nil, "no action \(id)")
        return byID[id].map(shared.keys) ?? []
    }

    /// For text that names a key: its glyphs, or the action's title when it has none.
    static func named(_ id: String) -> String {
        keys(id).first?.glyphs ?? byID[id]?.title ?? id
    }

    private static let byID = Dictionary(app.map { ($0.id, $0) }) { first, _ in first }
}

extension Hotkeys {
    static let app: [Hotkey] = general + sessions + spaces + tabs + panes + terminal + edit + browser + plugins

    private static let general = [
        Hotkey("app.palette", "Command Palette", "App", "cmd+k", "shift+cmd+p", top: true),
        Hotkey("app.shortcuts", "Keyboard Shortcuts", "App", "cmd+/", top: true),
        Hotkey("app.settings", "Settings…", "App", "cmd+,", top: true),
        Hotkey("app.new-window", "New Window", "App", "cmd+n", top: true),
        Hotkey("app.sidebar", "Toggle Sidebar", "App", "ctrl+cmd+s", top: true),
        Hotkey("app.overview", "Show Overview", "App", "ctrl+cmd+o", top: true),
        Hotkey("app.bigger", "Increase Font Size", "App", "cmd++", "cmd+=", top: true),
        Hotkey("app.smaller", "Decrease Font Size", "App", "cmd+-", top: true),
        Hotkey("app.actual-size", "Reset Font Size", "App", "cmd+0", top: true),
    ]

    private static let sessions = [
        Hotkey("session.open", "Open Session…", "Sessions", "option+cmd+t", top: true),
        Hotkey("session.detach", "Detach Session", "Sessions", "option+cmd+w", top: true),
        Hotkey("session.previous", "Previous Session", "Sessions", "option+cmd+[", top: true),
        Hotkey("session.next", "Next Session", "Sessions", "option+cmd+]", top: true),
    ] + jumps("session", "Session", "Sessions", "option+cmd+")

    private static let spaces = [
        Hotkey("space.new", "New Space", "Spaces", "ctrl+cmd+t", top: true),
        Hotkey("space.close", "Close Space", "Spaces", "ctrl+cmd+w", top: true),
        Hotkey("space.previous", "Show Previous Space", "Spaces", "ctrl+cmd+[", top: true),
        Hotkey("space.next", "Show Next Space", "Spaces", "ctrl+cmd+]", top: true),
    ] + jumps("space", "Space", "Spaces", "ctrl+cmd+")

    private static let tabs = [
        Hotkey("tab.new", "New Tab", "Tabs", "cmd+t", top: true),
        Hotkey("tab.close", "Close Tab", "Tabs", "shift+cmd+w", top: true),
        Hotkey("tab.close-others", "Close Other Tabs", "Tabs"),
        Hotkey("tab.close-right", "Close Tabs to the Right", "Tabs"),
        Hotkey("tab.previous", "Show Previous Tab", "Tabs", "shift+cmd+[", "ctrl+shift+tab", top: true),
        Hotkey("tab.next", "Show Next Tab", "Tabs", "shift+cmd+]", "ctrl+tab", top: true),
        Hotkey("tab.back", "Go Back", "Tabs", "ctrl+cmd+left", top: true),
        Hotkey("tab.forward", "Go Forward", "Tabs", "ctrl+cmd+right", top: true),
        Hotkey("tab.move-left", "Move Tab Left", "Tabs", "shift+cmd+left", top: true),
        Hotkey("tab.move-right", "Move Tab Right", "Tabs", "shift+cmd+right", top: true),
    ] + jumps("tab", "Tab", "Tabs", "cmd+")

    private static let panes = [
        Hotkey("pane.split-right", "Split Right", "Panes", "cmd+d", top: true),
        Hotkey("pane.split-down", "Split Down", "Panes", "shift+cmd+d", top: true),
        Hotkey("pane.split-left", "Split Left", "Panes"),
        Hotkey("pane.split-up", "Split Up", "Panes"),
        Hotkey("pane.zoom", "Zoom Pane", "Panes", "shift+cmd+return", top: true),
        Hotkey("pane.float", "Float Pane", "Panes"),
        Hotkey("pane.close", "Close Pane", "Panes", "cmd+w", top: true),
        Hotkey("pane.replace", "Replace Pane", "Panes", "shift+cmd+r", top: true),
        Hotkey("pane.balance", "Balance Splits", "Panes", "option+cmd+=", top: true),
        Hotkey("pane.previous", "Select Previous Pane", "Panes", "cmd+[", top: true),
        Hotkey("pane.next", "Select Next Pane", "Panes", "cmd+]", top: true),
    ] + arrows("select", "Select Pane", "option+cmd+") + arrows("move", "Move Pane", "option+shift+cmd+")
        + arrows("resize", "Resize Pane", nil)

    private static let terminal = [
        Hotkey("terminal.redraw", "Redraw Terminal", "Terminal", "option+cmd+r", scope: "terminal"),
        Hotkey("terminal.directory", "Go to Directory…", "Terminal", "shift+cmd+g", scope: "terminal"),
        Hotkey("terminal.insert-path", "Insert Path…", "Terminal", "shift+cmd+i", scope: "terminal"),
        Hotkey("terminal.line-start", "Go to Line Start", "Terminal", "cmd+left", scope: "terminal"),
        Hotkey("terminal.line-end", "Go to Line End", "Terminal", "cmd+right", scope: "terminal"),
        Hotkey("terminal.delete-line", "Delete to Line Start", "Terminal", "cmd+delete", scope: "terminal"),
        Hotkey("terminal.word-back", "Go Back a Word", "Terminal", "option+left", scope: "terminal"),
        Hotkey("terminal.word-forward", "Go Forward a Word", "Terminal", "option+right", scope: "terminal"),
    ]

    private static let edit = [
        Hotkey("edit.find", "Find…", "Edit", "cmd+f", top: true),
        Hotkey("edit.find-next", "Find Next", "Edit", "cmd+g", top: true),
        Hotkey("edit.find-previous", "Find Previous", "Edit", "shift+cmd+g", scope: "plugin"),
        Hotkey("edit.save", "Save", "Edit", "cmd+s", scope: "plugin"),
    ]

    private static let browser = [
        Hotkey("browser.reload", "Reload Page", "Browser", "cmd+r", scope: "browser"),
        Hotkey("browser.location", "Open Location", "Browser", "cmd+l", scope: "browser"),
        Hotkey("browser.inspector", "Show Web Inspector", "Browser", "option+cmd+i", scope: "browser"),
    ]

    private static let plugins = [
        Hotkey("card.back", "Back", "Plugins", "ctrl+-", "cmd+left", scope: "plugin"),
        Hotkey("card.forward", "Forward", "Plugins", "ctrl+shift+-", "cmd+right", scope: "plugin"),
        Hotkey("card.reload", "Reload Plugin", "Plugins", "option+cmd+r", scope: "plugin"),
    ]

    private static func jumps(_ id: String, _ level: String, _ group: String, _ modifiers: String) -> [Hotkey] {
        (1 ... 9).map {
            Hotkey("\(id).\($0)", "Show \(level) \($0)", group, "\(modifiers)\($0)", top: true,
                   family: (title: "Show \(level) 1–9", keys: "1–9"))
        }
    }

    private static func arrows(_ id: String, _ title: String, _ modifiers: String?) -> [Hotkey] {
        ["left", "right", "up", "down"].map { side in
            let chords = modifiers.map { [$0 + side] } ?? []
            return Hotkey("pane.\(id)-\(side)", "\(title) \(side.capitalized)", "Panes", keys: chords,
                          top: modifiers != nil,
                          family: (title: title, keys: "←→↑↓"))
        }
    }
}

extension KeyboardShortcut {
    private static let named: [String: KeyEquivalent] = [
        "left": .leftArrow, "right": .rightArrow, "up": .upArrow, "down": .downArrow, "return": .return, "tab": .tab,
        "space": .space, "escape": .escape, "delete": .delete, "plus": "+",
    ]
    private static let modifierNames: [(String, EventModifiers)] = [
        ("ctrl", .control), ("option", .option), ("shift", .shift), ("cmd", .command),
    ]

    init?(chord text: String) {
        guard let chord = Chord(text) else { return nil }
        self.init(Self.named[chord.key] ?? KeyEquivalent(Character(chord.key)),
                  modifiers: EventModifiers(Self.modifierNames.filter { chord.modifiers.contains($0.0) }.map(\.1)))
    }

    var chord: String {
        let name = Self.named.first { $0.value == key }?.key ?? String(key.character)
        let names = Self.modifierNames.filter { modifiers.contains($0.1) }.map(\.0)
        return Chord(modifiers: Set(names), key: name)?.description ?? ""
    }

    /// The key as the user typed it, with its unshifted character (⇧⌘[ is `[`, not `{`); nil for a key no chord
    /// names (F1, or one with no ⌘, ⌃ or ⌥).
    init?(event: NSEvent) {
        let specials: [NSEvent.SpecialKey: String] = [
            .leftArrow: "left", .rightArrow: "right", .upArrow: "up", .downArrow: "down", .carriageReturn: "return",
            .enter: "return", .tab: "tab", .backTab: "tab", .delete: "delete",
        ]
        let typed = event.characters(byApplyingModifiers: [])?.lowercased() ?? ""
        let key = event.specialKey.flatMap { specials[$0] } ?? [" ": "space", "\u{1B}": "escape"][typed] ?? typed
        let names = Self.modifierNames.filter { event.modifierFlags.contains(Self("a", modifiers: $0.1).modifierFlags) }
            .map(\.0)
        guard key.unicodeScalars.allSatisfy({ !(0xF700 ... 0xF8FF).contains($0.value) }),
              let chord = Chord(modifiers: Set(names), key: key) else { return nil }
        self.init(chord: chord.description)
    }

    /// `key: .hotkey("tab.new")`: the first key of one of the app's actions, as the user set it.
    @MainActor static func hotkey(_ id: String) -> KeyboardShortcut? {
        Hotkeys.keys(id).first
    }
}
