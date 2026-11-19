import Foundation
import HerdrKit

/// The hook's trust hash goes in `-c hooks.state=…`, so that Codex asks nothing and no bypass flag trusts other hooks.
/// Tool approvals and questions stay in its terminal.
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

    /// A SessionStart with no rollout (a hidden thread of Codex's own) is no history.
    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        await chat.followSessions(folder + "/hooks.jsonl", on: exec, late: false, skip: CodexRollout.unread,
                                  read: CodexRollout.read) { $0["transcript_path"] as? String }
    }
}
