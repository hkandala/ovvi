/// A link in a terminal's text: a web address, an email, another `scheme://` address, or a file path.
public struct TerminalLink: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case web, mail, file, other
    }

    /// In the line's characters, with a path's `:line:column`.
    public let range: Range<Int>
    public let kind: Kind
    /// The address (`mailto:` for an email), or the path: shell escapes undone, a diff's `a/` or `b/` dropped.
    public let target: String
    public var line: Int?
    public var column: Int?

    public init(range: Range<Int>, kind: Kind, target: String, line: Int? = nil, column: Int? = nil) {
        self.range = range
        self.kind = kind
        self.target = target
        self.line = line
        self.column = column
    }

    public static func at(_ index: Int, in text: String) -> TerminalLink? {
        all(in: text).first { $0.range.contains(index) }
    }

    /// Quoted paths first (they may hold spaces), then addresses, then emails, then the other paths.
    public static func all(in text: String) -> [TerminalLink] {
        var finder = Finder(Array(text))
        finder.quoted()
        finder.addresses()
        finder.emails()
        finder.paths()
        return finder.links.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}

private struct Finder {
    let chars: [Character]
    var links: [TerminalLink] = []
    var taken: [Bool]
    let diff: Bool

    init(_ chars: [Character]) {
        self.chars = chars
        taken = Array(repeating: false, count: chars.count)
        let line = String(chars).drop { $0 == " " }
        diff = line.hasPrefix("--- a/") || line.hasPrefix("+++ b/") || line.hasPrefix("diff --git ")
    }

    private mutating func add(_ range: Range<Int>, _ kind: TerminalLink.Kind, _ target: String, line: Int? = nil,
                              column: Int? = nil)
    {
        links.append(TerminalLink(range: range, kind: kind, target: target, line: line, column: column))
        range.forEach { taken[$0] = true }
    }

    // MARK: Quoted paths

    /// `"/tmp/my file.txt"`: a path with spaces only between quotes, and one that starts as a path: a quoted sentence
    /// (`-m "fix a/b.swift and c/d.md"`) keeps its own paths.
    mutating func quoted() {
        var start = 0
        while start < chars.count {
            let quote = chars[start]
            guard "\"'`".contains(quote),
                  let end = chars[(start + 1)...].firstIndex(of: quote)
            else {
                start += 1
                continue
            }
            let inside = String(chars[(start + 1) ..< end])
            if inside.contains(" "), ["/", "~/", "./", "../"].contains(where: inside.hasPrefix), Self.isPath(inside) {
                add((start + 1) ..< end, .file, inside)
                start = end + 1
            } else {
                start += 1
            }
        }
    }

    // MARK: Addresses

    /// `scheme://…` and `mailto:…`.
    mutating func addresses() {
        var index = 0
        while index < chars.count {
            if let link = address(at: index) {
                add(link.range, link.kind, link.target)
                index = link.range.upperBound
            } else {
                index += 1
            }
        }
    }

    private func address(at start: Int) -> TerminalLink? {
        guard !taken[start], chars[start].isASCII, chars[start].isLetter,
              start == 0 || !Self.isSchemeChar(chars[start - 1])
        else { return nil }
        var index = start
        while index < chars.count, Self.isSchemeChar(chars[index]) {
            index += 1
        }
        let scheme = String(chars[start ..< index]).lowercased()
        let mail = scheme == "mailto" && index < chars.count && chars[index] == ":"
        guard mail || has("://", at: index) else { return nil }
        index += mail ? 1 : 3
        let body = index
        while index < chars.count, !taken[index], Self.isURLChar(chars[index]) {
            index += 1
        }
        let end = trimmed(start, index)
        guard end > body else { return nil }
        let kind: TerminalLink.Kind = switch scheme {
        case "http", "https": .web
        case "mailto": .mail
        case "file": .file
        default: .other
        }
        return TerminalLink(range: start ..< end, kind: kind, target: String(chars[start ..< end]))
    }

    private func has(_ text: String, at index: Int) -> Bool {
        let text = Array(text)
        return index + text.count <= chars.count && Array(chars[index ..< index + text.count]) == text
    }

    private static func isSchemeChar(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || "+.-".contains(char))
    }

    /// Printable ASCII but the characters RFC 3986 leaves out, and any other letter or digit (IDN hosts and paths);
    /// box drawing and other symbols end it.
    private static func isURLChar(_ char: Character) -> Bool {
        if char.isASCII {
            return char.isLetter || char.isNumber || "-._~:/?#[]@!$&'()*+,;=%".contains(char)
        }
        return char.isLetter || char.isNumber
    }

    // MARK: Emails

    mutating func emails() {
        for sign in chars.indices where chars[sign] == "@" && !taken[sign] {
            var start = sign
            while start > 0, !taken[start - 1], Self.isLocalChar(chars[start - 1]) {
                start -= 1
            }
            var end = sign + 1
            while end < chars.count, !taken[end], chars[end].isASCII,
                  chars[end].isLetter || chars[end].isNumber || "-.".contains(chars[end])
            {
                end += 1
            }
            while end > sign + 1, ".-".contains(chars[end - 1]) {
                end -= 1
            }
            let domain = String(chars[(sign + 1) ..< end]), tld = domain.split(separator: ".").last ?? ""
            // `git@github.com:me/repo.git` and `me@host/path` are no addresses.
            guard start < sign, domain.contains("."), tld.count >= 2, tld.allSatisfy(\.isLetter),
                  start == 0 || !"/:".contains(chars[start - 1]),
                  end == chars.count || !":/@".contains(chars[end])
            else { continue }
            add(start ..< end, .mail, "mailto:" + String(chars[start ..< end]))
        }
    }

    private static func isLocalChar(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || "._%+-".contains(char))
    }

    // MARK: Paths

    mutating func paths() {
        var index = 0
        while index < chars.count {
            guard !taken[index], Self.startsPath(chars[index]),
                  index == 0 || Self.isBoundary(chars[index - 1], before: chars[index]),
                  index < 2 || chars[index - 2] != "$" || !"{(".contains(chars[index - 1])
            else {
                index += 1
                continue
            }
            var end = index, open = 0
            while end < chars.count, !taken[end] {
                if chars[end] == "\\", end + 1 < chars.count, !chars[end + 1].isLetter, !chars[end + 1].isNumber {
                    end += 2
                } else if Self.isPathChar(chars[end]) {
                    end += 1
                } else if "([{".contains(chars[end]), chars[end - 1] == "/" {
                    open += 1
                    end += 1
                } else if ")]}".contains(chars[end]), open > 0 {
                    open -= 1
                    end += 1
                } else {
                    break
                }
            }
            let next = max(end, index + 1)
            end = trimmed(index, end)
            // Claude Code names a file `@src/a.ts`.
            let start = chars[index] == "@" ? index + 1 : index
            var path = Self.unescaped(String(chars[start ..< end]))
            if Self.isPath(path) {
                if diff, path.hasPrefix("a/") || path.hasPrefix("b/") {
                    path.removeFirst(2)
                }
                let (place, after) = place(after: end)
                add(start ..< after, .file, path, line: place.line, column: place.column)
            }
            index = next
        }
    }

    /// `:12` or `:12:5` right after the path, tsc's `(12,5)`, or Python's `", line 12` (kept out of the link).
    private func place(after end: Int) -> (place: (line: Int?, column: Int?), end: Int) {
        let rest = String(chars[end...].prefix(40))
        if let match = rest.prefixMatch(of: /\((\d+),(\d+)\)/), let line = Int(match.1), let column = Int(match.2) {
            return ((line, column), end + match.0.count)
        }
        if let match = rest.prefixMatch(of: /", line (\d+)/), let line = Int(match.1) {
            return ((line, nil), end)
        }
        func number(at colon: Int) -> (Int, Int)? {
            guard colon < chars.count, chars[colon] == ":" else { return nil }
            var end = colon + 1
            while end < chars.count, chars[end].isASCII, chars[end].isNumber {
                end += 1
            }
            return end > colon + 1 ? Int(String(chars[(colon + 1) ..< end])).map { ($0, end) } : nil
        }
        guard let (line, afterLine) = number(at: end) else { return ((nil, nil), end) }
        guard let (column, afterColumn) = number(at: afterLine) else { return ((line, nil), afterLine) }
        return ((line, column), afterColumn)
    }

    /// After a `:` only an absolute path starts (`PATH=/usr/bin:/bin`): `git@github.com:me/repo.git` is no path.
    /// Nor after `$` (`$HOME/a.txt`) or a closing bracket (`$(pwd)/a.txt`).
    private static func isBoundary(_ char: Character, before first: Character) -> Bool {
        !isPathChar(char) && !"\\$".contains(char) && (char != ":" || first == "/") && !")]}".contains(char)
    }

    private static func startsPath(_ char: Character) -> Bool {
        char == "/" || char == "~" || char == "." || char == "_" || char == "@" || char.isLetter || char.isNumber
    }

    /// No `:` (it starts a line number) and no `=` or `,` (`--out=/tmp/a`, `a.txt,b.txt`). A bracket opens only a
    /// name (`app/(home)/page.tsx`): `Read(/tmp/a.txt)` is a call on a path.
    private static func isPathChar(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || "-_.~/+@%".contains(char)
    }

    private static func unescaped(_ path: String) -> String {
        var out = "", escaped = false
        for char in path {
            if char == "\\", !escaped {
                escaped = true
                continue
            }
            out.append(char)
            escaped = false
        }
        return out
    }

    /// `/compact`, `1/2`, `2026/11/11` and `and/or` are no paths: an absolute path needs two names, an extension or
    /// a closing `/`; a relative one needs a `/` and an extension, unless it starts with `./` or `../`.
    static func isPath(_ path: String) -> Bool {
        if path.hasPrefix("~/") {
            return true
        }
        if path.hasPrefix("./") || path.hasPrefix("../") {
            return path.count > (path.hasPrefix("./") ? 2 : 3)
        }
        guard path.contains("/"), path.contains(where: \.isLetter), !path.hasPrefix("//") else { return false }
        let names = path.split(separator: "/"), last = names.last.map(String.init) ?? ""
        if path.hasPrefix("/") {
            return names.count >= 2 || path.hasSuffix("/") && !names.isEmpty || hasExtension(last)
        }
        return !path.hasSuffix("/") && hasExtension(last)
    }

    private static func hasExtension(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        let ext = name[name.index(after: dot)...]
        return (1 ... 10).contains(ext.count) && ext.contains(where: \.isLetter) && ext.allSatisfy(\.isASCII)
            && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }

    // MARK: Ends

    /// Drops the punctuation after a link: `.,;:!?`, a closing bracket or quote it did not open, markdown's `*`, and
    /// a `_` when one comes before it.
    private func trimmed(_ start: Int, _ end: Int) -> Int {
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        var end = end
        func count(_ char: Character) -> Int {
            chars[start ..< end].count { $0 == char }
        }
        while end > start {
            let last = chars[end - 1]
            let unopened = if let open = pairs[last] {
                count(open) < count(last)
            } else {
                "\"'".contains(last) && count(last) % 2 == 1
            }
            guard ".,;:!?*".contains(last) || unopened || last == "_" && start > 0 && chars[start - 1] == "_"
            else { break }
            end -= 1
        }
        return end
    }
}

public extension TerminalLink {
    struct Place: Equatable, Sendable {
        public let row: Int, column: Int

        public init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    /// The text of the line that `row` is part of, with each character's cell. `cells` reads a row: one string per
    /// cell, `""` for a wide glyph's second cell, `" "` for a blank one. A row whose last cell holds text goes on in
    /// the next row (herdr's frames carry no soft wraps).
    /// ponytail: a full-width row of a program's own also joins its next; a wrap flag from herdr would end that.
    static func line(at row: Int, rows: Int, cells: (Int) -> [String]) -> (text: String, places: [Place]) {
        var read: [Int: [String]] = [:]
        func cellsOf(_ index: Int) -> [String] {
            if let cached = read[index] {
                return cached
            }
            let cells = cells(index)
            read[index] = cells
            return cells
        }
        func full(_ index: Int) -> Bool {
            cellsOf(index).last.map { $0 != " " } ?? false
        }
        var first = row, last = row
        while first > 0, row - first < 20, full(first - 1) {
            first -= 1
        }
        while last < rows - 1, last - row < 20, full(last) {
            last += 1
        }
        var text: [Character] = [], places: [Place] = []
        for index in first ... last {
            for (column, cell) in cellsOf(index).enumerated() {
                for char in cell {
                    text.append(char)
                    places.append(Place(row: index, column: column))
                }
            }
        }
        return (String(text), places)
    }
}
