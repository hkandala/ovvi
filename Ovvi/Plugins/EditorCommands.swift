import HerdrKit
import SwiftUI

extension Page {
    var editor: Plugin? {
        editor(keyboardPane)
    }

    func findStep(_ step: Int, in editor: Plugin?) {
        if let editor {
            editor.command(step > 0 ? "findNext" : "findPrevious")
        } else {
            Task { await find?.step(step) }
        }
    }

    /// Only a card already made: a menu never makes one.
    func editor(_ pane: HostStore.Pane?) -> Plugin? {
        pane?.terminalID.flatMap { terminals.plugins[$0] }
            .flatMap { $0.handles("save") || $0.handles("find") ? $0 : nil }
    }
}

extension CommandList {
    /// `editor` is asked again when an item runs: the menu bar can lag the last keyboard move. A disabled item would
    /// swallow ⌘S and ⇧⌘G elsewhere (⇧⌘G is Go to Directory).
    static func editorCommands(page: Page?, pane: HostStore.Pane?, terminal: Bool,
                               _ editor: @escaping @MainActor () -> Plugin?) -> [Command]
    {
        let finder = { editor().flatMap { $0.handles("find") ? $0 : nil } }
        let save = editor()?.handles("save") == true, over = finder() != nil, find = page?.find != nil
        return [
            Command(
                section: .file,
                title: "Save",
                key: save ? .save : nil,
                group: .edit,
                symbol: "square.and.arrow.down",
                enabled: save,
            ) { editor()?.command("save") },
            Command(section: .edit, title: "Find…", key: .init("f"), symbol: "magnifyingglass",
                    keywords: "search scrollback", enabled: terminal || over, action: {
                        if let editor = finder() {
                            editor.command("find")
                        } else {
                            page?.openFind(pane)
                        }
                    }),
            Command(section: .edit, title: "Find Next", key: .findNext, symbol: "chevron.down",
                    enabled: find || over) { page?.findStep(1, in: finder()) },
            Command(section: .edit, title: "Find Previous", key: over ? .findPrevious : nil, symbol: "chevron.up",
                    enabled: find || over) { page?.findStep(-1, in: finder()) },
        ]
    }
}
