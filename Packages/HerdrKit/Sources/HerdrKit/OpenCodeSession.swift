import Foundation

/// opencode 1.x gives messages and their parts first from `GET /session/<id>/message`, then from the `/event`
/// stream, upserted by id.
/// `@unchecked Sendable`: its parts are JSONSerialization's immutable objects, so a copy is safe to read and change
/// on another thread.
public struct OpenCodeSession: @unchecked Sendable {
    public let id: String
    public private(set) var history = ChatHistory()
    private var messages: [String: Message] = [:]
    private var parts: [String: [String: Any]] = [:]

    public init(id: String) {
        self.id = id
    }

    private struct Message {
        let user: Bool
        let created: Date?
        let completed: Date?
        let finish: String?
        let error: String?
        let model: String?
        /// opencode's variant ("high") is the thinking effort.
        let variant: String?
        let cwd: String?
    }

    public mutating func load(_ text: String) -> Bool {
        guard let list = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else {
            return false
        }
        messages = [:]
        parts = [:]
        for item in list {
            guard let info = item["info"] as? [String: Any] else { continue }
            message(info)
            for part in item["parts"] as? [[String: Any]] ?? [] {
                self.part(part)
            }
        }
        build()
        return true
    }

    @discardableResult
    public mutating func apply(_ event: [String: Any]) -> Bool {
        let properties = event["properties"] as? [String: Any] ?? [:]
        guard properties["sessionID"] as? String == id else { return false }
        switch event["type"] as? String {
        case "message.updated": message(properties["info"] as? [String: Any] ?? [:])
        case "message.part.updated": part(properties["part"] as? [String: Any] ?? [:])
        case "message.removed":
            let message = properties["messageID"] as? String
            messages[message ?? ""] = nil
            parts = parts.filter { $0.value["messageID"] as? String != message }
        case "message.part.removed": parts[properties["partID"] as? String ?? ""] = nil
        default: return false
        }
        build()
        return true
    }

    private mutating func message(_ info: [String: Any]) {
        guard let id = info["id"] as? String else { return }
        let time = info["time"] as? [String: Any]
        let error = info["error"] as? [String: Any]
        let failure = error.map { error in
            error["name"] as? String == "MessageAbortedError" ? "Interrupted"
                : (error["data"] as? [String: Any])?["message"] as? String ?? error["name"] as? String ?? "Error"
        }
        messages[id] = Message(user: info["role"] as? String == "user", created: Self.date(time?["created"]),
                               completed: Self.date(time?["completed"]), finish: info["finish"] as? String,
                               error: failure, model: info["modelID"] as? String, variant: info["variant"] as? String,
                               cwd: (info["path"] as? [String: Any])?["cwd"] as? String)
    }

    private mutating func part(_ part: [String: Any]) {
        guard let id = part["id"] as? String, part["messageID"] is String else { return }
        parts[id] = part
    }

    /// In id order: opencode's ids sort by time.
    /// ponytail: rebuilt whole on each event (a few per step, deltas are skipped); keep entries per part if a long
    /// session gets slow.
    private mutating func build() {
        var history = ChatHistory(), turn: Date?
        let byMessage = Dictionary(grouping: parts) { $0.value["messageID"] as? String ?? "" }
        for (id, message) in messages.sorted(by: { $0.key < $1.key }) {
            if message.user {
                turn = message.created
            } else if let model = message.model {
                history.model = model
                history.effort = message.variant
            }
            for (partID, part) in (byMessage[id] ?? []).sorted(by: { $0.key < $1.key }) {
                Self.read(part, id: partID, message, into: &history)
            }
            guard !message.user else { continue }
            if let error = message.error {
                history.append(ChatEntry(id: id + ".error", .note(error, failed: error != "Interrupted"),
                                         time: message.completed))
            } else if let completed = message.completed, let finish = message.finish, finish != "tool-calls" {
                let seconds = turn.map { completed.timeIntervalSince($0) } ?? 0
                history.append(ChatEntry(id: id + ".end", .turnEnd(seconds: seconds), time: completed))
            }
        }
        self.history = history
    }

    private static func read(_ part: [String: Any], id: String, _ message: Message, into history: inout ChatHistory) {
        let time = date((part["time"] as? [String: Any])?["start"]) ?? message.created
        switch part["type"] as? String {
        case "text" where part["synthetic"] as? Bool != true && part["ignored"] as? Bool != true:
            guard let text = part["text"] as? String, !text.isEmpty else { return }
            history.append(ChatEntry(id: id, message.user ? .user(text) : .reply(text), time: time))
        case "reasoning": history.append(ChatEntry(id: id, .thinking, time: time))
        case "compaction": history.append(ChatEntry(id: id, .note("Compacted", failed: false), time: time))
        case "tool": tool(part, id: id, cwd: message.cwd, into: &history)
        default: break
        }
    }

    private static func tool(_ part: [String: Any], id: String, cwd: String?, into history: inout ChatHistory) {
        let state = part["state"] as? [String: Any] ?? [:], input = state["input"] as? [String: Any] ?? [:]
        let times = state["time"] as? [String: Any], started = date(times?["start"])
        if part["tool"] as? String == "todowrite" {
            history.append(ChatEntry(id: id, .todos(ChatTodo.list(input["todos"])), time: started))
            return
        }
        let callID = part["callID"] as? String ?? id
        let tool = part["tool"] as? String ?? "tool"
        let (category, target) = row(tool, input, cwd)
        let name = tool == "task" ? input["subagent_type"] as? String ?? "agent" : tool
        let shown = target.isEmpty ? ChatHistory.firstLine(state["title"]) : target
        history.append(ChatEntry(id: id, .tool(ChatTool(id: callID, name: name, category: category,
                                                        target: shown, input: ChatHistory.detail(input),
                                                        started: started)), time: started))
        let ended = date(times?["end"])
        switch state["status"] as? String {
        case "error":
            history.finish(tool: callID, result: ChatHistory.firstLine(state["error"]), failed: true,
                           output: ChatHistory.detail(state["error"]), at: ended)
        case "completed":
            let metadata = state["metadata"] as? [String: Any] ?? [:]
            let diff = ChatTool.DiffLine.unified(metadata["diff"] as? String ?? "")
            let text = result(metadata, diff, output: state["output"])
            history.finish(tool: callID, result: text, failed: text.hasPrefix("exit "), diff: diff,
                           output: ChatHistory.detail(state["output"]), at: ended)
        default: break
        }
    }

    private static func row(_ tool: String, _ input: [String: Any], _ cwd: String?) -> (ChatTool.Category?, String) {
        let path = (input["filePath"] as? String).map { ChatHistory.short($0, cwd) } ?? ""
        let question = (input["questions"] as? [[String: Any]])?.first?["question"]
        return switch tool {
        case "bash": (nil, ChatHistory.firstLine(input["command"]))
        case "read", "edit", "write", "multiedit", "apply_patch", "patch": (nil, path)
        case "grep", "glob", "list": (nil, ChatHistory.firstLine(input["pattern"] ?? input["path"]))
        case "websearch": (nil, ChatHistory.firstLine(input["query"]))
        case "task": (.other, ChatHistory.firstLine(input["description"]))
        case "question": (nil, ChatHistory.firstLine(question))
        default: (.other, "")
        }
    }

    private static func result(_ metadata: [String: Any], _ diff: [ChatTool.DiffLine], output: Any?) -> String {
        if let exit = metadata["exit"] as? Int, exit != 0 {
            return "exit \(exit)"
        }
        if !diff.isEmpty {
            return ChatTool.change(diff)
        }
        if let lines = (metadata["display"] as? [String: Any])?["totalLines"] as? Int {
            return ChatHistory.count(lines, "line")
        }
        return ChatHistory.firstLine(output)
    }

    /// opencode's times are milliseconds since 1970.
    private static func date(_ value: Any?) -> Date? {
        (value as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// The password stays in its 0600 file under `folder`: curl reads it from a here-document, never from argv.
public extension Exec {
    /// The server's lines are `data: {json}`, blank lines between.
    func openCodeEvents(_ url: String, folder: String) async throws -> AsyncStream<String> {
        let script = #"""
        exec curl -sN -K - "$2/event" <<EOF
        user = "opencode:$(cat "$HOME/$1/pw")"
        EOF
        """#
        return try await lines(script, [folder, url])
    }

    func openCode(_ url: String, _ path: String, body: String? = nil, folder: String) async
        -> (status: Int, body: String)?
    {
        let script = #"""
        if [ -n "$4" ]; then set -- "$1" "$2$3" -H 'content-type: application/json' --data-raw "$4"
        else set -- "$1" "$2$3"; fi
        f=$HOME/$1/pw; shift
        curl -s -K - -w '\n%{http_code}' "$@" <<EOF
        user = "opencode:$(cat "$f")"
        EOF
        """#
        // A long session's history is megabytes, over the relay too.
        guard let text = try? await output(["sh", "-c", script, "sh", folder, url, path, body ?? ""],
                                           timeout: .seconds(30)) else { return nil }
        let newline = text.lastIndex(of: "\n")
        guard let status = Int(text[(newline.map { text.index(after: $0) } ?? text.startIndex)...]), status > 0
        else { return nil }
        return (status, newline.map { String(text[..<$0]) } ?? "")
    }
}
