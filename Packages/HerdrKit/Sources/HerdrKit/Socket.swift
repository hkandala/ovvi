import Foundation
import Synchronization

extension Exec {
    public func api(_ session: String) async throws -> Channel {
        try await UnixSocket.connect(herdrSocket(session))
    }

    /// herdr's own rule for the path (its config folder from `XDG_CONFIG_HOME` or the platform's, a session's folder in
    /// it), from herdr itself, in the environment its server and CLI share (D47).
    func herdrSocket(_ session: String) async throws -> String {
        guard let path = try await herdrSession(session).socketPath else {
            throw HerdrError.failed("herdr gives no socket for \(session)")
        }
        return path
    }

    func herdrSession(_ session: String) async throws -> Session {
        guard let herdr = try await herdr() else { throw HerdrError.notFound }
        let list = try await output([herdr, "--session", session, "session", "list", "--json"])
        guard let found = (try? JSONDecoder().decode(SessionList.self, from: Data(list.utf8)))?.sessions
            .first(where: { $0.name == session })
        else { throw HerdrError.failed("herdr has no session \(session)") }
        return found
    }
}

/// A connection to a Unix socket in the app, as a `Channel`: herdr's API socket, or the local socket ssh forwards to a
/// remote machine's. herdr answers one request per connection and then closes it; `events.subscribe` keeps it open.
enum UnixSocket {
    /// `name`: what the errors call it.
    static func connect(_ path: String, as name: String? = nil) throws -> Channel {
        let name = name ?? "herdr's socket \(path)"
        let handle = socket(AF_UNIX, SOCK_STREAM, 0)
        guard handle >= 0 else { throw failure(name, errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(handle)
            throw HerdrError.failed("\(name): its path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        // A write to a closed connection fails, also in an app that does not ignore SIGPIPE.
        var yes: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(handle, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let error = errno
            close(handle)
            throw failure(name, error)
        }
        return channel(handle)
    }

    private static func failure(_ name: String, _ error: Int32) -> HerdrError {
        .failed("\(name): \(String(cString: strerror(error)))")
    }

    /// One queue per connection reads and writes, and closes the socket once, when the reading ends: at its end, when
    /// the reader drops the lines, or on `terminate`. No write goes to a closed socket.
    private static func channel(_ handle: Int32) -> Channel {
        let queue = DispatchQueue(label: "ovvi.socket")
        let source = DispatchSource.makeReadSource(fileDescriptor: handle, queue: queue)
        let (lines, continuation) = AsyncStream<String>.makeStream()
        let ended = Mutex<String?>(nil)
        let (exits, exited) = AsyncStream<Void>.makeStream()
        let end: @Sendable (String) -> Void = { reason in
            ended.withLock { $0 = $0 ?? reason }
            source.cancel()
        }
        read(handle, source, continuation, end: end) { exited.finish() }
        // A reader that stops is no answer from herdr's end.
        continuation.onTermination = { reason in
            if case .cancelled = reason {
                queue.async { end("dropped") }
            }
        }
        return Channel(
            lines: lines,
            write: { line in
                queue.async {
                    if !source.isCancelled, let failure = send(Array((line + "\n").utf8), handle) {
                        end(failure)
                    }
                }
            },
            closeInput: { queue.async { _ = source.isCancelled ? 0 : shutdown(handle, SHUT_WR) } },
            terminate: { queue.async { end("terminated") } },
            exit: {
                for await _ in exits {}
                let reason = ended.withLock { $0 } ?? ""
                return reason.isEmpty ? (0, "") : (1, reason)
            },
        )
    }

    /// Lines until the end, then the socket closes in the cancel handler, its one place.
    private static func read(_ handle: Int32, _ source: any DispatchSourceRead,
                             _ continuation: AsyncStream<String>.Continuation,
                             end: @escaping @Sendable (String) -> Void, closed: @escaping @Sendable () -> Void)
    {
        let buffer = Mutex(LineBuffer())
        // Only the connection's queue reads into it, and its cancel handler frees it.
        nonisolated(unsafe) let chunk = UnsafeMutableRawBufferPointer.allocate(byteCount: 65536, alignment: 1)
        source.setEventHandler {
            let count = Darwin.read(handle, chunk.baseAddress, chunk.count)
            if count < 0, errno == EINTR {
                return
            }
            guard count > 0 else {
                if let rest = buffer.withLock(\.rest) {
                    continuation.yield(rest)
                }
                return end(count == 0 ? "" : String(cString: strerror(errno)))
            }
            for line in buffer.withLock({ $0.take(Data(chunk[..<count])) }) {
                continuation.yield(line)
            }
        }
        source.setCancelHandler {
            close(handle)
            chunk.deallocate()
            continuation.finish()
            closed()
        }
        source.resume()
    }

    /// Nil once all is sent, else why not.
    private static func send(_ bytes: [UInt8], _ handle: Int32) -> String? {
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { Darwin.send(handle, $0.baseAddress, $0.count, 0) }
            guard count > 0 || errno == EINTR else { return String(cString: strerror(errno)) }
            sent += max(count, 0)
        }
        return nil
    }
}

struct LineBuffer {
    private var data = Data()
    private(set) var scanned = 0

    /// Only the chunk's bytes are scanned: a scan from the start per chunk costs O(n²) on a 280 KB snapshot line.
    mutating func take(_ chunk: Data) -> [String] {
        var from = data.endIndex, lines: [String] = []
        data.append(chunk)
        while true {
            let newline = data[from...].firstIndex(of: UInt8(ascii: "\n"))
            scanned += data.distance(from: from, to: newline.map { data.index(after: $0) } ?? data.endIndex)
            guard let newline else { break }
            lines.append(String(decoding: data[..<newline], as: UTF8.self))
            data.removeSubrange(...newline)
            from = data.startIndex
        }
        return lines
    }

    var rest: String? {
        data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }
}
