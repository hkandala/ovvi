import var Carbon.HIToolbox.Events.kVK_Delete // not all of Carbon: its EventModifiers clashes with SwiftUI's
import var Carbon.HIToolbox.Events.kVK_Tab
import HerdrKit
import SwiftUI

extension KeyboardShortcut {
    var glyphs: String {
        caps.joined()
    }

    var caps: [String] {
        let keys: [Character: String] = [
            KeyEquivalent.return.character: "↩", KeyEquivalent.tab.character: "⇥",
            KeyEquivalent.leftArrow.character: "←", KeyEquivalent.rightArrow.character: "→",
            KeyEquivalent.upArrow.character: "↑", KeyEquivalent.downArrow.character: "↓",
            KeyEquivalent.delete.character: "⌫", KeyEquivalent.escape.character: "⎋",
            KeyEquivalent.space.character: "Space",
        ]
        return Self.modifierKeys.filter { modifiers.contains($0.modifier) }.map(\.glyph)
            + [keys[key.character] ?? String(key.character).uppercased()]
    }
}

extension KeyboardShortcut {
    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(Self.modifierKeys.filter { modifiers.contains($0.modifier) }.map(\.flag))
    }

    /// ⇧⌘[ types "{", so the key matches with or without Shift's character. With Shift, Tab's character is backtab.
    /// Delete types DEL, not its key equivalent's backspace.
    func matches(_ event: NSEvent) -> Bool {
        let keys = Int(event.keyCode) == kVK_Tab ? "\t" : Int(event.keyCode) == kVK_Delete ? "\u{8}"
            : (event.charactersIgnoringModifiers ?? "") + (event.characters(byApplyingModifiers: []) ?? "")
        return event.modifierFlags.intersection([.command, .shift, .option, .control]) == modifierFlags
            && keys.lowercased().contains(key.character)
    }

    /// Takes the key even when the command is disabled, and in a text field too: else ⌃⇥ goes on to AppKit's key
    /// view loop, which steps the panes. Only a command's keys: Back's ⌘← stays the page's.
    @MainActor static func second(_ event: NSEvent) -> Bool {
        guard let first = Hotkeys.app.lazy.map(Hotkeys.shared.keys)
            .first(where: { $0.dropFirst().contains { $0.matches(event) } })?.first,
            let commands = CommandList.keyWindow, commands.contains(where: { $0.key == first }) else { return false }
        commands.run { $0 == first }
        return true
    }
}

extension FocusedValues {
    @Entry var commands: CommandList?
}

extension CommandList: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.shown == rhs.shown
    }
}

extension View {
    /// SwiftUI rebuilds the menu bar only when this value changes: `Commands` do not observe. A modifier, so reading
    /// `all` re-runs only its body, not the window's.
    func menuBar(_ commands: CommandList) -> some View {
        modifier(MenuBar(commands: commands))
    }
}

private struct MenuBar: ViewModifier {
    let commands: CommandList
    /// Their change runs this body again: `commands.settings` is no dynamic property of this view.
    private var settings = AppSettings()

    func body(content: Content) -> some View {
        var commands = commands
        // Ids too: SwiftUI keeps the first of two equal values, and its actions (another floating window's pane,
        // another page). The keyboard card is read here so a keyboard move redraws the menu.
        let page = commands.pages?.current
        commands.menu = commands.menuBarList
        commands.shown = [
            [commands.floating as Any, commands.pages.map(ObjectIdentifier.init) as Any,
             page.map(ObjectIdentifier.init) as Any].map { String(describing: $0) }.joined(separator: " "),
            page?.keyboardCard(page?.selectedTab?.id)?.id ?? "",
        ] + commands.menu.map(\.shown)
        return content.focusedSceneValue(\.commands, commands).background(KeyWindowList(commands: commands))
    }
}

@MainActor
extension CommandList {
    /// Made when the key is pressed: the menu bar's list may still be another window's.
    static var keyWindow: [Command]? {
        KeyWindowList.Holder.all.allObjects.first { $0.window?.isKeyWindow == true }?.commands?.menuBarList
    }

    static func runInMainWindow(_ id: String) {
        let holders = KeyWindowList.Holder.all.allObjects.filter { $0.commands?.floating == nil }
        guard let holder = NSApp.orderedWindows.lazy.compactMap({ window in holders.first { $0.window === window } })
            .first else { return }
        holder.window?.makeKeyAndOrderFront(nil)
        holder.commands?.menuBarList.first { $0.id == id }?.action()
    }
}

extension [Command] {
    @discardableResult func run(_ matches: (KeyboardShortcut) -> Bool) -> Bool {
        guard let command = first(where: { $0.key.map(matches) == true }), command.enabled else { return false }
        command.action()
        return true
    }
}

private struct KeyWindowList: NSViewRepresentable {
    let commands: CommandList

    func makeNSView(context _: Context) -> Holder {
        let holder = Holder()
        Holder.all.add(holder)
        return holder
    }

    func updateNSView(_ holder: Holder, context _: Context) {
        holder.commands = commands
    }

    final class Holder: NSView {
        static let all = NSHashTable<Holder>.weakObjects()
        var commands: CommandList?
    }
}

struct Command {
    /// In the menu bar's order, which the palette follows too.
    enum Section: CaseIterable {
        case app
        case file, close, edit, view
        case paneSetting
        case pane, paneMove
        case paneKeys
        case size, tabSteps, workspaceSteps, pages, tabs, workspaces, sessions
        case palette
        case help

        var group: Group {
            switch self {
            case .edit: .edit
            case .paneSetting, .pane, .paneMove, .paneKeys: .panes
            case .tabSteps, .tabs: .tabs
            case .workspaceSteps, .workspaces: .workspaces
            case .pages, .sessions: .sessions
            case .app, .file, .close, .view, .size, .palette, .help: .view
            }
        }
    }

    /// In the palette's order.
    enum Group: String, CaseIterable {
        case tabs = "Tabs", workspaces = "Spaces", sessions = "Sessions", panes = "Panes", view = "View"
        case edit = "Edit", plugins = "Plugins"
    }

    let section: Section
    let title: String
    /// For code that finds it (its titles and keys change), and a choice's row (`Palette.choiceID`).
    var id: String?
    var key: KeyboardShortcut?
    var group: Group?
    var symbol: String?
    var program: String?
    var heading: String?
    var keywords = ""
    var enabled = true
    var checked: Bool?
    var setting = false
    var menu: [Command] = []
    var previews = false
    var name: (current: String, save: (String) async -> Void)?
    var field: (prompt: String, open: (String) -> Void)?
    /// ⌥ is read as the pane is made, so both items run the same action.
    var alternate: String?
    var action: () -> Void = {}

    var shown: String {
        "\(title) \(enabled) \(String(describing: checked)) \(key?.glyphs ?? "") \(menu.map(\.shown))"
            + (alternate ?? "")
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.commands) private var commands
    @Environment(\.openWindow) private var openWindow
    private var settings = AppSettings()

    var body: some Commands {
        // `_ =` is no statement in a builder.
        // swiftlint:disable:next redundant_discardable_let
        let _ = WindowPages.openWindow = openWindow
        let list = (commands?.menu ?? CommandList(settings: settings).menuBarList).map { command in
            var keyed = command
            if let key = command.key {
                keyed.action = {
                    if let live = CommandList.keyWindow {
                        live.run { $0 == key }
                    } else if NSApp.keyWindow?.sheetParent == nil {
                        command.action()
                    }
                }
            } else if command.section == .app {
                // The app menu reads no window's list as it opens: it shows the windowless one.
                keyed.action = { CommandList.keyWindow?.first { $0.title == command.title }?.action() }
            }
            return keyed
        }
        CommandGroup(replacing: .appInfo) { Button("About Ovvi") { openWindow(id: WindowPages.aboutScene) } }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: WindowPages.settingsScene) }.keyboardShortcut(.hotkey("app.settings"))
        }
        CommandGroup(after: .appInfo) { items(list, .app) }
        CommandGroup(replacing: .newItem) { items(list, .file) }
        CommandGroup(replacing: .saveItem) { items(list, .close) }
        CommandGroup(after: .pasteboard) { items(list, .edit) }
        CommandGroup(after: .sidebar) {
            items(list, .view)
            Menu("Pane") { CommandItems(commands: list, sections: [.paneSetting, .pane, .paneMove, .paneKeys]) }
            Divider()
            items(list, .size)
        }
        CommandGroup(after: .windowArrangement) {
            Divider()
            CommandItems(commands: list, sections: [.tabSteps, .workspaceSteps, .pages, .tabs, .workspaces,
                                                    .sessions])
        }
        CommandGroup(replacing: .help) { items(list, .help) }
    }

    private func items(_ list: [Command], _ section: Command.Section) -> some View {
        CommandItems(commands: list, sections: [section])
    }
}

struct CommandItems: View {
    let commands: [Command]
    var sections: [Command.Section]?

    var body: some View {
        let shown = sections.map { sections in
            sections.flatMap { section in commands.filter { $0.section == section } }
        } ?? commands
        let starts = shown.indices.filter { $0 == 0 || shown[$0].heading != shown[$0 - 1].heading }
        ForEach(starts, id: \.self) { start in
            let run = start ..< (starts.first { $0 > start } ?? shown.count)
            if let heading = shown[start].heading {
                Section(heading) { items(shown, run) }
            } else {
                items(shown, run)
            }
        }
    }

    private func items(_ shown: [Command], _ run: Range<Int>) -> some View {
        ForEach(run, id: \.self) { index in
            let command = shown[index]
            if index > 0, sections != nil, shown[index - 1].section != command.section {
                Divider()
            }
            Group {
                if let checked = command.checked {
                    Toggle(command.title, isOn: Binding { checked } set: { _ in command.action() })
                } else if !command.menu.isEmpty {
                    Menu(command.title) { CommandItems(commands: command.menu) }
                } else if let alternate = command.alternate {
                    // AppKit's alternate item: its key is the command's with ⌥ added.
                    Button(command.title, action: command.action).keyboardShortcut(command.key)
                        .modifierKeyAlternate(.option) { Button(alternate, action: command.action) }
                } else {
                    Button(command.title, action: command.action)
                }
            }
            .keyboardShortcut(command.alternate == nil ? command.key : nil)
            .disabled(!command.enabled)
        }
    }
}
