import Foundation

public struct FileEntry: Equatable, Sendable {
    public let name: String
    public let isFolder: Bool
    public let ignored: Bool
}

public struct FileContents: Equatable, Sendable {
    public let data: Data
    public let hash: String
}

enum FileError: Error, Equatable, Sendable {
    case tooLarge(Int)
    case changed
}

/// The relay carries lines, so names come NUL-separated and bytes as base64.
public enum Files {
    public static let viewLimit = 16 << 20
    /// A save queues the whole file on the machine's one relay.
    static let remoteEditLimit = 4 << 20

    /// `git check-ignore` asks only about the folder's own names, so a listing never walks the whole repository.
    public static func list(_ folder: String, git: Bool, exec: any Exec) async throws -> [FileEntry] {
        // A missing folder is `notFound` on every `sh` (dash says only "can't cd"). Links to folders are folders; a
        // name may hold a line break. The ignored names come after an empty one; none outside a repository. Each name
        // is asked as `./name`: git reads them as pathspecs, so `:foo` would be `foo`.
        let script = #"""
        [ -d "$1" ] || { echo "Not a folder" >&2; exit 1; }
        cd "$1" || exit
        for f in * .[!.]* ..?*; do
          if [ -d "$f" ]; then printf '%s/\0' "$f"; elif [ -e "$f" ] || [ -h "$f" ]; then printf '%s\0' "$f"; fi
        done
        [ "$2" ] || exit 0
        printf '\0'
        for f in * .[!.]* ..?*; do [ -e "$f" ] || [ -h "$f" ] && printf './%s\0' "$f"; done |
          git --no-optional-locks check-ignore -z --stdin 2>/dev/null
        exit 0
        """#
        let parts = try await exec.checkedOutput(["sh", "-c", script, "sh", folder, git ? "git" : ""])
            .split(separator: "\0", omittingEmptySubsequences: false)
        let empty = parts.firstIndex(of: "") ?? parts.endIndex
        let ignored = Set(parts[empty...].filter { !$0.isEmpty }.map { $0.hasPrefix("./") ? $0.dropFirst(2) : $0 })
        return parts[..<empty].filter { $0 != ".git/" && $0 != ".git" }.map { name in
            let isFolder = name.hasSuffix("/")
            let name = isFolder ? name.dropLast() : name
            return FileEntry(name: String(name), isFolder: isFolder, ignored: ignored.contains(name))
        }
        .sorted {
            $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// ponytail: the first 8 MB of names (about 150,000 files); a search on the machine when roots get bigger.
    public static func paths(_ root: String, git: Bool, exec: any Exec) async throws -> [String] {
        let script = #"""
        cd "$1" || exit
        if [ "$2" ]; then git ls-files -z -co --exclude-standard; else find . -name .git -prune -o -type f -print0; fi |
          head -c 8388608
        """#
        // The last name is cut short, or empty after the last NUL.
        return try await exec.checkedOutput(["sh", "-c", script, "sh", root, git ? "git" : ""],
                                            timeout: .seconds(30))
            .split(separator: "\0", omittingEmptySubsequences: false).dropLast()
            .map { String($0.hasPrefix("./") ? $0.dropFirst(2) : $0) }
    }

    public static func read(_ path: String, exec: any Exec) async throws -> FileContents {
        // The hash first: a change between the two reads makes a save stop with `changed`, never lose it.
        let script = #"""
        [ -f "$1" ] || { echo "Not a file" >&2; exit 1; }
        s=$(wc -c <"$1") || exit
        echo $s; [ $s -le $2 ] || exit 0
        cksum <"$1" && base64 <"$1"
        """#
        let lines = try await exec.checkedOutput(["sh", "-c", script, "sh", path, String(viewLimit)],
                                                 timeout: .seconds(60)).split(separator: "\n", maxSplits: 2)
        let size = Int(lines.first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        guard size <= viewLimit else { throw FileError.tooLarge(size) }
        guard lines.count >= 2,
              let data = Data(
                  base64Encoded: lines.count == 3 ? String(lines[2]) : "",
                  options: .ignoreUnknownCharacters,
              )
        else { throw HerdrError.failed("Could not read \(path)") }
        return FileContents(data: data, hash: String(lines[1]))
    }

    public static func save(_ data: Data, to path: String, replacing hash: String?, exec: any Exec) async throws
        -> String
    {
        let result = try await exec.checkedOutput(["sh", "-c", saveScript, "sh", path, hash ?? "", String(data.count)],
                                                  input: base64Lines(data), timeout: .seconds(60))
        guard result != "changed" else { throw FileError.changed }
        return result
    }

    /// `cp -p` gives the new file the replaced one's mode. The size check: a run whose stdin closed early (the
    /// connection dropped, the app quit) decodes what came and exits 0.
    static let saveScript = #"""
    t=$(mktemp "$(dirname "$1")/.ovvi-save.XXXXXX") || exit
    trap 'rm -f "$t"' EXIT
    cp -p "$1" "$t" 2>/dev/null; base64 -d >"$t" || exit
    [ "$(wc -c <"$t")" -eq "$3" ] || { echo "The save was cut short" >&2; exit 1; }
    [ -z "$2" ] || [ "$(cksum <"$1")" = "$2" ] || { echo changed; exit 0; }
    cksum <"$t"
    if [ -h "$1" ]; then cat "$t" >"$1"; else mv -f "$t" "$1"; fi
    """#

    public static func watch(_ path: String, exec: any Exec) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        if exec.isRemote {
            let task = Task { await poll(path, exec: exec, continuation) }
            continuation.onTermination = { _ in task.cancel() }
        } else {
            let events = Events([path], continuation)
            continuation.onTermination = { _ in events.stop() }
        }
        return stream
    }

    /// Any change to the paths, a folder's whole tree included, with no process per check: FSEvents on This Mac, and
    /// on a remote machine one long-lived Perl run (the relay's Perl) that compares their `lstat` every `interval`.
    /// It ends when the remote run does (a dropped connection).
    public static func watch(paths: [String], every interval: Duration = .seconds(2),
                             exec: any Exec) -> AsyncStream<Void>
    {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        if exec.isRemote {
            let task = Task {
                let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
                if let channel = try? await exec.run(["perl", "-e", statScript, String(seconds)] + paths) {
                    for await _ in channel.lines {
                        continuation.yield()
                    }
                    channel.terminate()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        } else {
            let events = Events(paths, continuation)
            continuation.onTermination = { _ in events.stop() }
        }
        return stream
    }

    /// A line each time a sweep differs from the one before. The wait is a `select` on stdin, so the run ends when its
    /// stdin closes. ponytail: every file of a folder each sweep, whole-second mtimes (Time::HiRes is not in Debian's
    /// perl-base) need the inodes: 10,000 loose refs take 30 ms; sweep only folders with HiRes where it is there, if
    /// that matters.
    static let statScript = #"""
    use strict; use warnings;
    my ($every, @paths) = @ARGV;
    $| = 1;
    sub sweep {
        my $path = shift;
        my @info = lstat $path or return "$path -\n";
        my $text = "$path @info[1, 7, 9]\n";
        if (-d _ && opendir(my $folder, $path)) {
            $text .= sweep("$path/$_") for sort grep { $_ ne '.' && $_ ne '..' } readdir $folder;
        }
        return $text;
    }
    my $last;
    while (1) {
        my $now = join '', map { sweep($_) } @paths;
        print "changed\n" if defined $last && $now ne $last;
        $last = $now;
        my $in = ''; vec($in, 0, 1) = 1;
        exit 0 if select($in, undef, undef, $every) > 0 && !sysread(STDIN, my $byte, 1);
    }
    """#

    /// ponytail: a file's check reads it whole (up to 16 MB) every 2 s, and the caller reads it again to compare
    /// hashes; yield the hash when that costs too much. A folder's check sees its own entries, what `git status` sees
    /// under it and the changed files' text (an edit to a file already changed), not a new file in an ignored folder;
    /// its git runs without `GitStatus.usable`. A path that is gone prints nothing: a check that fails (a dropped link,
    /// the 10 s bound) knows nothing, so it reports no change, and the first check that answers after it reports one,
    /// for what the caller's own calls may have missed meanwhile.
    static func poll(_ path: String, exec: any Exec, every interval: Duration = .seconds(2),
                     _ changed: AsyncStream<Void>.Continuation) async
    {
        let script = #"""
        if [ -d "$1" ]; then
          { ls -1Ap "$1"; git --no-optional-locks -C "$1" status --porcelain=v1 -z -unormal -- . 2>/dev/null
            git -C "$1" ls-files -z -m -o --exclude-standard -- . 2>/dev/null |
              (cd "$1" && xargs -0 cat 2>/dev/null); } | cksum
        elif [ -e "$1" ]; then cksum <"$1"; fi
        """#
        var last: String?, missed = false
        while !Task.isCancelled {
            if let now = try? await exec.checkedOutput(["sh", "-c", script, "sh", path]) {
                if missed || last.map({ $0 != now }) == true {
                    changed.yield()
                }
                (last, missed) = (now, false)
            } else {
                missed = true
            }
            try? await Task.sleep(for: interval)
        }
    }
}

/// Whatever file a path names: a file an editor replaced, or one that comes back, is still seen. The stream is on
/// the nearest folder that exists: one made later sends nothing.
private final class Events: Sendable {
    private static let queue = DispatchQueue(label: "ovvi.files.watch")
    private let changed: AsyncStream<Void>.Continuation
    /// Canonical, as the events name paths (`/private/tmp`).
    private let targets: [String]
    /// Set once in init and released once in `stop`, which the stream's end calls once.
    private nonisolated(unsafe) var stream: FSEventStreamRef?

    init(_ paths: [String], _ changed: AsyncStream<Void>.Continuation) {
        let roots = paths.map { path in
            var root = path, isFolder: ObjCBool = false
            while root != "/",
                  !(FileManager.default.fileExists(atPath: root, isDirectory: &isFolder) && isFolder.boolValue)
            {
                root = (root as NSString).deletingLastPathComponent
            }
            return root
        }
        targets = zip(paths, roots).map { path, root in
            let canonical = (try? URL(filePath: root).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
                ?? root
            return canonical + path.dropFirst(root.count)
        }
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil,
                                           release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let events = Unmanaged<Events>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            // Events the system dropped: anything may have changed.
            let dropped = (0 ..< count).contains {
                flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
            }
            if dropped || changed.contains(where: { path in
                events.targets.contains { path == $0 || path.hasPrefix($0 + "/") }
            }) {
                events.changed.yield()
            }
        }
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        // A second's latency: a folder lists again at most that often while a build writes.
        stream = FSEventStreamCreate(nil, callback, &context, Array(Set(roots)) as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
                                     FSEventStreamCreateFlags(flags))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, Self.queue)
            FSEventStreamStart(stream)
        }
    }

    /// On the events' queue: a callback that is running uses `self`, which the context does not keep.
    func stop() {
        Self.queue.async { [self] in
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
