import Foundation
@testable import HerdrKit
import Testing

private func history() throws -> ChatHistory {
    let url = try #require(Bundle.module.url(forResource: "claude-transcript", withExtension: "jsonl",
                                             subdirectory: "Fixtures"))
    var history = ChatHistory()
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
        ClaudeTranscript.read(String(line), into: &history)
    }
    return history
}

@Test func `claude transcript gives user text, replies and tools with their results`() throws {
    let history = try history()
    let users = history.entries.compactMap(\.user)
    // Task notices are not the user's; the queued prompt is.
    #expect(users.count == 6)
    #expect(users[0] == "Reply with just the word hello.")
    #expect(users.contains("Queued: say queued-ok."))
    #expect(history.model == "claude-opus-5-5")
    let tools = history.entries.compactMap(\.tool)
    #expect(tools.allSatisfy { $0.result != nil })
    let edit = try #require(tools.first { $0.name == "edit" })
    #expect(edit.target == "notes.txt" && edit.result == "+1 -1")
    #expect(edit.diff.map { "\($0.mark)\($0.number) \($0.text)" } == [" 1 alpha", "-2 beta", "+2 gamma"])
    #expect(tools.first { $0.name == "write" }?.diff.count == 2)
    #expect(tools.first { $0.name == "read" }?.result == "3 lines")
    let failed = try #require(tools.first { $0.failed })
    #expect(failed.target == "ls /nonexistent" && failed.result == "exit 1")
    #expect(failed.input == "command: ls /nonexistent\ndescription: List a directory that does not exist")
    #expect(failed.output.hasPrefix("Exit code 1\n"), "\(failed.output)")
    #expect(tools.contains { $0.name == "search_files" && $0.category == .other })
    #expect(history.entries.contains { $0.kind == .turnEnd(seconds: 8.355) })
}

extension ChatRow {
    var kind: String {
        String(describing: self).prefix { $0 != "(" }.description
    }
}

@Test func `every message shows in order, each run between them as one line of counts, then the time`() throws {
    let history = try history()
    let rows = history.rows()
    #expect(rows.count { $0.kind == "user" } == 6 && Set(rows.map(\.id)).count == rows.count)
    // One Worked per turn end the agent wrote, also for a turn of a reply alone, each where its turn ended.
    #expect(rows.count { $0.kind == "worked" } == 7)
    #expect(rows.prefix(4).map(\.kind) == ["user", "reply", "worked", "user"])
    #expect(rows.count { $0.kind == "reply" } == history.entries.count { $0.row?.kind == "reply" })
    let turn = try #require(rows
        .firstIndex {
            if case let .user(_, text) = $0 {
                text.hasPrefix("Think")
            } else {
                false
            }
        })
    let next = rows[(turn + 1)...].firstIndex { $0.kind == "user" } ?? rows.endIndex
    #expect(rows[(turn + 1) ..< next].map(\.kind).last == "worked")
    guard case let .worked(_, seconds) = rows[next - 1] else { Issue.record("no time"); return }
    #expect(seconds > 30)

    let runs = rows.compactMap { row -> ArraySlice<ChatEntry>? in
        guard case let .stack(_, steps) = row else { return nil }
        return history.entries[steps]
    }
    #expect(runs.map { ChatTool.summary($0.compactMap(\.tool)) } == [
        "Asked 1 question", "Wrote 1 file, ran 1 command, edited 1 file, +1 more", "Ran 1 command",
        "Ran 3 commands, ran toolsearch 1 time, ran search_files 1 time, 2 failed",
    ])
    #expect(runs.allSatisfy { $0.allSatisfy { $0.tool != nil || $0.kind == .thinking } })
    #expect(runs.contains { $0.contains { $0.kind == .thinking } && $0.contains { $0.tool != nil } })
    #expect(!rows.contains { $0.kind == "thinking" })
}

@Test func `a run is worded as pi-content-layout words it`() {
    func tool(_ name: String, failed: Bool = false, calls: [String] = []) -> ChatTool {
        var tool = ChatTool(id: name, name: name, category: .other, target: "", started: nil)
        tool.failed = failed
        tool.calls = calls.map { ChatTool(id: $0, name: $0, category: .other, target: "", started: nil) }
        return tool
    }
    #expect(ChatTool.summary([tool("read"), tool("bash", failed: true), tool("read"), tool("ls"), tool("ls")])
        == "Read 2 files, listed 2 directories, ran 1 command, 1 failed")
    let many = ["agent_send", "bash", "bash", "read", "agent_stop", "agent_list", "edit"].map { tool($0) }
        + [tool("bash", failed: true)]
    #expect(ChatTool.summary(many) == "Ran 3 commands, talked to 1 agent, read 1 file, +3 more, 1 failed")
    #expect(ChatTool.summary([tool("codemode", calls: ["read", "web_fetch", "bash"]), tool("agent_list")])
        == "Ran 2 commands, read 1 file, fetched 1 web page, +1 more")
    #expect(ChatTool.summary([tool("explore"), tool("explore")]) == "Ran explore 2 times")
}

@Test func `a turn shows Worked once it ends, and keeps it after the next turns`() {
    var history = ChatHistory()
    ClaudeTranscript.read(
        #"{"type":"user","uuid":"u","timestamp":"2026-10-29T10:00:00.000Z","message":{"content":"go"}}"#,
        into: &history,
    )
    let tool = #"{"type":"tool_use","id":"t","name":"Bash","input":{"command":"npm test\nmore"}}"#
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"a","message":{"content":[\#(tool)]}}"#, into: &history)
    #expect(history.rows().map(\.id) == ["u", "a.0"])
    #expect(history.turnStart == ChatHistory.date("2026-10-29T10:00:00.000Z"))
    guard case let .stack(_, steps) = history.rows().last else {
        Issue.record("no run"); return
    }
    #expect(history.entries[steps].first?.tool?.target == "npm test" && history.entries[steps].first?.tool?
        .result == nil)
    #expect(ChatTool.summary(history.entries[steps].compactMap(\.tool)) == "Ran 1 command")
    ClaudeTranscript.read(#"{"type":"system","subtype":"turn_duration","uuid":"e","durationMs":1000}"#, into: &history)
    #expect(history.rows().map(\.id) == ["u", "a.0", "e"])
    #expect(history.turnStart == nil)
    ClaudeTranscript.read(#"{"type":"user","uuid":"v","message":{"content":"on"}}"#, into: &history)
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"b","message":{"content":[{"type":"text","text":"ok"}]}}"#,
                          into: &history)
    #expect(history.rows().map(\.id) == ["u", "a.0", "e", "v", "b.0"])
    ClaudeTranscript.read(#"{"type":"system","subtype":"turn_duration","uuid":"f","durationMs":2000}"#, into: &history)
    #expect(history.rows().map(\.id) == ["u", "a.0", "e", "v", "b.0", "f"])
    #expect(history.rows().last == .worked(id: "f", seconds: 2))
    #expect(!ClaudeTranscript.read(#"{"type":"assist"#, into: &history))
    #expect(ChatHistory.duration(108) == "1m 48s")
}

@Test func `models read as the agent's picker names them`() {
    #expect(ChatHistory.modelName("claude-opus-5-5") == "Opus 5.5")
    #expect(ChatHistory.modelName("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
    #expect(ChatHistory.modelName("claude-3-5-haiku-20241022") == "Haiku 3.5")
    #expect(ChatHistory.modelName("anthropic/claude-opus-4") == "Opus 4")
    #expect(ChatHistory.modelName("gpt-5-codex") == "gpt-5-codex")
}

@Test func `claude's effort comes with each reply's model, none for a model without levels`() {
    var history = ChatHistory()
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"a","effort":"medium","message":{"model":"claude-opus-5-5"}}"#,
                          into: &history)
    #expect(history.model == "claude-opus-5-5" && history.effort == "medium")
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"b","message":{"model":"claude-haiku-5-5"}}"#, into: &history)
    #expect(history.model == "claude-haiku-5-5" && history.effort == nil)
}

extension ChatHistory {
    /// Each turn's rows after its message, as kinds.
    var turnKinds: [[String]] {
        rows().reduce(into: [[String]]()) { turns, row in
            if row.kind == "user" {
                turns.append([])
            } else if !turns.isEmpty {
                turns[turns.count - 1].append(row.kind)
            }
        }
    }
}
