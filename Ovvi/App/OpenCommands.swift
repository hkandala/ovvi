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
                    keywords: "git diff uncommitted changes status", enabled: folder,
                    place: .init { page?.openGit("uncommitted", $0) }) { page?.openGit("uncommitted", .here) },
            Command(section: .palette, title: "Open Commit…", group: .panes, symbol: "circle.and.line.horizontal",
                    keywords: "git sha hash ref show", enabled: folder,
                    field: ("Hash or ref", { page?.openGit($0) })),
        ]
    }
}

extension Page {
    func open(path text: String, _ how: Opening = .held) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            guard let path = await resolve(text) else {
                return store.notFound(text)
            }
            await openAsCLI(path, [], how)
        }
    }

    func open(resolved path: String, _ how: Opening) {
        Task { await openAsCLI(path, [], how) }
    }

    func openGit(_ source: String, _ how: Opening = .held) {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        Task { await openAsCLI("git", [".", source], how) }
    }

    func resolve(_ text: String) async -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return await store.there(text, from: store.folder(of: keyboardPane) ?? "")
    }

    private func openAsCLI(_ first: String, _ words: [String], _ how: Opening) async {
        let pane = keyboardPane
        let cwd = await store.folder(of: pane) ?? "/"
        let call = AgentCall(store: store, pane: pane?.id ?? "", cwd: cwd, id: "", args: [])
        do {
            let (plugin, arg) = try await call.opening(first, words)
            // A card of another kind gives way to it; one of the same kind goes to it (`open`).
            if how == .here, let pane, pane.terminalID.flatMap({ terminals.plugins[$0] })?.manifest.id != plugin.id {
                replacePane(
                    pane,
                    Replacement(
                        button: "Open \(plugin.chooser ?? plugin.name)",
                        label: store.newLabel(plugin, arg: arg),
                    ),
                )
            } else {
                await open(plugin, arg: arg, from: pane?.terminalID ?? "", how: how)
            }
        } catch {
            store.show(Notice(text: (error as? AgentError)?.message ?? error.localizedDescription,
                              tone: .warning))
        }
    }
}
