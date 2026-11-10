import Foundation

extension Chooser {
    /// Its command is its program icon's id too.
    struct Agent: Equatable {
        let name: String, adapter: any ChatAdapter.Type, install: String

        var command: String {
            adapter.command
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.command == rhs.command
        }
    }

    static let agents = [
        Agent(name: "Claude Code", adapter: ClaudeCode.self, install: "npm install -g @anthropic-ai/claude-code"),
        Agent(name: "Codex", adapter: Codex.self, install: "npm install -g @openai/codex"),
        Agent(name: "Pi", adapter: PiAgent.self, install: "npm install -g @mariozechner/pi-coding-agent"),
        Agent(name: "OpenCode", adapter: OpenCode.self, install: "npm install -g opencode-ai"),
    ]

    /// A command is herdr's agent name too.
    static func agent(_ command: String?) -> Agent? {
        agents.first { $0.command == command }
    }

    static func name(_ command: String) -> String {
        agent(command)?.name ?? command
    }

    static func argumentsKey(_ command: String) -> String {
        "agentArguments.\(command)"
    }

    static func arguments(_ command: String) -> String {
        let text = allowed(UserDefaults.standard.string(forKey: argumentsKey(command)) ?? "")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "" : " " + text
    }

    /// No line break, quote or backslash: the text goes into a typed line.
    static func allowed(_ text: String) -> String {
        text.filter { !"\"'\\".contains($0) && !$0.isNewline }
    }
}
