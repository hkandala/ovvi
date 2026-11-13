import Foundation
import Synchronization

public struct FileMark: Equatable, Sendable {
    public var inode = ""
    /// Whole lines only.
    public var offset = 0

    public init() {}
}

public enum FollowedLine: Sendable {
    /// A new file (another inode, or shorter than the mark) starts from its start. The lines ahead of it belong to
    /// another file when `restarted`.
    case opened(FileMark, restarted: Bool)
    case line(String, FileMark)
    case loaded
    /// The file does not exist yet; it is waited for.
    case missing
}

public extension Exec {
    /// As `tail -F` does, also while the file does not exist yet. A file rotated meanwhile starts again at the next
    /// follow, which compares its inode with the mark's. `skip`'s lines are dropped on the machine so they never cross
    /// a remote machine's relay. Each element is what came since the reader last asked: a burst (a long turn written at
    /// once, a reconnect) lands in one update of a busy reader, not in one per line.
    func follow(_ path: String, from mark: FileMark,
                skip: String = "0") async throws -> some AsyncSequence<[FollowedLine], Never> & Sendable
    {
        let lines = try await lines(Self.followScript, [path, String(mark.offset), mark.inode, skip])
        let pending = Mutex<[FollowedLine]>([])
        let (ready, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let reader = Task {
            func yield(_ line: FollowedLine) {
                pending.withLock { $0.append(line) }
                signal.yield()
            }
            var mark = mark, end = Int.max
            for await line in lines {
                if line == "ovvi-missing" {
                    yield(.missing)
                    continue
                }
                if line.hasPrefix("ovvi-follow ") {
                    let parts = line.split(separator: " ")
                    guard parts.count == 4, let offset = Int(parts[2]), let opened = Int(parts[3]) else { continue }
                    let restarted = parts[1] != mark.inode || offset != mark.offset
                    mark = FileMark()
                    mark.inode = String(parts[1])
                    mark.offset = offset
                    end = opened
                    yield(.opened(mark, restarted: restarted))
                } else if line.hasPrefix("ovvi-skip "), let bytes = Int(line.dropFirst(10)) {
                    mark.offset += bytes
                } else {
                    // Whole lines from a line start only, so the byte count holds (a cut inside a character would
                    // not).
                    mark.offset += line.utf8.count + 1
                    yield(.line(line, mark))
                }
                if mark.offset >= end {
                    end = .max
                    yield(.loaded)
                }
            }
            signal.finish()
        }
        signal.onTermination = { _ in reader.cancel() }
        return ready.map { pending.withLock { lines in defer { lines = [] }; return lines } }.filter { !$0.isEmpty }
    }

    /// The first of the files that exists, its line breaks taken out, at once and after each change, checked every
    /// 0.3 s in one long-lived run of the machine's `perl` (the relay's): no process per check. It ends when its
    /// stdin closes.
    func watch(_ paths: [String]) async throws -> AsyncStream<String> {
        try await lines(["perl", "-e", Self.watchScript] + paths)
    }

    /// Closing stdin makes the wrapper end the script (neither the script nor `tail` reads stdin). No kill: one that
    /// comes ahead of the wrapper's watcher leaves the script running.
    internal func lines(_ script: String, _ arguments: [String]) async throws -> AsyncStream<String> {
        try await lines(["sh", "-c", observeWrapper, "sh", "sh", "-c", script, "sh"] + arguments)
    }

    /// The stream ends the run by closing its stdin.
    private func lines(_ argv: [String]) async throws -> AsyncStream<String> {
        let channel = try await run(argv)
        let (stream, continuation) = AsyncStream<String>.makeStream()
        Task {
            for await line in channel.lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in channel.closeInput() }
        return stream
    }

    /// The start and the end of the whole lines both come from the first `s` bytes, which a write meanwhile does not
    /// change. awk tells the bytes of each skipped line, so the mark still counts the file's bytes. The whole lines
    /// go out through `head` from a seek (`dd … count=0`), and only the rest through `tail`: macOS's `tail` copies
    /// 17 MB a second, and a pi session can pass 100 MB. With nothing to skip, no awk (macOS's passes 30 MB a second).
    /// awk reads a FIFO that only `head`, then `tail` write to: the wrapper's kill ends `tail`, or ends `head` through
    /// the trap (a dropped follow sends no more of its backlog over the relay), and awk ends on its EOF. mawk (Debian's
    /// and Ubuntu's awk) holds lines until 8 KiB come unless it reads interactively.
    static var followScript: String {
        #"""
        f=$1; case $f in /*) ;; *) f=$HOME/$f ;; esac
        m=ovvi-missing; while [ ! -f "$f" ]; do [ -z "$m" ] || echo $m; m=; sleep 0.5; done
        n=$(ls -i "$f" | awk '{print $1}'); s=$(wc -c <"$f" | tr -d ' '); o=$2
        [ "$n" = "$3" ] && [ "$s" -ge "$o" ] || o=0
        [ "$s" -eq 0 ] || [ -z "$(tail -c +"$s" "$f" | head -c 1)" ] ||
          s=$((s - $(head -c "$s" "$f" | tail -n 1 | wc -c)))
        echo "ovvi-follow $n $o $s"
        r() { [ "$s" -gt "$o" ] || return 0
          trap 'kill $! 2>/dev/null; exit 143' TERM
          { dd bs=1 skip="$o" count=0 2>/dev/null; exec head -c $((s - o)); } <"$f" & wait $!; }
        [ "$4" = 0 ] && { r; exec tail -c +$((s + 1)) -F "$f" 2>/dev/null; }
        p=$(mktemp -u "${TMPDIR:-/tmp}/ovvi-follow.XXXXXX") && mkfifo -m 600 "$p" && exec 5<>"$p" 6<"$p" &&
          rm -f "$p" || exit 1
        a=awk; command -v mawk >/dev/null && a="mawk -W interactive"
        LC_ALL=C $a "$4"' { print "ovvi-skip " length($0) + 1; fflush(); next } { print; fflush() }' <&6 5>&- 6<&- &
        exec 6<&-; r >&5; exec tail -c +$((s + 1)) -F "$f" 2>/dev/null >&5 5>&-
        """#
    }

    /// A path may be relative to the home folder. An unreadable file is passed over, as a missing one.
    static var watchScript: String {
        #"""
        use strict; use warnings;
        $| = 1;
        my $last;
        while (1) {
            my $now = '';
            for (@ARGV) {
                my $file = m{^/} ? $_ : "$ENV{HOME}/$_";
                next unless -f $file;
            open(my $in, '<', $file) or next;
                local $/;
                $now = <$in> // '';
                $now =~ tr/\n//d;
                last;
            }
            print "$now\n" if !defined $last || $now ne $last;
            $last = $now;
            my $wait = ''; vec($wait, 0, 1) = 1;
            exit 0 if select($wait, undef, undef, 0.3) > 0 && !sysread(STDIN, my $byte, 1);
        }
        """#
    }
}
