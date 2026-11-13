import Foundation
import HerdrKit

/// The hook's trust hash goes in `-c hooks.state=…`, so that Codex asks nothing and no bypass flag trusts other hooks.
/// Tool approvals and questions stay in its terminal: herdr reports them as blocked.
struct Codex: ChatAdapter {
    static let command = "codex"
    let token: String
    static let stopKeys = ["escape"]
    static let quit = "/quit"

    /// Codex runs it with the user's login shell (`$SHELL -lc`), fish too: plain commands with no variable of its
    /// own, no quote and no backslash. It runs at each session's first prompt, not at launch.
    /// ponytail: `$HOME` unquoted, so a home folder with a space gets no chat.
    static func hook(_ token: String) -> String {
        // `awk 1`: the line and its newline in one write, so two hooks at once never share a line.
        let folder = "$HOME/\(ChatAdapters.folder(token))"
        return "umask 077;mkdir -p \(folder);awk 1 >>\(folder)/hooks.jsonl;" + ChatAdapters.sweep
    }

    /// The trust key is the `-c` layer's own (`codex-rs/hooks`); an inline table, as the `-c` parser splits a dotted
    /// key on every dot. `resume` after them: `codex resume` takes the overrides ahead of it.
    static func flags(_ token: String, resume: String?) -> String {
        let hook = hook(token), trust = CodexRollout.trust(hook)
        return #"-c 'hooks.SessionStart=[{hooks=[{type="command",command="\#(hook)"}]}]' "#
            + #"-c 'hooks.state={"/<session-flags>/config.toml:session_start:0:0"={trusted_hash="\#(trust)"}}'"#
            + (resume.map { " " + $0 } ?? "")
    }

    static func resume(_ session: String) -> String? {
        ChatAdapters.uuid(session).map { "resume \($0)" }
    }

    /// The hook names a resumed session only at its first prompt: the side file names its rollout first.
    static func prepare(_ token: String, resume: String?, arguments: String, on exec: any Exec) async -> String? {
        if let session = resume?.split(separator: " ").last {
            await CodexRollout.name(String(session), in: ChatAdapters.folder(token) + "/hooks.jsonl",
                                    home: HostStore.archivedHome, on: exec)
        }
        return command + arguments + " " + flags(token, resume: resume)
    }

    /// The launcher's `codex` and the native binary both carry the `hooks.SessionStart` value.
    init?(_ foreground: [Program.Foreground]) {
        guard let token = ChatAdapters.marked(foreground, { argv in
            argv.lazy.compactMap { $0.hasPrefix("hooks.SessionStart=") ? ChatAdapters.token(in: $0) : nil }.first
        })?.token else { return nil }
        self.init(token: token, pids: [])
    }

    init(token: String, pids _: [Int]) {
        self.token = token
    }

    /// Ends when the side file's stream does (a lost connection), so the core follows again.
    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        await withTaskGroup { group in
            group.addTask { await sessions(chat, exec) }
            group.addTask { await screens(chat) }
            await group.next()
            group.cancelAll()
        }
    }

    /// A SessionStart with no rollout (a hidden thread of Codex's own) is no history.
    @MainActor private func sessions(_ chat: Chat, _ exec: any Exec) async {
        await chat.followSessions(folder + "/hooks.jsonl", on: exec, late: false, skip: CodexRollout.unread,
                                  read: CodexRollout.read) { $0["transcript_path"] as? String }
    }

    /// herdr reports a picker or a dialog as idle: a screen whose last rows lack the input box above the status row
    /// waits too (two reads in a row, not a redraw). The last rows, not the visible ones: the user may have scrolled
    /// the pane. The first read alone decides when the chat shows on an open picker. A message not sent with no
    /// session yet: the hook did not run (a trust hash Codex rejects, hooks turned off).
    @MainActor private func screens(_ chat: Chat) async {
        var misses = 1
        while !Task.isCancelled {
            // A kept chat out of view reads nothing and keeps its last state.
            if chat.store?.inView.contains(chat.paneID) == true {
                var ready = true
                if let state = chat.store?.pane(chat.paneID)?.state, state != .needsYou,
                   let client = chat.store?.client,
                   let screen = try? await client.recent(chat.paneID, lines: 8)
                {
                    ready = CodexRollout.ready(screen)
                }
                misses = ready ? 0 : misses + 1
                if chat.source == nil, chat.problem == nil, chat.outgoing.contains(where: \.notSent) {
                    chat.problem = "Codex has not started a session"
                }
                let recorded: Chat.Phase? = misses >= 2 ? .waiting : nil
                // Only a change: Observation reports equal writes too.
                if !Task.isCancelled, chat.recorded != recorded {
                    chat.recorded = recorded
                }
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}
