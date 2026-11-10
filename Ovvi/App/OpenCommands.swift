import HerdrKit
import SwiftUI

extension CommandList {
    static func opens(_ page: Page?) -> [Command] {
        let folder = page?.keyboardPane?.cwd != nil
        return [
            Command(section: .palette, title: "Open File…", group: .panes, symbol: "doc",
                    keywords: "path paste preview image video markdown", enabled: page?.selectedTab != nil,
                    field: ("Path", { page?.open(path: $0) })),
            Command(section: .palette, title: "Open Working Tree", group: .panes, symbol: "plusminus",
                    keywords: "git diff uncommitted changes status", enabled: folder) { page?.openGit("uncommitted") },
            Command(section: .palette, title: "Open Commit…", group: .panes, symbol: "smallcircle.filled.circle",
                    keywords: "git sha hash ref show", enabled: folder,
                    field: ("Hash or ref", { page?.openGit($0) })),
        ]
    }
}

extension Page {
    /// ⌥ is read as the key or click comes in.
    func open(path text: String) {
        let how = Self.how
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            guard let path = await resolve(text) else {
                return store.notFound(text)
            }
            await openAsCLI(path, [], how)
        }
    }

    func open(resolved path: String) {
        let how = Self.how
        Task { await openAsCLI(path, [], how) }
    }

    func openGit(_ source: String) {
        let how = Self.how, source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        Task { await openAsCLI("git", [keyboardPane?.cwd ?? "", source], how) }
    }

    func resolve(_ text: String) async -> String? {
        await store.there(text.trimmingCharacters(in: .whitespacesAndNewlines), from: keyboardPane?.cwd ?? "")
    }

    private static var how: Opening {
        NSApp.currentEvent?.modifierFlags.contains(.option) == true ? .side : .tab
    }

    private func openAsCLI(_ first: String, _ words: [String], _ how: Opening) async {
        let pane = keyboardPane
        let call = AgentCall(store: store, pane: pane?.id ?? "", cwd: pane?.cwd ?? "/", id: "", args: [])
        do {
            let (plugin, arg) = try await call.opening(first, words)
            await open(plugin, arg: arg, from: pane?.terminalID ?? "", how: how)
        } catch {
            store.show(Notice(text: (error as? AgentError)?.message ?? error.localizedDescription,
                              tone: .warning))
        }
    }
}
