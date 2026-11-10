import Foundation

public struct GitStatus: Equatable, Sendable {
    public let branch: String
    public let ahead: Int
    public let behind: Int
}

public extension GitStatus {
    /// From `git status --porcelain=v2 --branch`: `# branch.head` (the short commit when detached) and
    /// `# branch.ab +A -B` (absent without an upstream). Nil without a head line.
    init?(porcelain: String) {
        var head: String?, oid = "", ahead = 0, behind = 0
        for line in porcelain.split(separator: "\n") {
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

    static func porcelain(_ root: String, exec: any Exec) async throws -> String {
        try await exec.checkedOutput(["git", "--no-optional-locks", "-C", root, "status", "--porcelain=v1", "-z",
                                      "--untracked-files=all"])
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

    /// In `git status --porcelain=v1 -z` a rename's or a copy's source path is the next field, also for a rename in
    /// the work tree after `add -N`.
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

    static func entries(_ porcelain: String) -> [Entry] {
        var fields = porcelain.split(separator: "\0", omittingEmptySubsequences: true)[...]
        var entries: [Entry] = []
        // By bytes: a path may start with a combining character.
        while let field = fields.popFirst()?.utf8, field.count > 3 {
            let index = Character(Unicode.Scalar(field[field.startIndex]))
            let tree = Character(Unicode.Scalar(field[field.index(after: field.startIndex)]))
            let oldPath = [index, tree].contains(where: { $0 == "R" || $0 == "C" }) ? fields.popFirst().map(String.init)
                : nil
            entries.append(Entry(index: index, tree: tree, path: String(decoding: field.dropFirst(3), as: UTF8.self),
                                 oldPath: oldPath))
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
