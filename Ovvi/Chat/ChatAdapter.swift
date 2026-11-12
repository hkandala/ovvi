import Foundation
import HerdrKit

protocol ChatAdapter: Sendable {
    /// Also herdr's agent name (`claude`).
    static var command: String { get }
    static func flags(_ token: String, resume: String?) -> String
    /// The user's arguments go ahead of Ovvi's flags: OpenCode ignores what follows its `--`.
    static func prepare(_ token: String, resume: String?, arguments: String, on exec: any Exec) async -> String?
    /// From herdr's `agent_session`. The arguments go into a typed line: only plain ids and quotable paths.
    static func resume(_ session: String) -> String?
    static var quit: String { get }
    static var stopKeys: [String] { get }
    static var resumesAnywhere: Bool { get }
    init?(_ foreground: [Program.Foreground])
    init(token: String, pids: [Int])
    var token: String { get }
    @MainActor func follow(_ chat: Chat, on exec: any Exec) async
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async -> Bool
}

extension ChatAdapter {
    /// Under the home folder: the user's own, on a shared machine too.
    var folder: String {
        ChatAdapters.folder(token)
    }

    var name: String {
        Chooser.name(Self.command)
    }

    static var resumesAnywhere: Bool {
        false
    }

    static func prepare(_ token: String, resume: String?, arguments: String, on _: any Exec) async -> String? {
        command + arguments + " " + flags(token, resume: resume)
    }

    func answer(_: ChatQuestion, _: [String: String], on _: any Exec) async -> Bool {
        false
    }
}

extension Chat {
    private static let unknownFormat = "The transcript is not in a format the chat knows"

    func followSessions(_ sideFile: String, on exec: any Exec, late: Bool, skip: String = "0",
                        read: @escaping @Sendable (String, inout ChatHistory) -> Bool,
                        line: ([String: Any]) async -> String?) async
    {
        let parser = Parser(take: {}, put: { _ in }, read: { _, text, _, history in read(text, &history) })
        await followSessions(sideFile, on: exec, late: late, skip: skip, parser: parser, line: line)
    }

    func followSessions(_ sideFile: String, on exec: any Exec, late: Bool, skip: String = "0",
                        parser: Parser<some Sendable>, line: ([String: Any]) async -> String?) async
    {
        var transcript: Task<Void, Never>?
        // One history follow at a time: they share the chat's backlog.
        let follow = { (source: String) in
            let old = transcript
            old?.cancel()
            transcript = Task {
                await old?.value
                guard !Task.isCancelled else { return }
                await self.follow(history: source, on: exec, skip: skip, parser: parser)
            }
        }
        let timer = Task {
            try? await Task.sleep(for: .seconds(10))
            if late, !Task.isCancelled, source == nil {
                problem = "\(adapter.name) has not started a session"
            }
        }
        defer { timer.cancel() }
        guard let lines = try? await exec.follow(sideFile, from: marks[sideFile] ?? FileMark()) else { return }
        if let source {
            follow(source)
        }
        // Lines buffered ahead of a cancel still come: not into the next follow's chat.
        for await batch in lines {
            for entry in batch where !Task.isCancelled {
                guard case let .line(text, mark) = entry else {
                    // Codex names its session only with the first prompt: none in the whole file is a new conversation.
                    if !late, source == nil, entry.read {
                        current = true
                    }
                    continue
                }
                marks[sideFile] = mark
                guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                      let next = await line(object), !Task.isCancelled else { continue }
                problem = nil
                guard next != source else { continue }
                source = next
                history = ChatHistory()
                // A resumed session's file reads from its start.
                marks[next] = nil
                follow(next)
            }
        }
        transcript?.cancel()
        await transcript?.value
    }

    /// `take` lets go of the parser's own copy of its state, so that it changes in place.
    struct Parser<State: Sendable> {
        let take: () -> State
        let put: (State) -> Void
        let read: @Sendable (inout State, String, Int, inout ChatHistory) -> Bool
        var restarted: () -> Void = {}
    }

    func change(_ body: @escaping (inout ChatHistory) -> Void) {
        if reading {
            queued.append((source, body))
        } else if loading {
            body(&backlog)
        } else {
            body(&history)
        }
    }

    /// What the file held when opened is read off the main actor (a 100 MB session takes seconds) and shows whole:
    /// row by row, a long session would rebuild every row each time.
    private func follow(history source: String, on exec: any Exec, skip: String, parser: Parser<some Any>) async {
        guard let lines = try? await exec.follow(source, from: marks[source] ?? FileMark(), skip: skip) else { return }
        var torn = 0
        // A batch's lines in one main-actor turn: the card draws once for them, not once per line.
        for await batch in lines {
            var run: [(text: String, mark: FileMark)] = []
            for line in batch {
                guard !Task.isCancelled, self.source == source else { break }
                guard case let .line(text, mark) = line else {
                    torn = await read(run, torn: torn, source: source, parser: parser)
                    run = []
                    take(line, parser: parser)
                    continue
                }
                run.append((text, mark))
            }
            if !Task.isCancelled, self.source == source {
                torn = await read(run, torn: torn, source: source, parser: parser)
            }
        }
        // Cut short: the marks went on, so the history keeps what they read, unless another session took over.
        if loading {
            showBacklog(self.source == source)
        }
    }

    private func take(_ line: FollowedLine, parser: Parser<some Any>) {
        switch line {
        case let .opened(_, again):
            (loading, backlog) = (true, again ? ChatHistory() : history)
            if again, !history.entries.isEmpty {
                parser.restarted()
            }
        case .loaded:
            showBacklog()
            current = true
        // Not written yet: Claude Code and pi write it with the first message, so the chat has no history.
        case .missing: current = true
        case .line: break
        }
    }

    private func read(_ run: [(text: String, mark: FileMark)], torn: Int, source: String,
                      parser: Parser<some Any>) async -> Int
    {
        guard !run.isEmpty else { return torn }
        let read = parser.read
        var state = parser.take(), torn = torn, done = (five: false, count: 0)
        if loading {
            var backlog = backlog
            self.backlog = ChatHistory()
            reading = true
            let task = Task.detached { [state, backlog, torn] in
                var (state, backlog, torn) = (state, backlog, torn)
                let done = Self.lines(run, read, &state, &backlog, &torn)
                return (state, backlog, torn, done)
            }
            (state, backlog, torn, done) = await withTaskCancellationHandler { await task.value } onCancel: {
                task.cancel()
            }
            reading = false
            if self.source == source {
                self.backlog = backlog
            }
        } else {
            done = Self.lines(run, read, &state, &history, &torn)
        }
        let five = done.five
        // Not into another session's parser (a session line started it again meanwhile).
        if self.source == source {
            parser.put(state)
            if done.count > 0 {
                marks[source] = run[done.count - 1].mark
            }
            if five {
                problem = Self.unknownFormat
            }
            check(torn: torn)
        }
        for (made, body) in queued where made == self.source {
            change(body)
        }
        queued = []
        return torn
    }

    private nonisolated static func lines<State>(_ run: [(text: String, mark: FileMark)],
                                                 _ read: (inout State, String, Int, inout ChatHistory) -> Bool,
                                                 _ state: inout State, _ history: inout ChatHistory,
                                                 _ torn: inout Int) -> (five: Bool, count: Int)
    {
        var five = false
        for (index, (text, mark)) in run.enumerated() {
            if index.isMultiple(of: 500), Task.isCancelled {
                return (five, index)
            }
            torn = read(&state, text, mark.offset, &history) ? 0 : torn + 1
            five = five || torn == 5
        }
        return (five, run.count)
    }

    private func check(torn: Int) {
        if torn == 5 {
            problem = Self.unknownFormat
        } else if torn == 0, problem == Self.unknownFormat {
            problem = nil
        }
    }

    private func showBacklog(_ show: Bool = true) {
        loading = false
        if show {
            history = backlog
        }
        // Let go of the copy, or the history's next line would copy it whole.
        backlog = ChatHistory()
    }
}

private extension FollowedLine {
    /// The file is read to its end, or not there.
    var read: Bool {
        switch self {
        case .loaded, .missing: true
        case .opened, .line: false
        }
    }
}

enum ChatAdapters {
    static let cache = ovviFolder, root = cache + "/chat"

    static func folder(_ token: String) -> String {
        "\(root)/\(token)"
    }

    /// Appends do not change a folder's time; `-mmin +1`: not one a launch just made. Plain, unquoted sh: Claude
    /// Code's and Codex's hooks hold no quote. ponytail: `$HOME` unquoted (a home folder with a space keeps its files);
    /// a session idle 30 days loses its chat on a relaunch: touch the files on use if that shows up.
    static let sweep = "find $HOME/\(root) -mindepth 2 -mtime +30 -delete 2>/dev/null;"
        + "find $HOME/\(root) -mindepth 1 -type d -empty -mmin +1 -delete 2>/dev/null"

    static func launch(_ command: String, token: String, resume: String? = nil, on exec: any Exec) async -> String? {
        guard let adapter = Chooser.agent(command)?.adapter else { return nil }
        let resumed = resume.flatMap(adapter.resume)
        guard resume == nil || resumed != nil else { return nil }
        return await adapter.prepare(token, resume: resumed, arguments: Chooser.arguments(command), on: exec)
    }

    static func token(_ id: some StringProtocol) -> String? {
        UUID(uuidString: String(id)) != nil && id == id.lowercased() ? String(id) : nil
    }

    static func token(in argument: String) -> String? {
        argument.range(of: "/\(root)/").flatMap { token(argument[$0.upperBound...].prefix(36)) }
    }

    static func marked(_ foreground: [Program.Foreground],
                       _ token: ([String]) -> String?) -> (token: String, pids: [Int])?
    {
        var found: String?, pids: [Int] = []
        for process in foreground {
            guard let id = token(process.argv), found == nil || found == id else { continue }
            found = id
            pids.append(process.pid)
        }
        return found.map { ($0, pids) }
    }

    static func uuid(_ value: String) -> String? {
        UUID(uuidString: value) != nil ? value : nil
    }

    static func recognize(_ program: Program?) -> (any ChatAdapter)? {
        guard let foreground = program?.foreground, !foreground.isEmpty else { return nil }
        return Chooser.agents.lazy.compactMap { $0.adapter.init(foreground) }.first
    }
}

extension [String] {
    func after(_ flag: String) -> String? {
        firstIndex(of: flag).flatMap { $0 + 1 < count ? self[$0 + 1] : nil }
    }
}
