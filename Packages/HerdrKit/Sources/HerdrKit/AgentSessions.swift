import Foundation

public struct ClosedSession: Sendable, Hashable, Identifiable {
    public let agent: String
    public let value: String
    public let title: String
    public let folder: String
    public let date: Date

    public var id: String {
        agent + " " + value
    }
}

public struct ClosedPage: Sendable, Equatable {
    public var sessions: [ClosedSession] = []
    public var more = false
    public var problem: String?
    public var looked = 0
    public var oldest: Date?
}

public struct ClosedList: Sendable, Equatable {
    public private(set) var agents: [String: ClosedPage] = [:]

    public init() {}

    public mutating func add(_ page: ClosedPage, for agent: String) {
        var all = agents[agent] ?? ClosedPage()
        // A session that moved to the top between pages comes again.
        let seen = Set(all.sessions.map(\.id))
        all.sessions += page.sessions.filter { !seen.contains($0.id) }
        (all.more, all.problem, all.looked) = (page.more, page.problem, all.looked + page.looked)
        all.oldest = page.oldest ?? all.oldest
        agents[agent] = all
    }

    /// Down to where every agent with more pages has been read: an agent's next page may hold newer ones than
    /// another's last.
    public func sessions(of shown: [String]) -> [ClosedSession] {
        let cutoff = cutoff(shown) ?? .distantPast
        return shown.flatMap { agents[$0]?.sessions ?? [] }.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
    }

    public func next(of shown: [String]) -> [String] {
        let cutoff = cutoff(shown)
        return shown.filter { agents[$0]?.more == true && agents[$0]?.oldest == cutoff }
    }

    private func cutoff(_ shown: [String]) -> Date? {
        shown.compactMap { agents[$0].flatMap { $0.more ? $0.oldest : nil } }.max()
    }
}

/// One process per page, never one per session file: a process costs about 20 ms on a Mac with endpoint security.
/// The perl readers look at `files` at most, so a store of left-out runs still answers within the read's 10 s. A
/// session with no prompt prints an empty title and is counted, so a page of noise still has a next one. pi and
/// Claude Code keep a JSONL file a session, newest by its modification time; Codex and OpenCode keep an SQLite index.
/// ponytail: pages are offsets into lists that change while the shelf is open: a session that moves to the top shifts
/// the next page (`ClosedList.add` drops the repeat), and one deleted between pages hides one row until a new open.
enum ClosedSessions {
    /// `cut`: a string cut inside a `\u` escape or a surrogate pair loses the part. `tail`: past a file's first lines,
    /// on to its last 256 KB at a line's start, where the agents append their titles (a transcript can be 100 MB).
    static let perl = #"""
    use File::Glob ':bsd_glob';
    sub cut { my $s = shift // ""; $s =~ s/(?<!\\)((?:\\\\)*)\\u[0-9a-fA-F]{0,3}$/$1/;
      $s =~ s/(?<!\\)((?:\\\\)*)\\u[dD][89abAB][0-9a-fA-F]{2}$/$1/; $s }
    my ($shown, $looked) = (0, 0);
    sub row { my ($t, $v, $c, $n) = @_; $v =~ s/(["\\])/\\$1/g; $shown++ if $n ne "";
      print qq({"t":$t,"v":"$v","c":"), cut($c), qq(","n":"), cut($n), qq("}\n) }
    sub full { $shown >= $ARGV[0] || ++$looked >= \#(files) }
    sub newest { my ($k, @f) = @_; @f = sort { $b->[1] <=> $a->[1] } map { [$_, (stat)[9]] } @f;
      $k > $#f ? () : @f[$k .. $#f] }
    sub tail { my $h = shift; if (-s $h > tell($h) + 262144) { seek $h, -262144, 2; <$h> } }
    my $S = qr/((?:[^"\\]|\\.){0,300})/;
    """#

    static let scripts = [
        // Line 1 holds the folder, the next 40 the first prompt; the title is the last `/name`, else the first prompt.
        "pi": #"""
        exec perl -e "$3"'
        for (newest($ARGV[1], glob("$ENV{HOME}/.pi/agent/sessions/*/*.jsonl"))) { my ($p, $m) = @$_;
          open my $h, "<", $p; my $l = <$h> // ""; my ($c) = $l =~ /"cwd":"((?:[^"\\]|\\.)*)"/;
          my ($u, $s, $i) = ("", "", 0);
          my $name = sub { $s = $1 if index($_, q({"type":"session_info")) == 0 && /"name":"$S"/ };
          while ($i++ < 40 && defined($_ = <$h>)) { $name->();
            $u = $2 if $u eq "" && /"message":\{"role":"user","content":(\[\{"type":"text","text":)?"$S/ }
          tail($h); while (<$h>) { $name->() }
          row($m, $p, $c, $s ne "" ? $s : $u); last if full() }' "$1" "$2"
        """#,
        // The id is the file's name; the folder and the first typed prompt (not its commands' wrappers, which start
        // with `<`) in the first 100 lines; the title the last `/rename`, else Claude Code's own, else the prompt. Left
        // out: the Agent SDK's sessions.
        "claude": #"""
        exec perl -e "$3"'
        for (newest($ARGV[1], glob("$ENV{HOME}/.claude/projects/*/*.jsonl"))) { my ($p, $m) = @$_;
          my ($id) = $p =~ m{([^/]+)\.jsonl$}; open my $h, "<", $p;
          my ($c, $u, $a, $r, $sdk, $i) = ("", "", "", "", 0, 0);
          my $title = sub { $r = $1 if /^\{"type":"custom-title","customTitle":"$S/;
            $a = $1 if /^\{"type":"ai-title","aiTitle":"$S/ };
          while ($i++ < 100 && defined($_ = <$h>)) { $title->(); $c = $1 if $c eq "" && /"cwd":"((?:[^"\\]|\\.)*)"/;
            $sdk ||= /"entrypoint":"sdk-/; last if $sdk; $u = $2 if $u eq "" && !/"isMeta":true/
              && /"message":\{"role":"user","content":(\[\{"type":"text","text":)?"(?!<)$S/ }
          unless ($sdk) { tail($h); while (<$h>) { $title->() } }
          row($m, $id, $c, $sdk ? "" : $r || $a || $u); last if full() }' "$1" "$2"
        """#,
        // The newest state database (its number is a schema version). Left out: subagents, `codex exec` runs and
        // empty threads. With no sqlite3, or a schema without these columns: the rollout files, whose line 1 holds the
        // id and folder, with the name from `session_index.jsonl`, else the first prompt.
        // ponytail: a database busy past its 1 s for one page reads that page from the rollouts, whose offsets count
        // files: the pages mix two lists (the repeats are dropped).
        "codex": #"""
        d=$(ls -t "$HOME"/.codex/state_*.sqlite | head -n 1)
        [ -n "$d" ] && sqlite3 -readonly -cmd '.timeout 1000' "$d" "select json_object('t', recency_at_ms / 1000,
          'v', id, 'c', cwd, 'n', substr(coalesce(nullif(name, ''), nullif(title, ''), preview), 1, 300)) from threads
          where archived = 0 and source not like '{%' and source <> 'exec' and preview <> ''
          order by recency_at_ms desc limit $1 offset $2" || exec perl -e "$3"'
        my %name; if (open my $i, "<", "$ENV{HOME}/.codex/session_index.jsonl") { while (<$i>) {
          $name{$1} = $2 if /"id":"([^"]+)","thread_name":"$S"/ } }
        for (newest($ARGV[1], glob("$ENV{HOME}/.codex/sessions/*/*/*/rollout-*.jsonl"))) { my ($p, $m) = @$_;
          open my $h, "<", $p; my $l = <$h> // "";
          my ($id) = $l =~ /"payload":\{(?:"session_id":"[^"]*",)?"id":"([^"]+)"/;
          my ($c) = $l =~ /"cwd":"((?:[^"\\]|\\.)*)"/; my $u = $name{$id // ""} // ""; my $i = 0;
          my $skip = $l =~ /"source":(\{|"exec")/;
          while (!$skip && $u eq "" && ++$i < 400 && defined($_ = <$h>)) {
            $u = $1 if /"type":"user_message","message":"$S/ || /"type":"UserMessage".*?"text":"$S/ }
          row($m, $id // "", $c, $skip ? "" : $u); last if full() }' "$1" "$2"
        """#,
        // Left out: child sessions (a task's), archived ones, and OpenCode's placeholder titles (no prompt yet).
        "opencode": #"""
        d=${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db; [ -e "$d" ] || exit 0
        command -v sqlite3 >/dev/null || { echo '{"problem":"needs sqlite3"}'; exit; }
        exec sqlite3 -readonly -cmd '.timeout 1000' "$d" "select json_object('t', time_updated / 1000, 'v', id,
          'c', directory, 'n', substr(title, 1, 300)) from session
          where parent_id is null and time_archived is null and title not like 'New session - %'
          order by time_updated desc limit $1 offset $2"
        """#,
    ]

    static let files = 2000

    static func parse(agent: String, _ text: String, limit: Int) -> ClosedPage {
        var page = ClosedPage()
        let lines = text.split(separator: "\n")
        var titled = 0
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            page.problem = object["problem"] as? String ?? page.problem
            guard let time = object["t"] as? Double else { continue }
            page.oldest = min(page.oldest ?? .distantFuture, Date(timeIntervalSince1970: time))
            if object["n"] as? String != "" {
                titled += 1
            }
            guard let value = object["v"] as? String, !value.isEmpty,
                  let folder = object["c"] as? String, folder.hasPrefix("/"),
                  let title = (object["n"] as? String).flatMap(clean) else { continue }
            page.sessions.append(ClosedSession(agent: agent, value: value, title: title, folder: folder,
                                               date: Date(timeIntervalSince1970: time)))
        }
        page.looked = lines.count
        page.more = page.problem == nil && (titled >= limit || lines.count >= files)
        return page
    }

    static func home(_ argument: Int) -> String {
        "[ -z \"$\(argument)\" ] || { HOME=$\(argument); unset XDG_DATA_HOME; }"
    }

    static func clean(_ text: String) -> String? {
        let line = text.map { $0.isNewline || $0 == "\t" ? " " : $0 }.filter { !$0.isControl }
        // A 300-byte cut can end inside a character.
        let clean = String(line).trimmingCharacters(in: .whitespaces.union(["\u{FFFD}"])).prefix(200)
        return clean.isEmpty ? nil : String(clean)
    }
}

public extension Exec {
    func closedSessions(agent: String, offset: Int, limit: Int = 50, home: String? = nil) async throws -> ClosedPage {
        guard let script = ClosedSessions.scripts[agent] else { return ClosedPage() }
        let text = try await checkedOutput([
            "sh",
            "-c",
            "{ \(ClosedSessions.home(4))\n\(script)\n} 2>/dev/null",
            "sh",
            "\(limit)",
            "\(offset)",
            ClosedSessions.perl,
            home ?? "",
        ])
        return ClosedSessions.parse(agent: agent, text, limit: limit)
    }
}

/// Claude Code keeps a session's title in its transcript (`ai-title` lines it writes itself, `custom-title` from
/// `/rename`), Codex in `~/.codex/session_index.jsonl` (`thread_name`), pi in its session file (`session_info` from
/// `/name`; pi names no session itself), OpenCode in its database (`session.title`, the same as its server's). With
/// no title yet, the first typed prompt: Claude Code's and pi's from their files' first lines, Codex's from its state
/// database's `preview`; OpenCode titles its own sessions.
enum SessionTitle {
    static let scripts = [
        // The prompt's lines only with no title line: a transcript's first user lines can be long.
        "claude": #"f=$(ls "$HOME"/.claude/projects/*/"$1".jsonl | head -n 1); "#
            + #"t=$(grep -a '"type":"custom-title"' "$f" | tail -n 1; grep -a '"type":"ai-title"' "$f" | tail -n 1); "#
            + #"if [ -n "$t" ]; then printf '%s\n' "$t"; else head -n 100 "$f" | grep -a '"type":"user"' | "#
            + #"grep -av '"tool_result"' | head -n 10; fi"#,
        "codex": #"t=$(grep -a -F "\"id\":\"$1\"" "$HOME/.codex/session_index.jsonl" | tail -n 1); "#
            + #"if [ -n "$t" ]; then printf '%s\n' "$t"; else d=$(ls -t "$HOME"/.codex/state_*.sqlite | head -n 1); "#
            + #"[ -n "$d" ] && sqlite3 -readonly -cmd '.timeout 1000' "$d" "#
            + #""select json_object('prompt', substr(preview, 1, 300)) from threads where id = '$1'"; fi"#,
        "pi": #"t=$(grep -a '"type":"session_info"' "$1" | tail -n 1); if [ -n "$t" ]; then printf '%s\n' "$t"; "#
            + #"else head -n 40 "$1" | grep -a '"role":"user"' | head -n 1; fi"#,
        "opencode": #"sqlite3 -readonly -cmd '.timeout 1000' "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/"#
            + #"opencode.db" "select title from session where id = '$1'""#,
    ]

    static func parse(agent: String, _ text: String) -> String? {
        let lines = text.split(separator: "\n").map(String.init)
        if agent == "opencode" {
            return lines.first.flatMap { $0.hasPrefix("New session - ") || $0.hasPrefix("Child session - ") ? nil : $0 }
                .flatMap(ClosedSessions.clean)
        }
        let objects = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let title = objects.lazy.compactMap { object in
            ["customTitle", "aiTitle", "thread_name", "name"].lazy.compactMap { object[$0] as? String }.first
                .flatMap(ClosedSessions.clean)
        }.first
        return title ?? objects.lazy.compactMap(prompt).compactMap(ClosedSessions.clean).first.map { prompt in
            prompt.count > 100 ? prompt.prefix(100).trimmingCharacters(in: .whitespaces) + "…" : prompt
        }
    }

    /// Not Claude Code's meta lines or its commands' wrappers, which start with `<`.
    private static func prompt(_ object: [String: Any]) -> String? {
        if let preview = object["prompt"] as? String {
            return preview
        }
        guard let message = object["message"] as? [String: Any], message["role"] as? String == "user",
              object["isMeta"] as? Bool != true else { return nil }
        let content = message["content"]
        let text = content as? String
            ?? (content as? [[String: Any]])?.first { $0["type"] as? String == "text" }?["text"] as? String
        return text.flatMap { $0.hasPrefix("<") ? nil : $0 }
    }
}

public extension Exec {
    /// `timeout` bounds a machine that hangs; the title is a nicety, so a slow one shows none.
    func sessionTitle(agent: String, session: String, home: String? = nil,
                      timeout: Duration = .seconds(5)) async -> String?
    {
        // pi's is a file; the others' ids go into OpenCode's SQL and Claude Code's file name: letters, digits, `-` and
        // `_` only.
        let plain = session.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }
        let id = !session.isEmpty && plain
        guard let script = SessionTitle.scripts[agent], agent == "pi" ? session.hasPrefix("/") : id else { return nil }
        let text = try? await output(
            ["sh", "-c", "{ \(ClosedSessions.home(2)); \(script); } 2>/dev/null", "sh", session, home ?? ""],
            timeout: timeout,
        )
        return SessionTitle.parse(agent: agent, text ?? "")
    }
}
