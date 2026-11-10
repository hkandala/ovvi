import Foundation

public struct AgentRequest: Equatable, Sendable {
    public static let version = 1
    public static let limit = 64 << 10, inputLimit = 1 << 20

    public let cwd: String
    public let argv: [String]

    public enum Problem: Error, Equatable {
        case tooLarge
        case unreadable
        case newer(Int)
    }

    public init(_ data: Data) throws(Problem) {
        guard data.count <= Self.limit else { throw .tooLarge }
        var fields = data.split(separator: 0, omittingEmptySubsequences: false).map {
            String(decoding: $0, as: UTF8.self)
        }
        // Each field ends with a NUL, so the last split is empty.
        guard fields.popLast() == "" else { throw .unreadable }
        guard fields.count <= 64 else { throw .tooLarge }
        guard fields.count >= 3, fields[0] == "ovvi-req", let version = Int(fields[1]) else { throw .unreadable }
        guard version <= Self.version else { throw .newer(version) }
        cwd = fields[2]
        argv = Array(fields[3...])
    }

    /// Every mailbox path is built from it, so a token can never name another file.
    public static func isID(_ id: String) -> Bool {
        id.wholeMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/) != nil
    }
}

public extension Exec {
    /// `script` goes in only when the machine's is missing or behind, never over a newer one.
    func prepareAgent(script: Data) async {
        let line = try? await output(["sh", "-c", #"""
        d=$HOME/\#(ovviFolder); mkdir -p "$d/bin" "$d/rpc" && chmod 700 "$d/rpc" &&
        find "$d/rpc" -type f -mmin +60 -exec rm -f {} + ; sed -n 2p "$d/bin/ovvi" 2>/dev/null
        """#])
        let ours = String(decoding: script, as: UTF8.self).split(separator: "\n").dropFirst().first.map(String.init)
        guard let line, scriptVersion(line).lexicographicallyPrecedes(scriptVersion(ours ?? "")) else { return }
        await succeeds(#"""
        f=$HOME/\#(ovviFolder)/bin/ovvi; base64 -d >"$f.$$" && chmod 755 "$f.$$" && mv "$f.$$" "$f" || rm -f "$f.$$"
        """#, [], input: base64Lines(script))
    }

    /// Takes the request: renames `‹id›.req` to `‹id›.run` and reads it, at most one byte over the limit. Nil when
    /// another Ovvi took it first, or the command gave up.
    func take(request id: String) async throws -> Data? {
        guard AgentRequest.isID(id) else { return nil }
        let text = try await output(["sh", "-c", #"""
        cd "$HOME/\#(ovviFolder)/rpc" && mv -- "$1.req" "$1.run" && head -c "$2" "$1.run" | base64
        """#, "sh", id, "\(AgentRequest.limit + 1)"])
        return text.isEmpty ? nil : Data(base64Encoded: text, options: .ignoreUnknownCharacters)
    }

    func input(request id: String) async throws -> Data {
        guard AgentRequest.isID(id) else { return Data() }
        let text = try await output(
            ["sh", "-c", #"f=$HOME/\#(ovviFolder)/rpc/$1.in; [ ! -f "$f" ] || head -c "$2" "$f" | base64"#,
             "sh", id, "\(AgentRequest.inputLimit + 1)"],
            timeout: .seconds(30),
        )
        return Data(base64Encoded: text, options: .ignoreUnknownCharacters) ?? Data()
    }

    /// Each file goes to a temporary name and is then renamed, so the command never reads half a file.
    func answer(request id: String, code: Int32, out: Data, err: String) async throws {
        guard AgentRequest.isID(id) else { return }
        _ = try await checkedOutput(["sh", "-c", #"""
        cd "$HOME/\#(ovviFolder)/rpc" && base64 -d >"$1.o" && mv "$1.o" "$1.out" &&
        printf '%s\n%s' "$2" "$3" >"$1.e" && mv "$1.e" "$1.exit"; s=$?; rm -f "$1.run" "$1.in"; exit $s
        """#, "sh", id, "\(code)", err], input: base64Lines(out), timeout: .seconds(30))
    }
}

public let ovviFolder = ".cache/ovvi"

private func scriptVersion(_ line: String) -> [Int] {
    guard line.hasPrefix("# ovvi-cli ") else { return [] }
    return line.dropFirst(11).split(separator: ".").map { Int($0) ?? 0 }
}
