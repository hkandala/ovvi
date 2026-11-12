import Foundation
import HerdrKit

/// The marker is `-- ovvi-T` after the flags (opencode ignores what follows `--`), and the state line's pid must be
/// the marked process's.
struct OpenCode: ChatAdapter {
    static let command = "opencode"
    let token: String
    let pids: [Int]
    /// The first Esc only arms the interrupt.
    static let stopKeys = ["escape", "escape"]
    static let quit = "/exit"

    static func flags(_ token: String, resume: String?) -> String {
        (resume.map { $0 + " " } ?? "") + "--port 0 --hostname 127.0.0.1 -- ovvi-\(token)"
    }

    static func resume(_ session: String) -> String? {
        isID(session) ? "--session \(session)" : nil
    }

    /// The plugin and its `tui.json` go whole, then renamed: another pane may be starting. The password goes from its
    /// file into the environment, never into argv or the scrollback. The line reads the same in sh, bash, zsh and
    /// fish (3.4 and later).
    /// ponytail: a home folder with a `"` breaks `tui.json`; escape it if one shows up. A pane running for 30 days
    /// loses its password file to the sweep (the chat says the server did not answer); touch it while followed if that
    /// matters.
    static func prepare(_ token: String, resume: String?, arguments: String, on exec: any Exec) async -> String? {
        let script = #"""
        umask 077; c=$HOME/\#(ChatAdapters.cache); d=$HOME/\#(ChatAdapters.root)/$1; p=$c/opencode/ovvi-tui.js
        mkdir -p "$c/opencode" "$d" && cat >"$p.$$" && mv "$p.$$" "$p" && t=$c/opencode/tui.json &&
        printf '{"plugin":["%s"]}\n' "$p" >"$t.$$" && mv "$t.$$" "$t" &&
        od -An -tx1 -N16 /dev/urandom | tr -d ' \n' >"$d/pw" || exit 1
        \#(ChatAdapters.sweep); exit 0
        """#
        guard let plugin,
              await exec.succeeds(script, [token], input: plugin.split(separator: "\n").map(String.init))
        else {
            return nil
        }
        let folder = "$HOME/\(ChatAdapters.folder(token))"
        return "OVVI_OC_STATE=\(folder)/state.jsonl OPENCODE_TUI_CONFIG=$HOME/\(ChatAdapters.cache)/opencode/tui.json "
            + "OPENCODE_SERVER_PASSWORD=$(cat \"\(folder)/pw\") \(command)\(arguments) \(flags(token, resume: resume))"
    }

    static let plugin = Bundle.main.url(forResource: "opencode-ovvi", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    init?(_ foreground: [Program.Foreground]) {
        guard let (token, pids) = ChatAdapters.marked(foreground, { argv in
            guard argv.contains("--port"), let marker = argv.after("--"), marker.hasPrefix("ovvi-") else { return nil }
            return ChatAdapters.token(marker.dropFirst(5))
        }) else { return nil }
        self.init(token: token, pids: pids)
    }

    init(token: String, pids: [Int]) {
        self.token = token
        self.pids = pids
    }

    /// No state line after 15 s (the company build ignores the plugin): the card shows its terminal.
    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        let waits = Waits()
        var server: Task<Void, Never>?, followed: String?
        defer { server?.cancel() }
        let late = Task {
            try? await Task.sleep(for: .seconds(15))
            // Once: a user who went back to the chat stays there.
            if !Task.isCancelled, chat.source == nil, chat.problem != Self.unreported {
                chat.problem = Self.unreported
                chat.showsChat = false
            }
        }
        defer { late.cancel() }
        // From the start each time: the last line holds the server and session.
        guard let lines = try? await exec.follow(folder + "/state.jsonl", from: FileMark()) else { return }
        for await batch in lines {
            // The batch's last state only: a launch's first one has no session yet, which would clear the history.
            guard !Task.isCancelled, let (state, url) = batch.reversed().lazy.compactMap(state).first else { continue }
            let session = (state["session"] as? String).flatMap { Self.isID($0) ? $0 : nil }
            if chat.problem == Self.unreported {
                chat.problem = nil
            }
            waits.dialog = state["dialog"] as? Bool == true
            let source = url + " " + (session ?? "")
            if followed != source {
                followed = source
                server?.cancel()
                waits.requests = []
                waits.busy = nil
                if chat.source != source {
                    chat.history = ChatHistory()
                    chat.source = source
                    chat.problem = chat.problem?.hasPrefix(Self.serverProblem) == true ? nil : chat.problem
                }
                // No session yet: a new conversation.
                if session == nil {
                    chat.current = true
                }
                server = session.map { session in
                    Task {
                        while !Task.isCancelled {
                            await self.server(chat, url, session, waits, exec)
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
            }
            waits.publish(chat)
        }
    }

    private func state(_ line: FollowedLine) -> ([String: Any], String)? {
        guard case let .line(text, _) = line,
              let state = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let pid = state["pid"] as? Int, pids.contains(pid),
              let url = state["url"] as? String, url.wholeMatch(of: /http:\/\/127\.0\.0\.1:[0-9]{1,5}/) != nil
        else { return nil }
        return (state, url)
    }

    /// The history once the event stream is connected, so that nothing falls between the two.
    @MainActor private func server(_ chat: Chat, _ url: String, _ id: String, _ waits: Waits,
                                   _ exec: any Exec) async
    {
        guard let events = try? await exec.openCodeEvents(url, folder: folder) else { return }
        var lines = events.makeAsyncIterator(), connected = false
        while !connected, let line = await lines.next() {
            connected = line.contains(#""server.connected""#)
        }
        guard !Task.isCancelled else { return }
        guard connected else {
            chat.problem = Self.serverProblem + " did not answer"
            return
        }
        guard var session = await history(chat, url, id, exec) else { return }
        chat.history = session.history
        chat.current = true
        await waits.load(url, folder, exec, chat)
        while let line = await lines.next() {
            guard line.hasPrefix("data: ") else { continue }
            let (changed, waited) = await Self.apply(line, to: session)
            guard !Task.isCancelled else { return }
            if let changed {
                session = changed
                chat.history = changed.history
            }
            // Read again here: its JSON objects are not Sendable.
            if waited, let event = Self.event(line), waits.take(event, session: id, url: url) {
                waits.publish(chat)
            }
        }
    }

    private static func apply(_ line: String, to session: OpenCodeSession) async -> (OpenCodeSession?, Bool) {
        await Task.detached {
            var session = session
            let event = Self.event(line)
            let changed = event.map { session.apply($0) } == true
            return (changed ? session : nil, (event?["type"] as? String).map(Waits.reads) == true)
        }.value
    }

    private nonisolated static func event(_ line: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8.dropFirst(6))) as? [String: Any]
    }

    @MainActor private func history(_ chat: Chat, _ url: String, _ id: String,
                                    _ exec: any Exec) async -> OpenCodeSession?
    {
        chat.loading = true
        defer { chat.loading = false }
        let answer = await exec.openCode(url, "/session/\(id)/message", folder: folder)
        guard !Task.isCancelled else { return nil }
        let session = await Task.detached { [answer] in
            var session = OpenCodeSession(id: id)
            return answer?.status == 200 && session.load(answer?.body ?? "") ? session : nil
        }.value
        guard !Task.isCancelled else { return nil }
        guard let session else {
            chat.problem = Self.serverProblem + " did not give the session" + (answer.map { " (\($0.status))" } ?? "")
            return nil
        }
        if chat.problem?.hasPrefix(Self.serverProblem) == true {
            chat.problem = nil
        }
        return session
    }

    /// A slow first start (opencode installs its plugin packages first) may still report.
    static let unreported = "OpenCode has not reported its session"
    static let serverProblem = "OpenCode's server"

    /// opencode's ids (`ses_…`, `per_…`, `que_…`) as they go into a URL.
    static func isID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    static let replies = [("Allow once", "once"), ("Allow always", "always"), ("Reject", "reject")]

    /// A request already answered in the TUI gets a 404: its `replied` event takes the card away.
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async -> Bool {
        guard let request = try? JSONSerialization.jsonObject(with: question.raw) as? [String: String],
              let kind = request["kind"], let id = request["id"], let url = request["url"]
        else { return false }
        let body: Any = kind == "permission"
            ? ["reply": Self.replies.first { $0.0 == answers.values.first }?.1 ?? "reject"]
            : ["answers": question.items.map { [answers[$0.text] ?? ""] }]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let status = await exec.openCode(url, "/\(kind)/\(id)/reply", body: String(decoding: data, as: UTF8.self),
                                               folder: folder)?.status else { return false }
        return (200 ..< 300).contains(status) || status == 404
    }
}

@MainActor private final class Waits {
    var dialog = false
    var busy: Bool?
    var fresh = false
    var requests: [(id: String, question: ChatQuestion?)] = []

    func add(_ kind: String, _ request: [String: Any], _ url: String) {
        guard let id = request["id"] as? String, OpenCode.isID(id), !requests.contains(where: { $0.id == id })
        else { return }
        var items: [ChatQuestion.Item] = []
        if kind == "permission" {
            let metadata = request["metadata"] as? [String: Any]
            let target = metadata?["command"] as? String
                ?? (request["patterns"] as? [String] ?? []).joined(separator: ", ")
            let name = (request["permission"] as? String ?? "tool").capitalized
            items = [ChatQuestion.Item(text: target.isEmpty ? name : "\(name): \(target)",
                                       options: OpenCode.replies.map(\.0))]
        } else {
            items = ChatQuestion.items(request["questions"] as? [[String: Any]] ?? [], several: "multiple") ?? []
        }
        let raw = try? JSONSerialization.data(withJSONObject: ["kind": kind, "id": id, "url": url])
        requests.append((id, items.isEmpty ? nil : raw.map { ChatQuestion(items: items, raw: $0) }))
        // opencode's ids sort by time after their kind's prefix.
        requests.sort { $0.id.dropFirst(4) < $1.id.dropFirst(4) }
    }

    /// All at once, so that a publish meanwhile keeps the listed ones. A status from a dropped stream may be stale; a
    /// card answered then (the answer may be lost) shows again.
    func load(_ url: String, _ folder: String, _ exec: any Exec, _ chat: Chat) async {
        busy = nil
        defer {
            fresh = true
            if !Task.isCancelled {
                publish(chat)
            }
        }
        var lists: [(String, [[String: Any]])] = []
        for kind in ["permission", "question"] {
            let body = await exec.openCode(url, "/\(kind)", folder: folder)?.body ?? ""
            lists.append((kind, (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [[String: Any]] ?? []))
        }
        requests = []
        for (kind, list) in lists {
            for request in list {
                add(kind, request, url)
            }
        }
    }

    nonisolated static func reads(_ type: String) -> Bool {
        type.hasPrefix("permission.") || type.hasPrefix("question.") || ["session.status", "session.idle"]
            .contains(type)
    }

    func take(_ event: [String: Any], session id: String, url: String) -> Bool {
        let properties = event["properties"] as? [String: Any] ?? [:]
        let own = properties["sessionID"] as? String == id
        switch event["type"] as? String {
        case "session.status" where own:
            busy = (properties["status"] as? [String: Any])?["type"] as? String != "idle"
        case "session.idle" where own: busy = false
        case "permission.asked": add("permission", properties, url)
        case "question.asked": add("question", properties, url)
        case "permission.replied", "question.replied", "question.rejected":
            requests.removeAll { $0.id == properties["requestID"] as? String }
        default: return false
        }
        return true
    }

    func publish(_ chat: Chat) {
        let phase: Chat.Phase? = dialog || !requests.isEmpty ? .waiting : busy == true ? .working : nil
        // Only a change: Observation reports equal writes too.
        if chat.recorded != phase {
            chat.recorded = phase
        }
        let question = dialog ? nil : requests.first?.question
        if fresh || chat.question?.raw != question?.raw {
            chat.question = question
            fresh = false
        }
    }
}
