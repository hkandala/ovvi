import CryptoKit
import Foundation
import HerdrKit

struct PiAgent: ChatAdapter {
    static let command = "pi"
    let token: String
    static let stopKeys = ["escape"]
    static let quit = "/quit"
    static let resumesAnywhere = true
    private let kept = Kept()

    @MainActor private final class Kept {
        var transcript = PiTranscript()

        nonisolated init() {}
    }

    /// Named by its content, so that two versions of Ovvi never fight over one file.
    private static let source = Bundle.main.url(forResource: "pi-ovvi", withExtension: "ts")
        .flatMap { try? Data(contentsOf: $0) }
    private static let file = source.map { source in
        ChatAdapters.cache + "/pi-ovvi-" + SHA256.hash(data: source).prefix(4).map { String(format: "%02x", $0) }
            .joined()
            + ".ts"
    }

    /// pi-ovvi makes its folder.
    private static func state(_ token: String) -> String {
        ChatAdapters.folder(token) + "/pi.jsonl"
    }

    static func flags(_ token: String, resume: String?) -> String {
        "-e ~/\(file ?? "") --ovvi ~/\(state(token))" + (resume.map { " " + $0 } ?? "")
    }

    /// herdr's pi integration reports the session's file. Single quotes read the same in sh, bash, zsh and fish when
    /// the path holds no quote and no backslash.
    static func resume(_ session: String) -> String? {
        guard session.hasPrefix("/"), !session.contains(where: { "'\\".contains($0) }),
              !session.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return "--session '\(session)'"
    }

    /// Base64, as the relay passes lines; a temporary file, then a rename. pi exits at once when `-e` names no file.
    static func prepare(_ token: String, resume: String?, arguments: String, on exec: any Exec) async -> String? {
        guard let source, let file else { return nil }
        let script = #"""
        umask 077; d=$HOME/\#(ChatAdapters.cache); f=$HOME/$1
        mkdir -p "$d" && chmod 700 "$d" && base64 -d >"$f.$$" && mv "$f.$$" "$f" || exit 1
        \#(ChatAdapters.sweep); exit 0
        """#
        guard await exec.succeeds(script, [file], input: [source.base64EncodedString()]) else { return nil }
        return command + arguments + " " + flags(token, resume: resume)
    }

    /// The launcher's `pi` and its `pi.real` both carry `--ovvi`.
    init?(_ foreground: [Program.Foreground]) {
        guard let token = ChatAdapters.marked(foreground, { argv in
            argv.after("--ovvi").flatMap { path in
                ChatAdapters.token(in: path).flatMap { path.hasSuffix("/\($0)/pi.jsonl") ? $0 : nil }
            }
        })?.token else { return nil }
        self.init(token: token, pids: [])
    }

    init(token: String, pids _: [Int]) {
        self.token = token
    }

    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        let parser = Chat.Parser(take: { [kept] in
            defer { kept.transcript = PiTranscript() }
            return kept.transcript
        }, put: { [kept] in kept.transcript = $0 }, read: { transcript, line, end, history in
            transcript.read(line, end: end, into: &history)
        }, restarted: { [kept] in kept.transcript = PiTranscript() })
        await chat.followSessions(Self.state(token), on: exec, late: true, parser: parser) { read($0, chat) }
    }

    /// pi-working's words, as its prompt box says them.
    static func waiting(_ agents: Int, _ jobs: Int) -> String? {
        let parts = [(agents, "agent"), (jobs, "background job")].filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return parts.isEmpty ? nil : "Waiting on " + parts.joined(separator: " and ")
    }

    @MainActor private func read(_ object: [String: Any], _ chat: Chat) -> String? {
        switch object["type"] as? String {
        case "session":
            guard let source = object["path"] as? String else { return nil }
            if source != chat.source {
                kept.transcript = PiTranscript()
            }
            return source
        case "tree":
            chat.change { kept.transcript.tree(object["leaf"] as? String, at: object["at"] as? Int ?? 0, into: &$0) }
            return nil
        case "waiting":
            let waiting = Self.waiting(object["agents"] as? Int ?? 0, object["jobs"] as? Int ?? 0)
            // Only a change: Observation reports equal writes too.
            if chat.waiting != waiting {
                chat.waiting = waiting
            }
            return nil
        default: return nil
        }
    }
}
