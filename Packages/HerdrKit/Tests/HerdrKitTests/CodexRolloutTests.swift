import Foundation
@testable import HerdrKit
import Testing

/// A real Codex 0.163 session, cut down; the last turn is written by hand in the shapes of real rollouts.
private func history() throws -> ChatHistory {
    let url = try #require(Bundle.module.url(forResource: "codex-rollout", withExtension: "jsonl",
                                             subdirectory: "Fixtures"))
    var history = ChatHistory()
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
        #expect(CodexRollout.read(String(line), into: &history))
    }
    return history
}

@Test func `codex rollout gives user text, replies, tools with their results and turn ends`() throws {
    let history = try history()
    #expect(history.entries.compactMap(\.user) == [
        "Run the shell command 'echo spike-ok' and then reply with just the word done.",
        "In /private/tmp/ovvi-39codex-spike: first make a 2-step plan with your plan tool, then create notes.txt with "
            + "two lines (alpha, beta), then change beta to gamma with an edit, then run 'false' as a shell command, "
            + "then read launch.py, then reply with a short summary.",
        "Run the shell command 'sleep 30' then reply ok.",
        "Plan it, then tell main hello.",
    ])
    #expect(history.model == "gpt-6.1-sol" && history.effort == "high")
    let tools = history.entries.compactMap(\.tool)
    #expect(tools.allSatisfy { $0.result != nil && $0.ended != nil })
    #expect(tools.first?.target == "echo spike-ok" && tools.first?.result == "spike-ok")
    #expect(tools.first?.input == "echo spike-ok" && tools.first?.output == "spike-ok")
    let edits = tools.filter { $0.category == .edit }
    #expect(edits.map(\.result) == ["+2", "+1 -1"])
    #expect(edits[1].diff.map { "\($0.mark)\($0.number) \($0.text)" } == [" 1 alpha", "-2 beta", "+2 gamma"])
    let failed = try #require(tools.first { $0.failed })
    #expect(failed.target == "false" && failed.result == "exit 1")
    #expect(tools.contains { $0.category == .read && $0.target == "launch.py" })
    #expect(tools.last?.name == "agent_send" && tools.last?.target == "hello")
    let agents = tools.filter { $0.id.hasPrefix("call_") }
    #expect(agents.map(\.name) == ["agent", "wait", "agent_send"])
    #expect(agents.allSatisfy { !$0.failed && $0.result == "" && $0.ended != nil })
    #expect(agents[0].target == "subreply" && agents[2].target == "subreply")
    #expect(history.entries.contains { $0.kind == .turnEnd(seconds: 8.954) })
    #expect(history.entries.contains { $0.kind == .note("Interrupted", failed: false) })
    #expect(history.entries.contains { $0.kind == .note("Compacted", failed: false) })
    #expect(history.entries.contains { $0.kind == .reply("# Say hello\n\n1. Send hello to main.") })
    #expect(history.entries.contains { $0.kind == .thinking })
}

@Test func `a torn codex line is not read`() {
    var history = ChatHistory()
    #expect(!CodexRollout.read(#"{"type":"event_msg","payload""#, into: &history))
}

@Test func `codex is ready only with its input box above its status row`() {
    let idle = "• done\n\n› Ask Codex to do anything\n\n  GPT-6.1 Sol high · /private/tmp\n"
        + "  ? for shortcuts                       ⚠ 1 warning · f2 to view\n\n"
    #expect(CodexRollout.ready(idle))
    let working = "• Working (8s • esc to interrupt) · 1 background terminal running\n› Ask Codex to do anything\n"
        + "  GPT-6.1 Sol high · /private/tmp · Run echo spike-ok\n  ? for shortcuts\n"
    #expect(CodexRollout.ready(working))
    let picker = "  Select Model and Effort\n› 1. GPT-6.1 Sol (current)  Near-Astra\n  2. GPT-6.1 Sol (1M)  Near\n"
        + "  3. GPT-5.6-Sol  Older\n  enter select · esc back\n"
    #expect(!CodexRollout.ready(picker))
    let approval = "  Would you like to run the following command?\n  $ rm -rf g1\n› 1. Yes, proceed (y)\n"
        + "  2. No, and tell Codex what to do differently (esc)\n  Press enter to confirm or esc to cancel\n"
    #expect(!CodexRollout.ready(approval))
    #expect(!CodexRollout.ready(""))
}

@Test func `codex trust hash matches what Codex trusted`() {
    let command = "umask 077;mkdir -p $HOME/.cache/ovvi/chat/11111111-2222-4333-8444-555555555555;"
        + "cat>>$HOME/.cache/ovvi/chat/11111111-2222-4333-8444-555555555555/hooks.jsonl;"
        + "echo>>$HOME/.cache/ovvi/chat/11111111-2222-4333-8444-555555555555/hooks.jsonl;"
        + "find $HOME/.cache/ovvi/chat -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} +"
    // Codex 0.163 runs this hook from `-c hooks.state` with no trust picker.
    #expect(CodexRollout.trust(command) == "sha256:59e8711e0546bcc8001a71abda156fad60107f0500e9785c2402205f09acd187")
}

@Test func `declined and killed calls are failures, not successes`() {
    var history = ChatHistory()
    let items = [
        #"{"type":"CommandExecution","id":"a","command":["rm","-rf","g1"],"status":"declined"}"#,
        #"{"type":"CommandExecution","id":"b","command":["/bin/zsh","-lc","sleep 9"],"status":"failed"}"#,
        #"{"type":"FileChange","id":"c","status":"declined","changes":{"/t/n.txt":{"type":"add","content":"x\n"}}}"#,
    ]
    for item in items {
        CodexRollout.read(#"{"type":"event_msg","payload":{"type":"item_completed","item":\#(item)}}"#, into: &history)
    }
    #expect(history.entries.compactMap(\.tool).map { "\($0.target) \($0.result ?? "") \($0.failed)" } == [
        "rm -rf g1 declined true", "sleep 9 failed true", "/t/n.txt declined true",
    ])
}

@Test func `each codex turn that completes ends in its Worked`() throws {
    // The third turn was interrupted: its note, then a command that ended after it.
    #expect(try history().turnKinds == [["reply", "stack", "reply", "worked"],
                                        ["reply", "reply", "stack", "reply", "worked"],
                                        ["reply", "note", "stack"], ["note", "reply", "stack", "worked"]])
}

@Test func `a resumed codex session's rollout goes in the side file, plain where Codex compressed it`() async throws {
    let home = URL(filePath: "/tmp/ovvi-codex-name-\(UUID().uuidString)"), store = home.appending(path: "store")
    defer { try? FileManager.default.removeItem(at: home) }
    let exec = ProcessExec(["HOME": home.path, "PATH": "/usr/bin:/bin"], herdr: nil, asked: .now)
    let id = "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b", other = "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5c"
    let folder = ".codex/sessions/2026/11/02/", name = "rollout-2026-11-02T10-00-00-\(id).jsonl"
    for (root, file) in [(home, name + ".zst"), (home, "rollout-2026-11-02T11-00-00-\(other).jsonl"), (store, name)] {
        let url = root.appending(path: folder + file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }
    let side = ".cache/ovvi/chat/t/hooks.jsonl"
    await CodexRollout.name(id, in: side, on: exec)
    await CodexRollout.name("019a2b3c-0000-7f60-8a9b-0c1d2e3f4a5b", in: side, on: exec)
    await CodexRollout.name(id, in: side, home: store.path, on: exec)
    let lines = try String(contentsOf: home.appending(path: side), encoding: .utf8).split(separator: "\n")
    let paths = try lines.map { line in
        try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String])["transcript_path"]
    }
    #expect(paths == [home.path + "/" + folder + name, store.path + "/" + folder + name])
}
