import Foundation

/// Where each agent keeps its session's title (resources/research/agents): Claude Code in its transcript (`ai-title`
/// lines it writes itself, `custom-title` from `/rename`), Codex in `~/.codex/session_index.jsonl` (`thread_name`),
/// pi in its session file (`session_info` from `/name`; pi names no session itself), OpenCode in its database
/// (`session.title`, the same as its server's). With no title yet, the first typed prompt (ui/window#agent-rows):
/// Claude
/// Code's and pi's from their files' first lines, Codex's from its state database's `preview`; OpenCode titles its own
/// sessions. Each script prints the lines `parse` reads, on the pane's machine.
enum SessionTitle {
    static let scripts = [
        // The id's transcript, in any project folder.
        "claude": #"f=$(ls "$HOME"/.claude/projects/*/"$1".jsonl | head -n 1); "#
            + #"grep -a '"type":"custom-title"' "$f" | tail -n 1; grep -a '"type":"ai-title"' "$f" | tail -n 1; "#
            + #"head -n 100 "$f" | grep -a '"type":"user"' | head -n 20"#,
        "codex": #"grep -a -F "\"id\":\"$1\"" "$HOME/.codex/session_index.jsonl" | tail -n 1; "#
            + #"d=$(ls -t "$HOME"/.codex/state_*.sqlite | head -n 1); [ -n "$d" ] && sqlite3 -readonly "#
            + #"-cmd '.timeout 1000' "$d" "select json_object('prompt', substr(preview, 1, 300)) from threads "#
            + #"where id = '$1'""#,
        "pi": #"grep -a '"type":"session_info"' "$1" | tail -n 1; head -n 40 "$1" | grep -a '"role":"user"' | "#
            + #"head -n 1"#,
        "opencode": #"sqlite3 -readonly -cmd '.timeout 1000' "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/"#
            + #"opencode.db" "select title from session where id = '$1'""#,
    ]

    /// The title in the script's output, else the first prompt cut at 100 characters with "…"; nil when there is none
    /// yet (OpenCode's own placeholder too).
    static func parse(agent: String, _ text: String) -> String? {
        let lines = text.split(separator: "\n").map(String.init)
        if agent == "opencode" {
            return lines.first.flatMap { $0.hasPrefix("New session - ") || $0.hasPrefix("Child session - ") ? nil : $0 }
                .flatMap(ClosedSessions.clean)
        }
        let objects = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let title = objects.lazy.compactMap { object in
            ["customTitle", "aiTitle", "thread_name", "name"].lazy.compactMap { object[$0] as? String }.first
                .flatMap(ClosedSessions.clean)
        }.first
        return title ?? objects.lazy.compactMap(prompt).compactMap(ClosedSessions.clean).first.map { prompt in
            prompt.count > 100 ? prompt.prefix(100).trimmingCharacters(in: .whitespaces) + "…" : prompt
        }
    }

    /// A line's typed prompt: Codex's `preview`, or a user message's text (not Claude Code's meta lines or its
    /// commands' wrappers, which start with `<`).
    private static func prompt(_ object: [String: Any]) -> String? {
        if let preview = object["prompt"] as? String {
            return preview
        }
        guard let message = object["message"] as? [String: Any], message["role"] as? String == "user",
              object["isMeta"] as? Bool != true else { return nil }
        let content = message["content"]
        let text = content as? String
            ?? (content as? [[String: Any]])?.first { $0["type"] as? String == "text" }?["text"] as? String
        return text.flatMap { $0.hasPrefix("<") ? nil : $0 }
    }
}

public extension Exec {
    /// The title of an agent's session, from herdr's `agent_session` value; nil when it has none yet, or for an agent
    /// with no known place for one.
    func sessionTitle(agent: String, session: String) async -> String? {
        // pi's is a file; the others' ids go into OpenCode's SQL and Claude Code's file name: letters, digits, `-` and
        // `_` only.
        let plain = session.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }
        let id = !session.isEmpty && plain
        guard let script = SessionTitle.scripts[agent], agent == "pi" ? session.hasPrefix("/") : id else { return nil }
        let text = try? await output(["sh", "-c", "{ \(script); } 2>/dev/null", "sh", session], timeout: .seconds(5))
        return SessionTitle.parse(agent: agent, text ?? "")
    }
}
