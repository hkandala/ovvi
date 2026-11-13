import Foundation

public struct GitStatus: Equatable, Sendable {
    public let branch: String
    public let ahead: Int
    public let behind: Int
}

public extension GitStatus {
    /// From `git status --porcelain=v2 --branch`, with `-z` or not: `# branch.head` (the short commit when detached)
    /// and `# branch.ab +A -B` (absent without an upstream). Nil without a head line.
    init?(porcelain: String) {
        var head: String?, oid = "", ahead = 0, behind = 0
        // With `-z` a name may hold a line break: only NULs end a line then.
        let end: Character = porcelain.contains("\0") ? "\0" : "\n"
        for line in porcelain.split(separator: end) {
            let words = line.split(separator: " ")
            guard words.count >= 3, words[0] == "#" else { continue }
            switch words[1] {
            case "branch.head": head = String(words[2])
            case "branch.oid": oid = String(words[2])
            case "branch.ab" where words.count >= 4:
                ahead = Int(words[2].dropFirst()) ?? 0
                behind = Int(words[3].dropFirst()) ?? 0
            default: break
            }
        }
        guard let head else { return nil }
        branch = head == "(detached)" ? String(oid.prefix(7)) : head
        self.ahead = ahead
        self.behind = behind
    }

    /// No optional locks: a run every 10 s must not leave `index.lock` in the user's way.
    static func of(_ root: String, exec: any Exec) async -> GitStatus? {
        let argv = ["git", "--no-optional-locks", "-C", root, "status", "--porcelain=v2", "--branch",
                    "--untracked-files=no"]
        return await (try? exec.output(argv, timeout: .seconds(5))).flatMap(GitStatus.init(porcelain:))
    }

    /// Git's own files that the head and the counts come from: the work tree's `HEAD`, and its repository's refs
    /// (loose, packed or a reftable) and `config` (the upstream). A linked worktree's `HEAD` is in its own git folder.
    /// Nil outside a repository.
    static func files(_ root: String, exec: any Exec) async -> [String]? {
        let lines = await (try? exec.output(["git", "-C", root, "rev-parse", "--absolute-git-dir", "--git-common-dir"],
                                            timeout: .seconds(5)))?.split(separator: "\n").map(String.init) ?? []
        guard lines.count == 2, lines[0].hasPrefix("/") else { return nil }
        // Relative only when it is the git folder itself (from the physical folder, so not to be joined to `root`).
        let common = lines[1].hasPrefix("/") ? lines[1] : lines[0]
        return [lines[0] + "/HEAD"] + ["refs", "packed-refs", "reftable", "config"].map { common + "/" + $0 }
    }

    /// Follows `files`: a change to one makes the head and counts read again.
    static func watch(_ root: String, exec: any Exec) async -> AsyncStream<Void>? {
        guard let files = await files(root, exec: exec) else { return nil }
        return Files.watch(paths: files, exec: exec)
    }

    /// `watch`, tried again each 60 s while the root is no repository (a `git init` comes later) or after a watch
    /// ended (a dropped link), as the sidebar's; a later one yields once, for what came meanwhile. None without `git`.
    static func follow(_ root: String, git: Bool, exec: any Exec) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            var started = false
            while git, !Task.isCancelled {
                if let changes = await watch(root, exec: exec) {
                    if started {
                        continuation.yield()
                    }
                    started = true
                    for await _ in changes {
                        continuation.yield()
                    }
                }
                try? await Task.sleep(for: .seconds(60))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// On a Mac `/usr/bin/git` is a stub that opens the developer tools' install dialog when `xcode-select -p` finds
    /// none.
    static func usable(exec: any Exec) async -> Bool {
        await exec.succeeds(#"""
        g=$(command -v git) &&
          { [ "$g" != /usr/bin/git ] || [ "$(uname)" != Darwin ] || xcode-select -p; } >/dev/null 2>&1
        """#, [])
    }
}

/// Callers check `GitStatus.usable` first: on a Mac without the developer tools, any git run opens the install
/// dialog.
public enum Git {
    public static func root(_ folder: String, exec: any Exec) async -> String? {
        let root = await (try? exec.output(["git", "-C", folder, "rev-parse", "--show-toplevel"],
                                           timeout: .seconds(5))) ?? ""
        return root.isEmpty ? nil : root
    }

    public static func commit(_ ref: String, in root: String, exec: any Exec) async -> String? {
        // Never an option.
        guard !ref.isEmpty, !ref.hasPrefix("-") else { return nil }
        let hash = await (try? exec.output(["git", "-C", root, "rev-parse", "--verify", "--quiet", "\(ref)^{commit}"],
                                           timeout: .seconds(5))) ?? ""
        return hash.isEmpty ? nil : hash
    }

    public static func status(_ root: String, exec: any Exec) async throws -> [Change] {
        try await Change.parse(porcelain(root, exec: exec))
    }

    /// The changes and the head in one run.
    static func porcelain(_ root: String, exec: any Exec) async throws -> String {
        try await exec.checkedOutput(["git", "--no-optional-locks", "-C", root, "status", "--porcelain=v2", "--branch",
                                      "-z", "--untracked-files=all"])
    }

    /// Not `--all`: the stash, notes and git's own refs would add lanes.
    /// ponytail: Show More asks for the whole longer list again, as the graph's lanes need every row above; ask for
    /// the rows after a commit if long histories get slow. An orphan branch with no commit yet fails on `HEAD` and
    /// shows no history; drop `HEAD` there if that matters.
    public static func log(_ root: String, limit: Int? = nil, exec: any Exec) async throws -> [Commit] {
        try await exec.checkedOutput(
            ["git", "-C", root, "log", "--branches", "--remotes", "--tags", "HEAD", "-n", String(max(limit ?? 500, 1)),
             "--topo-order",
             "--no-show-signature", "--decorate=full",
             // `--`: a file named HEAD is no revision.
             "--format=%H%x1f%P%x1f%an%x1f%at%x1f%D%x1f%s", "--"],
            timeout: .seconds(30),
        )
        .split(separator: "\n").compactMap(Commit.init)
    }
}

public extension Git {
    struct Change: Equatable, Sendable {
        public let letter: Character
        /// From the repository's root; a folder's ends in `/`.
        public let path: String
        public let oldPath: String?
    }

    struct Commit: Equatable, Sendable {
        public let hash: String
        public let parents: [String]
        public let author: String
        public let date: Date
        public let subject: String
        /// The names on it, as `%D` prints them with `--decorate=full`: `HEAD -> refs/heads/main`, `HEAD` when
        /// detached, `refs/heads/…`, `refs/remotes/…`, `tag: refs/tags/…`.
        public var refs: [String] = []
    }

    /// A lane keeps its column while its line runs, so a line that passes a row is straight.
    struct GraphRow: Equatable, Sendable {
        public let lane: Int
        public let children: [Int]
        public let parents: [Int]
        public let through: [Int]
    }
}

extension Git.Change {
    static func parse(_ porcelain: String) -> [Self] {
        entries(porcelain).map { entry in
            let letter = entry.whole ?? ("ARC".contains(entry.index) || entry.tree == " " ? entry.staged : entry.tree)
            return Self(letter: letter, path: entry.path, oldPath: entry.oldPath)
        }
    }

    /// As `git status --porcelain=v1` has it: `index` and `tree` are a space when unchanged, `??` untracked, `!!`
    /// ignored.
    struct Entry {
        let index: Character, tree: Character, path: String, oldPath: String?

        var whole: Character? {
            switch (index, tree) {
            case ("?", "?"): "U"
            case ("!", "!"): "!"
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): "C"
            default: nil
            }
        }

        var staged: Character {
            index == "C" ? "A" : index
        }
    }

    /// From `git status --porcelain=v2 -z`: `1 XY` (8 fields ahead of the path), `2 XY` (9; a rename's or a copy's
    /// source path is the next field), `u XY` (10), `? ` and `! `; the `# ` headers are the head's.
    static func entries(_ porcelain: String) -> [Entry] {
        var fields = porcelain.split(separator: "\0", omittingEmptySubsequences: true)[...]
        var entries: [Entry] = []
        // By bytes: a path may start with a combining character, and hold spaces.
        while let field = fields.popFirst().map({ Array($0.utf8) }) {
            guard field.count > 2, field[1] == UInt8(ascii: " ") else { continue }
            let kind = Character(Unicode.Scalar(field[0]))
            guard let ahead = ["1": 8, "2": 9, "u": 10, "?": 1, "!": 1][kind] else { continue }
            let spaces = field.indices.filter { field[$0] == UInt8(ascii: " ") }
            guard spaces.count >= ahead else { continue }
            let path = String(decoding: field[(spaces[ahead - 1] + 1)...], as: UTF8.self)
            let letter = { (byte: UInt8) in byte == UInt8(ascii: ".") ? " " : Character(Unicode.Scalar(byte)) }
            let (index, tree) = "?!".contains(kind) ? (kind, kind) : (letter(field[2]), letter(field[3]))
            entries.append(Entry(index: index, tree: tree, path: path,
                                 oldPath: kind == "2" ? fields.popFirst().map(String.init) : nil))
        }
        return entries
    }
}

extension Git.Commit {
    init?(_ line: Substring) {
        let fields = line.split(separator: "\u{1F}", maxSplits: 5, omittingEmptySubsequences: false)
        guard fields.count == 6, let time = TimeInterval(fields[3]) else { return nil }
        self.init(hash: String(fields[0]), parents: fields[1].split(separator: " ").map(String.init),
                  author: String(fields[2]), date: Date(timeIntervalSince1970: time), subject: String(fields[5]),
                  refs: fields[4].split(separator: ", ").map(String.init))
    }
}

public extension Git {
    static func graph(_ commits: [Commit]) -> [GraphRow] {
        // Each lane waits for the commit it runs to; nil is a free column.
        var lanes: [String?] = []
        return commits.map { commit in
            let children = lanes.indices.filter { lanes[$0] == commit.hash }
            let lane = children.first ?? lanes.firstIndex(of: nil) ?? lanes.endIndex
            if lane == lanes.endIndex {
                lanes.append(nil)
            }
            children.forEach { lanes[$0] = nil }
            let through = lanes.indices.filter { lanes[$0] != nil }
            var parents: [Int] = []
            for (index, parent) in commit.parents.enumerated() {
                // The first parent keeps the dot's lane, also when another lane waits for it: their lines meet at
                // its dot, in the left one, as in `git log --graph`. Another parent joins a lane that waits for it.
                let next = index == 0 ? lane : lanes.firstIndex(of: parent) ?? lanes.firstIndex(of: nil) ?? lanes
                    .endIndex
                if next == lanes.endIndex {
                    lanes.append(parent)
                } else {
                    lanes[next] = parent
                }
                parents.append(next)
            }
            while lanes.last == .some(nil) {
                lanes.removeLast()
            }
            return GraphRow(lane: lane, children: children, parents: parents, through: through)
        }
    }
}

public extension Git {
    static func show(_ root: String, _ hash: String, exec: any Exec) async throws -> [String: any Sendable] {
        // Never an option.
        guard !hash.isEmpty, hash.allSatisfy(\.isHexDigit) else { throw HerdrError.failed("No commit \(hash)") }
        let format = "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%b"
        let fields = try await exec.checkedOutput(
            ["git", "-C", root, "show", "-s", "--no-show-signature", format, hash, "--"],
            timeout: .seconds(30),
        )
        .split(separator: "\u{1F}", maxSplits: 6, omittingEmptySubsequences: false)
        guard fields.count == 7,
              let time = TimeInterval(fields[4]) else { throw HerdrError.failed("No commit \(hash)") }
        return ["hash": String(fields[0]), "parents": fields[1].split(separator: " ").map(String.init),
                "author": String(fields[2]), "email": String(fields[3]), "date": time * 1000,
                "subject": String(fields[5]), "body": fields[6].trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    static func patch(_ root: String, commit: String?, exec: any Exec) async throws -> String {
        // The user's config must not change the format: color, an external tool, other prefixes, quoted names.
        let git = ["git", "-c", "core.quotePath=false", "-c", "diff.suppressBlankEmpty=false"]
        let flags = ["--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "-M"]
        if let commit {
            // A hash from a pane's label: never an option.
            guard !commit.isEmpty,
                  commit.allSatisfy(\.isHexDigit) else { throw HerdrError.failed("No commit \(commit)") }
            return try await exec.checkedOutput(
                git + ["-C", root, "show"] + flags + ["-m", "--first-parent", "--format=", commit],
                timeout: .seconds(30),
            )
        }
        // With no commit yet, against the empty tree.
        // ponytail: 16 MB of patch and 64 KB of untracked names (a cut last line reads as a shorter file), and the
        // pipe hides git's errors: an empty patch; a patch per file when bigger changes must show.
        let script = #"""
        cd "$1" && shift && h=$(git rev-parse -q --verify HEAD || git hash-object -t tree /dev/null) || exit
        { git "$@" "$h" --
          git ls-files -z -o --exclude-standard | head -c 65536 | xargs -0 -r -n 1 git "$@" --no-index -- /dev/null
        } | head -c 16777216
        """#
        return try await exec.checkedOutput(
            ["sh", "-c", script, "sh", root] + git.dropFirst() + ["diff"] + flags,
            timeout: .seconds(30),
        )
    }
}
