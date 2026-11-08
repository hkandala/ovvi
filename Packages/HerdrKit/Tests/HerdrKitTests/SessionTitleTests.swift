import Foundation
@testable import HerdrKit
import Testing

/// Lines as each script prints them, from real sessions (Claude Code 2.1.310, Codex 0.163, pi 0.80, OpenCode 1.x).
@Test func `session titles: a rename wins over Claude Code's own, and placeholders are none`() {
    let claude = #"""
    {"type":"custom-title","customTitle":"say hi (Branch)","sessionId":"1b77b9f3-ed25-4373-964e-295a0158d7e8"}
    {"type":"ai-title","aiTitle":"x.txt in tuictl","sessionId":"1b77b9f3-ed25-4373-964e-295a0158d7e8"}
    """#
    #expect(SessionTitle.parse(agent: "claude", claude) == "say hi (Branch)")
    #expect(SessionTitle.parse(agent: "claude", #"{"type":"ai-title","aiTitle":"x.txt in tuictl"}"#)
        == "x.txt in tuictl")
    #expect(SessionTitle.parse(agent: "codex", #"{"id":"01a0","thread_name":"Build LLM email classifier\n"}"#)
        == "Build LLM email classifier")
    #expect(SessionTitle.parse(agent: "pi", #"{"type":"session_info","id":"1c51dedc","name":"t40-sessions"}"#)
        == "t40-sessions")
    #expect(SessionTitle.parse(agent: "pi", #"{"type":"session_info","id":"1c51dedc","name":" "}"#) == nil)
    #expect(SessionTitle.parse(agent: "opencode", "ax steer test") == "ax steer test")
    #expect(SessionTitle.parse(agent: "opencode", "New session - 2026-09-18T05:33:51.827Z") == nil)
    #expect(SessionTitle.parse(agent: "claude", "") == nil)
}

@Test func `a pi session file's last name, read through the script`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ovvi-title-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try """
    {"type":"session","version":3,"id":"01a1","cwd":"/tmp"}
    {"type":"session_info","id":"a","parentId":null,"name":"first"}
    {"type":"message","id":"b","parentId":"a","message":{"role":"user","content":"name it"}}
    {"type":"session_info","id":"c","parentId":"b","name":"Trip notes"}

    """.write(to: file, atomically: true, encoding: .utf8)
    #expect(await localExec.sessionTitle(agent: "pi", session: file.path) == "Trip notes")
    // Not a path or a plain id: never reaches the script.
    #expect(await localExec.sessionTitle(agent: "opencode", session: "x' or '1'='1") == nil)
    #expect(await localExec.sessionTitle(agent: "opencode", session: "/x' union select sqlite_version() --") == nil)
    #expect(await localExec.sessionTitle(agent: "gemini", session: file.path) == nil)
}

/// No title yet: the first typed prompt, cut at 100 characters with "…" (ui/window#agent-rows).
@Test func `an untitled session's first prompt`() {
    let long = String(repeating: "word ", count: 30)
    let claude = #"""
    {"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}
    {"type":"user","isMeta":true,"message":{"role":"user","content":"Caveat: local commands"}}
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"fix the\nflaky test"}]}}
    """#
    #expect(SessionTitle.parse(agent: "claude", claude) == "fix the flaky test")
    let titled = #"{"type":"ai-title","aiTitle":"Flaky test"}"# + "\n" + claude
    #expect(SessionTitle.parse(agent: "claude", titled) == "Flaky test")
    let piLine = #"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"\#(long)"}]}}"#
    let cut = SessionTitle.parse(agent: "pi", piLine)
    #expect(cut == String(long.prefix(100)).trimmingCharacters(in: .whitespaces) + "…")
    #expect(SessionTitle.parse(agent: "codex", #"{"prompt":"rename the CLI"}"#) == "rename the CLI")
    #expect(SessionTitle.parse(agent: "codex", #"{"prompt":""}"#) == nil)
}

@Test func `an untitled session's first prompt, read through the scripts, from a home of its own`() async throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "ovvi-home-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let projects = home.appending(path: ".claude/projects/x")
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    try #"{"type":"user","message":{"role":"user","content":"fix the flaky test"},"sessionId":"01a2"}"#
        .write(to: projects.appending(path: "01a2.jsonl"), atomically: true, encoding: .utf8)
    #expect(await localExec.sessionTitle(agent: "claude", session: "01a2", home: home.path) == "fix the flaky test")
    let file = home.appending(path: "pi.jsonl")
    try """
    {"type":"session","version":3,"id":"01a3","cwd":"/tmp"}
    {"type":"message","message":{"role":"user","content":[{"type":"text","text":"plan the trip"}]}}

    """.write(to: file, atomically: true, encoding: .utf8)
    #expect(await localExec.sessionTitle(agent: "pi", session: file.path) == "plan the trip")
}
