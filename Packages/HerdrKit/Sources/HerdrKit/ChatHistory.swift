import Foundation

public struct ChatHistory: Equatable, Sendable {
    public private(set) var entries: [ChatEntry] = []
    public var model: String?
    public var effort: String?
    private var tools: [String: Int] = [:]

    public init() {}

    public mutating func append(_ entry: ChatEntry) {
        if case let .tool(tool) = entry.kind {
            tools[tool.id] = entries.count
        }
        entries.append(entry)
    }

    public mutating func finish(tool id: String, result: String, failed: Bool, diff: [ChatTool.DiffLine] = [],
                                output: String = "", calls: [ChatTool] = [], at time: Date?)
    {
        guard let index = tools.removeValue(forKey: id), case var .tool(tool) = entries[index].kind else { return }
        tool.result = result
        tool.output = output
        tool.calls = calls
        tool.failed = failed
        tool.diff = diff.isEmpty ? tool.diff : diff
        tool.ended = time
        entries[index].kind = .tool(tool)
    }
}

public struct ChatEntry: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case user(String)
        case reply(String)
        case thinking
        case tool(ChatTool)
        case todos([ChatTodo])
        case note(String, failed: Bool)
        case turnEnd(seconds: Double)
    }

    public let id: String
    public var kind: Kind
    public let time: Date?

    public init(id: String, _ kind: Kind, time: Date?) {
        self.id = id
        self.kind = kind
        self.time = time
    }
}

public extension ChatEntry {
    var tool: ChatTool? {
        if case let .tool(tool) = kind {
            tool
        } else {
            nil
        }
    }
}

extension ChatEntry {
    var user: String? {
        if case let .user(text) = kind {
            text
        } else {
            nil
        }
    }

    var seconds: Double? {
        if case let .turnEnd(seconds) = kind {
            seconds
        } else {
            nil
        }
    }

    var isStep: Bool {
        tool != nil || kind == .thinking
    }

    var row: ChatRow? {
        switch kind {
        case let .reply(text): .reply(id: id, text: text)
        case let .todos(todos): .todos(id: id, todos)
        case let .note(text, failed): .note(id: id, text: text, failed: failed)
        case .user, .tool, .thinking, .turnEnd: nil
        }
    }
}

public struct ChatTool: Equatable, Sendable {
    public enum Category: Sendable {
        case read, edit, command, search, other
    }

    public struct DiffLine: Equatable, Sendable {
        public let mark: Character
        public let number: Int
        public let text: String
    }

    public let id: String
    public let name: String
    public let category: Category
    public let target: String
    public var result: String?
    public var failed = false
    public var diff: [DiffLine] = []
    public let input: String
    public var output = ""
    public var calls: [ChatTool] = []
    public let started: Date?
    public var ended: Date?

    public init(id: String, name: String, category: Category? = nil, target: String, input: String = "",
                started: Date?)
    {
        self.id = id
        self.name = name
        self.category = category ?? Self.kinds[name]?.category ?? .other
        self.target = target
        self.input = input
        self.started = started
    }
}

public struct ChatTodo: Equatable, Sendable {
    public let text: String
    public let done: Bool
    public let active: Bool
}

public extension ChatHistory {
    static func duration(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return whole < 60 ? "\(whole)s" : whole < 3600 ? "\(whole / 60)m \(whole % 60)s"
            : "\(whole / 3600)h \(whole % 3600 / 60)m"
    }

    static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(number == 1 ? noun : noun.hasSuffix("y") ? noun.dropLast() + "ies" : noun + "s")"
    }

    /// By name: a parsed object has no order.
    static func firstText(_ input: [String: Any]) -> String {
        firstLine(input.sorted { $0.key < $1.key }.first { $0.value is String }?.value)
    }

    static func firstLine(_ value: Any?) -> String {
        let text = (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let line = text.prefix { $0 != "\n" }
        return line.count > 120 ? line.prefix(119) + "…" : String(line)
    }

    static func detail(_ value: Any?) -> String {
        func json(_ value: Any) -> String {
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .fragmentsAllowed,
                                                             .withoutEscapingSlashes]
            return (try? JSONSerialization.data(withJSONObject: value, options: options))
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        let text = switch value {
        case nil, is NSNull: ""
        case let text as String: text
        case let object as [String: Any]:
            object.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value as? String ?? json($0.value))" }
                .joined(separator: "\n")
        case let value?: json(value)
        }
        return text.count > 20000 ? text.prefix(19999) + "…" : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func short(_ path: String, _ cwd: String?) -> String {
        guard let cwd, path.hasPrefix(cwd + "/") else { return path }
        return String(path.dropFirst(cwd.count + 1))
    }

    static func date(_ text: String) -> Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)
    }
}

extension ChatTool.DiffLine {
    static func unified(_ text: String) -> [Self] {
        var lines: [Self] = [], old = 0, new = 0, inHunk = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") {
                let numbers = line.split(separator: " ").dropFirst().prefix(2)
                    .map { Int($0.dropFirst().split(separator: ",").first ?? "") ?? 1 }
                (old, new, inHunk) = (numbers.first ?? 1, numbers.last ?? 1, true)
                continue
            }
            guard inHunk, let mark = line.first, "+- ".contains(mark) else { continue }
            lines.append(Self(mark: mark, number: mark == "-" ? old : new, text: String(line.dropFirst())))
            old += mark == "+" ? 0 : 1
            new += mark == "-" ? 0 : 1
        }
        return lines
    }

    static func added(_ text: String) -> [Self] {
        text.split(separator: "\n", omittingEmptySubsequences: false).dropLast(text.hasSuffix("\n") ? 1 : 0)
            .enumerated().map { Self(mark: "+", number: $0 + 1, text: String($1)) }
    }
}

extension ChatTool {
    static func change(_ diff: [DiffLine]) -> String {
        let added = diff.count { $0.mark == "+" }, removed = diff.count { $0.mark == "-" }
        return [added > 0 ? "+\(added)" : nil, removed > 0 ? "-\(removed)" : nil].compactMap(\.self)
            .joined(separator: " ")
    }
}

extension ChatTodo {
    /// Claude Code's TodoWrite and opencode's todowrite give `content` and `status`.
    static func list(_ todos: Any?) -> [ChatTodo] {
        (todos as? [[String: Any]] ?? []).map { todo in
            let status = todo["status"] as? String
            return ChatTodo(text: todo["content"] as? String ?? "", done: status == "completed",
                            active: status == "in_progress")
        }
    }
}

public extension ChatTool {
    static func summary(_ tools: [ChatTool]) -> String {
        var order: [(verb: String, noun: String)] = [], numbers: [String: Int] = [:]
        let tools = tools.flatMap { [$0] + $0.calls }
        for name in tools.map(\.name) {
            let wording: (verb: String, noun: String) = kinds[name]?.wording ?? ("ran \(name)", "time")
            if numbers[wording.verb] == nil {
                order.append(wording)
            }
            numbers[wording.verb, default: 0] += 1
        }
        // A stable sort: ties keep their order.
        let largest = order.sorted { numbers[$0.verb, default: 0] > numbers[$1.verb, default: 0] }
        let failed = tools.count(where: \.failed)
        let text = (largest.prefix(3).map { verb, noun in
            noun.isEmpty ? verb : "\(verb) \(ChatHistory.count(numbers[verb, default: 0], noun))"
        } + (largest.count > 3 ? ["+\(largest.count - 3) more"] : []) + (failed > 0 ? ["\(failed) failed"] : []))
            .joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static let kinds: [String: (category: Category, wording: (verb: String, noun: String))] = {
        let ran = ("ran", "command"), searched = ("searched", "pattern"), edited = ("edited", "file")
        let read = ("read", "file"), listed = ("listed", "directory"), web = ("searched the web", "time")
        let fetched = ("fetched", "web page"), asked = ("asked", "question"), talked = ("talked to", "agent")
        let checked = ("checked agents", ""), started = ("started", "agent")
        return [
            "read": (.read, read), "notebookread": (.read, read), "write": (.edit, ("wrote", "file")),
            "edit": (.edit, edited), "multiedit": (.edit, edited), "notebookedit": (.edit, edited),
            "apply_patch": (.edit, edited), "patch": (.edit, edited),
            "bash": (.command, ran), "codemode": (.other, ran), "bash_list": (.other, ran), "bash_watch": (.other, ran),
            "grep": (.search, searched), "find": (.search, searched), "glob": (.search, searched),
            "ls": (.search, listed), "list": (.search, listed),
            "websearch": (.search, web), "web_search": (.other, web), "webfetch": (.other, fetched),
            "web_fetch": (.other, fetched), "askuserquestion": (.other, asked), "question": (.other, asked),
            "agent_start": (.other, started), "agent": (.other, started), "agent_send": (.other, talked),
            "agent_watch": (.other, talked), "agent_read": (.other, checked), "agent_list": (.other, checked),
            "agent_stop": (.other, ("stopped", "agent")), "wait": (.other, ("waited for agents", "")),
        ]
    }()
}

public extension ChatHistory {
    /// Claude's ids come as `claude-opus-5-5` and `claude-3-5-haiku-20241022`.
    static func modelName(_ model: String) -> String {
        let parts = model.split(separator: "/").last?.split(separator: "-") ?? []
        guard parts.first == "claude", let family = parts.first(where: { ["opus", "sonnet", "haiku"].contains($0) })
        else { return model }
        let version = parts.filter { $0.count < 3 && $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        return ([family.capitalized] + (version.isEmpty ? [] : [version])).joined(separator: " ")
    }
}
