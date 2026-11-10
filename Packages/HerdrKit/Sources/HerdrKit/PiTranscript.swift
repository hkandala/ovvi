import Foundation

/// pi's entries form a tree by `id` and `parentId`; the history is the branch from the leaf back to the root.
public struct PiTranscript: Sendable {
    private var nodes: [String: Node] = [:]
    private var leaf: String?
    private var cwd: String?
    /// ponytail: a file pi rewrites in place keeps the offsets and nodes read from it; the nodes heal by id, a pending
    /// move may be lost.
    private var offset = 0
    private var moves: [(leaf: String?, size: Int)] = []

    public init() {}

    private struct Node {
        let parent: String?
        let steps: [Step]
    }

    private enum Step {
        case add(ChatEntry)
        case finish(id: String, result: String, failed: Bool, diff: [ChatTool.DiffLine], output: String,
                    calls: [ChatTool] = [], time: Date?)
        case model(String, effort: String?)
    }

    /// The entry becomes the leaf: pi appends to its leaf.
    @discardableResult
    public mutating func read(_ line: String, end: Int, into history: inout ChatHistory) -> Bool {
        offset = end
        defer {
            while let move = moves.first, move.size <= end {
                moves.removeFirst()
                if move.size == end {
                    self.move(to: move.leaf, into: &history)
                }
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return false
        }
        if object["type"] as? String == "session" {
            cwd = object["cwd"] as? String
            return true
        }
        guard let id = object["id"] as? String else { return true }
        let node = Node(parent: object["parentId"] as? String, steps: steps(object, id: id))
        nodes[id] = node
        if node.parent != nil, node.parent == leaf {
            leaf = id
            Self.apply(node.steps, to: &history)
        } else {
            move(to: id, into: &history)
        }
        return true
    }

    /// pi writes nothing to the file for a `/tree` move (`leaf` nil: ahead of the first entry). The move shows once the
    /// file is read up to `size` (the state file and this one are two streams), and never when the file is read past
    /// it: the entries after it grew from the new leaf.
    public mutating func tree(_ leaf: String?, at size: Int, into history: inout ChatHistory) {
        if size == offset {
            move(to: leaf, into: &history)
        } else if size > offset {
            moves.append((leaf, size))
        }
    }

    private mutating func move(to leaf: String?, into history: inout ChatHistory) {
        self.leaf = leaf
        var branch: [Node] = [], id = leaf
        while let current = id, let node = nodes[current], branch.count < nodes.count {
            branch.append(node)
            id = node.parent
        }
        history = ChatHistory()
        for node in branch.reversed() {
            Self.apply(node.steps, to: &history)
        }
    }

    private static func apply(_ steps: [Step], to history: inout ChatHistory) {
        for step in steps {
            switch step {
            case let .add(entry): history.append(entry)
            case let .finish(id, result, failed, diff, output, calls, time):
                history.finish(tool: id, result: result, failed: failed, diff: diff, output: output, calls: calls,
                               at: time)
            case let .model(model, effort):
                history.model = model
                history.effort = effort
            }
        }
    }

    private func steps(_ object: [String: Any], id: String) -> [Step] {
        let time = (object["timestamp"] as? String).flatMap(ChatHistory.date)
        switch object["type"] as? String {
        case "message": break
        case let type? where ["compaction", "branch_summary"].contains(type):
            let text = type == "compaction" ? "Compacted" : "Summarized the branch"
            return [.add(ChatEntry(id: id, .note(text, failed: false), time: time))]
        default: return []
        }
        let message = object["message"] as? [String: Any] ?? [:]
        let blocks = message["content"] as? [[String: Any]] ?? []
        switch message["role"] as? String {
        case "user":
            let texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            let text = message["content"] as? String ?? texts.joined(separator: "\n")
            return text.isEmpty ? [] : [.add(ChatEntry(id: id, .user(text), time: time))]
        case "assistant": return assistant(message, blocks, id: id, time: time)
        case "toolResult":
            guard let call = message["toolCallId"] as? String else { return [] }
            return [result(message, blocks, call: call, time: time)]
        case "bashExecution":
            let code = message["exitCode"] as? Int
            let tool = ChatTool(id: id, name: "bash",
                                target: ChatHistory.firstLine(message["command"]),
                                input: ChatHistory.detail(message["command"]), started: time)
            let result = message["cancelled"] as? Bool == true ? "cancelled" : code.map { "exit \($0)" } ?? ""
            return [.add(ChatEntry(id: id, .tool(tool), time: time)),
                    .finish(id: id, result: result, failed: code.map { $0 != 0 } ?? false, diff: [],
                            output: ChatHistory.detail(message["output"]), time: time)]
        default: return []
        }
    }

    private func assistant(_ message: [String: Any], _ blocks: [[String: Any]], id: String, time: Date?) -> [Step] {
        var steps: [Step] = []
        if let model = message["model"] as? String {
            steps.append(.model(model, effort: message["thinkingLevel"] as? String))
        }
        for (index, block) in blocks.enumerated() {
            let entry = "\(id).\(index)"
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String, !text.isEmpty else { continue }
                steps.append(.add(ChatEntry(id: entry, .reply(text), time: time)))
            case "thinking": steps.append(.add(ChatEntry(id: entry, .thinking, time: time)))
            case "toolCall":
                steps.append(.add(ChatEntry(id: entry, .tool(tool(block, id: entry, time: time)), time: time)))
            default: break
            }
        }
        // Esc while it streams is `aborted`; Esc during a tool is an error that says so.
        let error = message["errorMessage"] as? String ?? ""
        switch message["stopReason"] as? String {
        case "aborted": steps.append(.add(ChatEntry(id: "\(id).end", .note("Interrupted", failed: false), time: time)))
        case "error":
            let note = error.contains("aborted") ? ChatEntry.Kind.note("Interrupted", failed: false)
                : .note(ChatHistory.firstLine(error.isEmpty ? "Error" : error), failed: true)
            steps.append(.add(ChatEntry(id: "\(id).end", note, time: time)))
        default: break
        }
        return steps
    }

    private func tool(_ block: [String: Any], id: String, time: Date?) -> ChatTool {
        let name = block["name"] as? String ?? "tool", input = block["arguments"] as? [String: Any] ?? [:]
        let path = ChatHistory.short(input["path"] as? String ?? "", cwd)
        let (category, target): (ChatTool.Category?, String) = switch name {
        case "read", "edit", "write", "ls": (nil, path)
        case "bash": (nil, ChatHistory.firstLine(input["command"]))
        case "grep", "find": (nil, ChatHistory.firstLine(input["pattern"]))
        default: (.other, ChatHistory.firstText(input))
        }
        return ChatTool(id: block["id"] as? String ?? id, name: name, category: category, target: target,
                        input: ChatHistory.detail(input), started: time)
    }

    private static func arguments(_ text: String) -> Any? {
        let match = text.firstMatch(of: /"(path|command|pattern)":"(?:[^"\\]|\\.)*"/)
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8)))
            ?? match.flatMap { try? JSONSerialization.jsonObject(with: Data("{\($0.0)}".utf8)) }
    }

    private func result(_ message: [String: Any], _ blocks: [[String: Any]], call: String, time: Date?) -> Step {
        let failed = message["isError"] as? Bool == true, details = message["details"] as? [String: Any]
        let content = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `-12 removed`, `+12 added`, ` 13 same`; `   ...` between hunks has no number.
        let diff: [ChatTool.DiffLine] = (details?["diff"] as? String ?? "")
            .split(separator: "\n").compactMap { line in
                guard let mark = line.first, "+- ".contains(mark) else { return nil }
                let rest = line.dropFirst().drop { $0 == " " }, digits = rest.prefix { $0.isNumber }
                guard let number = Int(digits) else { return nil }
                return ChatTool.DiffLine(mark: mark, number: number, text: String(rest.dropFirst(digits.count + 1)))
            }
        let text: String
        if failed {
            let last = content.split(separator: "\n").last.map(String.init) ?? ""
            text = last.hasPrefix("Command exited with code ") ? "exit " + last.dropFirst(25)
                : ChatHistory.firstLine(content)
        } else if !diff.isEmpty {
            text = ChatTool.change(diff)
        } else if message["toolName"] as? String == "read" {
            text = ChatHistory.count(content.split(separator: "\n", omittingEmptySubsequences: false).count, "line")
        } else {
            text = ChatHistory.firstLine(content)
        }
        // A codemode script's calls, tools and models alike, as rows of pi's own tools; it tells their time taken and
        // their arguments: whole in `nestedCalls` unless large, else as JSON text cut at 200 characters in `details`.
        let cut = details?["calls"] as? [[String: Any]] ?? []
        let nested = (message["nestedCalls"] as? [String: Any])?["calls"] as? [[String: Any]] ?? cut
        let calls = nested.enumerated().map { index, step in
            var block = step
            let text = step["args"] as? String ?? (cut.indices.contains(index) ? cut[index]["args"] as? String : nil)
            block["arguments"] = step["arguments"] ?? text.flatMap(Self.arguments)
            let seconds = (step["durationMs"] as? Double ?? 0) / 1000
            var row = tool(block, id: "\(call)/\(index + 1)", time: time?.addingTimeInterval(-seconds))
            row.failed = step["status"] as? String == "error"
            row.result = row.failed ? ChatHistory.firstLine(step["error"] ?? "failed") : ""
            row.output = ChatHistory.detail(step["error"])
            row.ended = time
            return row
        }
        return .finish(id: call, result: text, failed: failed, diff: diff, output: ChatHistory.detail(content),
                       calls: calls, time: time)
    }
}
