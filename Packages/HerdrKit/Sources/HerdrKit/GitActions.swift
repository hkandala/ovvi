import Foundation

public extension Git {
    /// The index's view (`staged`, `unstaged`), `status`'s and the head with its commit (empty before the first),
    /// from one run.
    struct Changes {
        public let staged: [Change], unstaged: [Change], status: [Change]
        public let head: GitStatus?, commit: String
    }

    static func changes(_ root: String, exec: any Exec) async throws -> Changes {
        let porcelain = try await porcelain(root, exec: exec)
        let (staged, unstaged) = Change.split(porcelain)
        let oid = porcelain.split(separator: "\0").first { $0.hasPrefix("# branch.oid ") }?.dropFirst(13) ?? ""
        return Changes(staged: staged, unstaged: unstaged, status: Change.parse(porcelain),
                       head: GitStatus(porcelain: porcelain), commit: oid == "(initial)" ? "" : String(oid))
    }

    struct Branch: Equatable, Sendable {
        public let name: String
        public let remote: Bool
        public let current: Bool
    }

    static func branches(_ root: String, exec: any Exec) async throws -> [Branch] {
        let lines = try await exec.checkedOutput(["git", "-C", root, "for-each-ref", "--format=%(HEAD)%(refname)",
                                                  "refs/heads", "refs/remotes"]).split(separator: "\n")
        let local = lines.compactMap { line in
            line.dropFirst().hasPrefix("refs/heads/") ? Branch(name: String(line.dropFirst(12)), remote: false,
                                                               current: line.first == "*") : nil
        }
        let names = Set(local.map(\.name))
        let remote = lines.compactMap { line -> Branch? in
            guard line.dropFirst().hasPrefix("refs/remotes/") else { return nil }
            let name = String(line.dropFirst(14))
            // `origin/HEAD` names another one.
            guard !name.hasSuffix("/HEAD"), let slash = name.firstIndex(of: "/"),
                  !names.contains(String(name[name.index(after: slash)...])) else { return nil }
            return Branch(name: name, remote: true, current: false)
        }
        return local + remote
    }

    /// Tracked paths first (`git restore`, which knows no untracked path), then untracked ones (`git clean`, which
    /// leaves ignored files), so a failed restore deletes nothing. A tracked path fails with no commit yet: there is no
    /// HEAD to go back to.
    /// ponytail: the paths go in argv, twice; thousands of them (an unignored `node_modules`) can pass the argument
    /// limit, then `--pathspec-from-file=-` on stdin.
    static func revert(_ root: String, _ paths: [String], exec: any Exec) async throws {
        let untracked = try await run(root, ["--literal-pathspecs", "ls-files", "-z", "--others", "--exclude-standard",
                                             "--"] + paths, timeout: .seconds(30), exec: exec)
            .split(separator: "\0").map(String.init)
        let gone = Set(untracked), tracked = paths.filter { !gone.contains($0) }
        if !tracked.isEmpty {
            try await run(root, ["--literal-pathspecs", "restore", "--staged", "--worktree", "--source=HEAD", "--"]
                + tracked, timeout: .seconds(30), exec: exec)
        }
        if !untracked.isEmpty {
            try await run(root, ["--literal-pathspecs", "clean", "-fq", "--"] + untracked, timeout: .seconds(30),
                          exec: exec)
        }
    }

    enum Sync: String, Sendable {
        case fetch, pull, push

        public var arguments: [String] {
            switch self {
            case .fetch: ["fetch", "--all"]
            case .pull: ["pull"]
            case .push: ["-c", "push.autoSetupRemote=true", "push"]
            }
        }
    }

    @discardableResult
    static func run(_ root: String, _ arguments: [String], timeout: Duration = .seconds(120),
                    exec: any Exec) async throws -> String
    {
        try await exec.checkedOutput(["env", "GIT_TERMINAL_PROMPT=0", "git", "-C", root] + arguments,
                                     timeout: timeout)
    }
}

extension Git.Change {
    static func split(_ porcelain: String) -> (staged: [Self], unstaged: [Self]) {
        var staged: [Self] = [], unstaged: [Self] = []
        for entry in entries(porcelain) {
            if let whole = entry.whole {
                if whole != "!" {
                    unstaged.append(Self(letter: whole, path: entry.path, oldPath: nil))
                }
                continue
            }
            if entry.index != " " {
                staged.append(Self(letter: entry.staged, path: entry.path, oldPath: entry.oldPath))
            }
            if entry.tree != " " {
                unstaged.append(Self(letter: entry.tree, path: entry.path, oldPath: nil))
            }
        }
        return (staged, unstaged)
    }
}
