import Foundation
import HerdrKit

/// Its status is its session record, `~/.claude/sessions/<pid>.json` (undocumented).
struct ClaudeCode: ChatAdapter {
    static let command = "claude"
    let token: String
    /// One of them has the session record.
    let pids: [Int]
    static let stopKeys = ["escape"]
    static let quit = "/exit"

    /// The hooks hold no quote and no backslash, so that the single-quoted JSON reads the same in sh, bash, zsh and
    /// fish. `set -f`: `[:cntrl:]` is no file pattern. The question hook waits for `answer` while `ask` holds its pid
    /// and Claude lives, 30 minutes at most.
    /// ponytail: `$HOME` unquoted, so a home folder with a space gets no chat; quote it (escaped JSON) if one shows up.
    static func flags(_ token: String, resume: String?) -> String {
        let folder = "umask 077;set -f;d=$HOME/\(ChatAdapters.folder(token));mkdir -p $d"
        let start = "\(folder);{ tr -d [:cntrl:];echo;}>>$d/hooks.jsonl;" + ChatAdapters.sweep
        let ask = "\(folder);rm -f $d/answer;echo $$ >$d/ask;{ tr -d [:cntrl:];echo;}>>$d/hooks.jsonl;n=0;"
            + "while [ $n -lt 9000 ] && grep -qx $$ $d/ask 2>/dev/null && kill -0 $PPID 2>/dev/null;do "
            + "if [ -f $d/answer ];then cat $d/answer;rm -f $d/answer $d/ask;exit 0;fi;sleep 0.2;n=$((n+1));done;"
            + "grep -qx $$ $d/ask 2>/dev/null && rm -f $d/ask"
        let settings = #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","timeout":10,"command":"\#(start)"}]}],"#
            + #""PermissionRequest":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","timeout":1810,"#
            + #""command":"\#(ask)"}]}]}}"#
        return "\(resume ?? "--session-id \(token)") --settings '\(settings)'"
    }

    static func resume(_ session: String) -> String? {
        ChatAdapters.uuid(session).map { "--resume \($0)" }
    }

    /// The launcher's `claude`, its `dotslash` and the native binary all carry the `--settings` value.
    init?(_ foreground: [Program.Foreground]) {
        let marked = ChatAdapters.marked(foreground) { $0.after("--settings").flatMap(ChatAdapters.token(in:)) }
        guard let (token, pids) = marked else { return nil }
        self.init(token: token, pids: pids)
    }

    init(token: String, pids: [Int]) {
        self.token = token
        self.pids = pids
    }

    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        await withDiscardingTaskGroup { group in
            group.addTask { await hooks(chat, exec) }
            group.addTask { await phases(chat, exec) }
        }
    }

    @MainActor private func hooks(_ chat: Chat, _ exec: any Exec) async {
        let sideFile = folder + "/hooks.jsonl", skip = ClaudeTranscript.unread
        await chat.followSessions(sideFile, on: exec, late: true, skip: skip, read: ClaudeTranscript.read) { object in
            if object["hook_event_name"] as? String == "SessionStart" {
                return object["transcript_path"] as? String
            }
            if object["tool_name"] as? String == "AskUserQuestion",
               let questions = (object["tool_input"] as? [String: Any])?["questions"] as? [[String: Any]]
            {
                // Only while its hook waits: a new chat reads the file from the start, answered questions too.
                let question = Self.question(questions)
                if await exec.succeeds(#"test -f "$HOME/$1/ask""#, [folder]), !Task.isCancelled {
                    chat.question = question
                }
            }
            return nil
        }
    }

    /// `status`: idle and `shell` (a background command) are ready, waiting is a dialog, a question or a picker. A
    /// question answered in the terminal ends the wait: its hook may go.
    @MainActor private func phases(_ chat: Chat, _ exec: any Exec) async {
        guard let records = try? await exec.watch(pids.map { ".claude/sessions/\($0).json" }) else { return }
        for await text in records where !Task.isCancelled {
            let status = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["status"]
            let waited = chat.phase == .waiting
            chat.recorded = switch status as? String {
            case "idle", "shell": .ready
            case "busy": .working
            case "waiting": .waiting
            default: nil
            }
            if waited, chat.phase != .waiting, chat.question != nil {
                chat.question = nil
                await exec.succeeds(#"rm -f "$HOME/$1/ask""#, [folder])
            }
        }
    }

    private static func question(_ questions: [[String: Any]]) -> ChatQuestion? {
        guard let items = ChatQuestion.items(questions, several: "multiSelect"),
              let raw = try? JSONSerialization.data(withJSONObject: questions) else { return nil }
        return ChatQuestion(items: items, raw: raw)
    }

    /// Written whole (a temporary file, then a rename): the hook polls for it. Only while the hook waits, else false.
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async -> Bool {
        guard let questions = try? JSONSerialization.jsonObject(with: question.raw),
              let data = try? JSONSerialization.data(withJSONObject: [
                  "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": [
                      "behavior": "allow", "updatedInput": ["questions": questions, "answers": answers],
                  ]],
              ]) else { return false }
        let script = #"d="$HOME/$1"; [ -f "$d/ask" ] && cat >"$d/answer.tmp" && mv "$d/answer.tmp" "$d/answer""#
        return await exec.succeeds(script, [folder], input: [String(decoding: data, as: UTF8.self)])
    }
}
