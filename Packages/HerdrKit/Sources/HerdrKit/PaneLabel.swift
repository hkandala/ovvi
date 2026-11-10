import Foundation

/// A herdr label survives moves and herdr restarts, and every device sees it.
public struct PaneLabel: Equatable, Sendable {
    public let plugin: String
    public let iid: String
    public let arg: String

    public init(plugin: String, iid: String, arg: String = "") {
        self.plugin = plugin
        self.iid = iid
        self.arg = arg
    }

    /// By hand, not a `Regex`: matching one takes about 0.1 ms, and every card asks at every render (a fifth of the
    /// main thread's time in a swipe across tabs).
    public init?(_ label: String?) {
        guard let label, label.hasPrefix("ovvi:") else { return nil }
        let body = label.dropFirst(5), head = body.prefix { $0 != " " }
        guard let hash = head.firstIndex(of: "#") else { return nil }
        let plugin = head[..<hash], iid = head[head.index(after: hash)...]
        func word(_ text: Substring, _ most: Int, _ also: String) -> Bool {
            let low = { (char: Character) in char.isASCII && (char.isLowercase || char.isNumber) }
            return (1 ... most).contains(text.count) && text.first.map(low) == true
                && text.allSatisfy { low($0) || also.contains($0) }
        }
        guard PluginManifest.isID(plugin), iid.count == 6, word(iid, 6, "") else { return nil }
        let arg = String(body[head.endIndex...].drop { $0 == " " })
        guard arg.count <= Self.argLimit, !arg.contains(where: \.isControl) else { return nil }
        self.init(plugin: String(plugin), iid: String(iid), arg: arg)
    }

    public var text: String {
        "ovvi:\(plugin)#\(iid)" + (arg.isEmpty ? "" : " \(arg)")
    }

    public static let argLimit = 1024

    /// herdr can hold it: no control character, a short enough argument.
    public var fits: Bool {
        Self(text) != nil
    }

    public static func newIID(taken: Set<String>) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        while true {
            let iid = String((0 ..< 6).map { _ in alphabet.randomElement() ?? "a" })
            if !taken.contains(iid) {
                return iid
            }
        }
    }

    /// herdr saves it and, after a restart, brings the pane back only if it is still there.
    public var folder: String? {
        guard arg.hasPrefix("/"), let slash = arg.lastIndex(of: "/") else { return nil }
        return slash == arg.startIndex ? "/" : String(arg[..<slash])
    }

    public var diffSource: String? {
        guard let space = arg.lastIndex(of: " "), arg[..<space].hasSuffix("/") else { return nil }
        return String(arg[arg.index(after: space)...])
    }

    public func statePath(session: String) -> String {
        "\(Self.stateFolder)/\(session)/\(plugin)/\(iid).json"
    }

    static let stateFolder = ".local/state/ovvi"
}

public extension Program {
    /// herdr lists no argv for the script's `sh`. The caller asks it only of a pane with a plugin label.
    var isPlaceholder: Bool {
        name == "cat" && foreground.count <= 2
    }
}

extension Character {
    var isControl: Bool {
        unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

public extension Exec {
    /// Each writer goes through its own temporary file; last writer wins. Only the user can read it.
    func write(home path: String, _ line: String) async {
        let script = #"umask 077; f="$HOME/$1"; mkdir -p "${f%/*}" && cat >"$f.$$" && mv "$f.$$" "$f""#
        await succeeds(script, [path], input: [line])
    }

    /// Every write refreshes a file's age.
    func pruneState(session: String) async {
        _ = try? await output([
            "sh",
            "-c",
            #"find "$HOME/\#(PaneLabel.stateFolder)/$1" -type f -mtime +30 -delete 2>/dev/null"#,
            "sh",
            session,
        ])
    }

    func remove(home path: String) async {
        _ = try? await output(["sh", "-c", #"rm -f "$HOME/$1""#, "sh", path])
    }
}
