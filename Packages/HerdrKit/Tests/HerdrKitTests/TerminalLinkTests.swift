import Foundation
@testable import HerdrKit
import Testing

/// What a line shows as links: the text each covers, and where it goes.
private struct Found: Equatable, Sendable, CustomStringConvertible {
    let shown: String, kind: TerminalLink.Kind, target: String
    var line: Int?, column: Int?

    var description: String {
        "\(shown) (\(kind) \(target) \(line.map(String.init) ?? "-"):\(column.map(String.init) ?? "-"))"
    }
}

private func web(_ shown: String) -> Found {
    Found(shown: shown, kind: .web, target: shown)
}

private func other(_ shown: String) -> Found {
    Found(shown: shown, kind: .other, target: shown)
}

private func mail(_ shown: String) -> Found {
    Found(shown: shown, kind: .mail, target: shown.hasPrefix("mailto:") ? shown : "mailto:" + shown)
}

private func file(_ shown: String, _ target: String? = nil, line: Int? = nil, column: Int? = nil) -> Found {
    Found(shown: shown, kind: .file, target: target ?? shown, line: line, column: column)
}

private func found(_ text: String) -> [Found] {
    let chars = Array(text)
    return TerminalLink.all(in: text).map {
        Found(shown: String(chars[$0.range]), kind: $0.kind, target: $0.target, line: $0.line, column: $0.column)
    }
}

private let cases: [(String, [Found])] = [
    // Slash commands, fractions, dates and words with a slash are no paths.
    ("/compact", []),
    ("/help", []),
    ("/model sonnet", []),
    ("type /compact to shrink the context", []),
    ("/reload your open pi", []),
    ("1/2 done", []),
    ("2026/11/11", []),
    ("on 11/11/2026 at noon", []),
    ("/1/2", []),
    ("and/or", []),
    ("TCP/IP over km/h", []),
    ("// a comment", []),
    ("src/", []),
    ("12/25 tests passed", []),

    // Web addresses and where they end.
    ("https://example.com", [web("https://example.com")]),
    ("see https://x.dev/a. Next sentence", [web("https://x.dev/a")]),
    ("see https://x.dev/a, then https://y.dev/b; done", [web("https://x.dev/a"), web("https://y.dev/b")]),
    ("open https://x.dev/a!", [web("https://x.dev/a")]),
    ("is it https://x.dev/a?", [web("https://x.dev/a")]),
    ("at https://x.dev/a: the docs", [web("https://x.dev/a")]),
    ("(see https://x.dev/a)", [web("https://x.dev/a")]),
    ("[docs](https://x.dev/a)", [web("https://x.dev/a")]),
    ("{https://x.dev/a}", [web("https://x.dev/a")]),
    ("\"https://x.dev/a\"", [web("https://x.dev/a")]),
    ("'https://x.dev/a',", [web("https://x.dev/a")]),
    ("<https://x.dev/a>", [web("https://x.dev/a")]),
    ("`https://x.dev/a`", [web("https://x.dev/a")]),
    ("**https://x.dev/a**", [web("https://x.dev/a")]),
    ("_https://x.dev/a_", [web("https://x.dev/a")]),
    ("https://en.wikipedia.org/wiki/Swift_(programming_language)",
     [web("https://en.wikipedia.org/wiki/Swift_(programming_language)")]),
    ("(https://en.wikipedia.org/wiki/Swift_(programming_language))",
     [web("https://en.wikipedia.org/wiki/Swift_(programming_language)")]),
    ("https://x.dev/search?q=a+b&page=2#results", [web("https://x.dev/search?q=a+b&page=2#results")]),
    ("http://localhost:3000/", [web("http://localhost:3000/")]),
    ("Local: http://127.0.0.1:8080/app?debug=1", [web("http://127.0.0.1:8080/app?debug=1")]),
    ("http://[::1]:8080/path", [web("http://[::1]:8080/path")]),
    ("http://[2001:db8::1]/", [web("http://[2001:db8::1]/")]),
    ("https://x.dev/a_b-c~d/%20e", [web("https://x.dev/a_b-c~d/%20e")]),
    ("HTTPS://X.DEV/A", [web("HTTPS://X.DEV/A")]),
    ("https://x.dev/a│ next cell", [web("https://x.dev/a")]),
    ("https://ja.wikipedia.org/wiki/東京", [web("https://ja.wikipedia.org/wiki/東京")]),
    ("https://", []),
    ("https://x.dev/a.md", [web("https://x.dev/a.md")]),
    ("ftp://example.com/x", [other("ftp://example.com/x")]),
    ("ssh://me@host:22/repo", [other("ssh://me@host:22/repo")]),
    // A bare domain is no link: it reads as a file name too (`README.md`, `package.json`).
    ("example.com", []),
    ("go to www.example.com now", []),

    // Emails.
    ("mail me@example.com.", [mail("me@example.com")]),
    ("<first.last+tag@mail.example.org>", [mail("first.last+tag@mail.example.org")]),
    ("mailto:me@example.com?subject=hi", [mail("mailto:me@example.com?subject=hi")]),
    ("git@github.com:me/repo.git", []),
    ("@scope/package", []),
    ("me@localhost", []),

    // Absolute, home and relative paths.
    ("/tmp/a.txt", [file("/tmp/a.txt")]),
    ("... at /tmp/a.txt, then", [file("/tmp/a.txt")]),
    ("saved to /tmp/a.txt.", [file("/tmp/a.txt")]),
    ("/usr/local/bin", [file("/usr/local/bin")]),
    ("/tmp/", [file("/tmp/")]),
    ("/notes.md", [file("/notes.md")]),
    ("~/foo/bar.txt", [file("~/foo/bar.txt")]),
    ("~/", [file("~/")]),
    ("cd ~/code", [file("~/code")]),
    ("./build.sh", [file("./build.sh")]),
    ("../lib/x", [file("../lib/x")]),
    ("src/main.rs", [file("src/main.rs")]),
    ("Ovvi/Terminal/Links.swift:104", [file("Ovvi/Terminal/Links.swift:104", "Ovvi/Terminal/Links.swift", line: 104)]),
    ("/tmp/a.swift:12:5: error: bad", [file("/tmp/a.swift:12:5", "/tmp/a.swift", line: 12, column: 5)]),
    ("src/a.ts:7", [file("src/a.ts:7", "src/a.ts", line: 7)]),
    ("/tmp/a.txt:", [file("/tmp/a.txt")]),
    ("node_modules/@types/node/index.d.ts", [file("node_modules/@types/node/index.d.ts")]),
    ("app/(home)/[id]/page.tsx", [file("app/(home)/[id]/page.tsx")]),
    ("Read(/tmp/a.txt)", [file("/tmp/a.txt")]),
    ("Update(src/foo.swift)", [file("src/foo.swift")]),
    ("(/tmp/a.txt)", [file("/tmp/a.txt")]),
    ("`/tmp/a.txt`", [file("/tmp/a.txt")]),
    ("**src/a.swift**", [file("src/a.swift")]),
    ("--out=/tmp/out.json", [file("/tmp/out.json")]),
    ("PATH=/usr/bin:/bin", [file("/usr/bin")]),
    ("cp /tmp/a.txt /tmp/b.txt", [file("/tmp/a.txt"), file("/tmp/b.txt")]),
    ("/tmp/my\\ file.txt", [file("/tmp/my\\ file.txt", "/tmp/my file.txt")]),
    ("file:///tmp/a.txt", [Found(shown: "file:///tmp/a.txt", kind: .file, target: "file:///tmp/a.txt")]),
    ("Links.swift", []),
    ("e.g. this", []),

    // Spaces only between quotes.
    ("/tmp/my file.txt", [file("/tmp/my")]),
    ("open '/tmp/my file.txt' now", [file("/tmp/my file.txt")]),
    ("\"~/My Notes/a b.md\"", [file("~/My Notes/a b.md")]),
    ("\"not a path\" and 'also not'", []),
    ("it's \"/tmp/a b.txt\"", [file("/tmp/a b.txt")]),

    // Diffs drop `a/` and `b/`.
    ("--- a/Ovvi/Links.swift", [file("a/Ovvi/Links.swift", "Ovvi/Links.swift")]),
    ("+++ b/Ovvi/Links.swift", [file("b/Ovvi/Links.swift", "Ovvi/Links.swift")]),
    ("diff --git a/x.swift b/x.swift", [file("a/x.swift", "x.swift"), file("b/x.swift", "x.swift")]),
    ("a/x.swift", [file("a/x.swift")]),

    // A quoted sentence keeps its own paths.
    ("git commit -m \"fix Ovvi/a.swift and docs/b.mdx\"", [file("Ovvi/a.swift"), file("docs/b.mdx")]),
    ("\"see /tmp/a.txt and more.md\"", [file("/tmp/a.txt")]),
    ("echo 'copy a/b.txt to c/d.txt'", [file("a/b.txt"), file("c/d.txt")]),
    ("`src/a b.ts`", []),

    // Mentions, variables and commands.
    ("look at @Ovvi/Terminal/Links.swift", [file("Ovvi/Terminal/Links.swift")]),
    ("@/tmp/a.txt", [file("/tmp/a.txt")]),
    ("$HOME/foo.txt", []),
    ("${HOME}/foo.txt", []),
    ("$(pwd)/a.txt", []),

    // Other compilers' and tracebacks' lines.
    ("File \"/tmp/a.py\", line 12, in main", [file("/tmp/a.py", line: 12)]),
    ("src/a.ts(3,7): error TS2322", [file("src/a.ts(3,7)", "src/a.ts", line: 3, column: 7)]),

    // A path inside an address is the address's.
    ("https://x.dev/tmp/a.txt", [web("https://x.dev/tmp/a.txt")]),
    ("see https://x.dev/a and /tmp/b.txt", [web("https://x.dev/a"), file("/tmp/b.txt")]),
]

@Test(arguments: cases)
private func `a terminal line has its links`(text: String, expected: [Found]) {
    #expect(found(text) == expected, "\(text)")
}

@Test func `the link under a character`() {
    let text = "see https://x.dev/a. Next /tmp/b.txt"
    #expect(TerminalLink.at(4, in: text)?.target == "https://x.dev/a")
    #expect(TerminalLink.at(18, in: text)?.target == "https://x.dev/a")
    #expect(TerminalLink.at(19, in: text) == nil)
    #expect(TerminalLink.at(30, in: text)?.target == "/tmp/b.txt")
    #expect(TerminalLink.at(0, in: text) == nil)
}

/// Rows as cells: one string a cell, `" "` blank, `""` a wide glyph's second cell.
private func cells(_ rows: [String], columns: Int) -> (Int) -> [String] {
    { index in
        var cells: [String] = []
        for char in rows[index] {
            cells.append(String(char))
            if char == "東" || char == "京" {
                cells.append("")
            }
        }
        return cells + Array(repeating: " ", count: max(0, columns - cells.count))
    }
}

@Test func `an address wrapped across rows is one link`() {
    let rows = ["see https://x.dev/a", "aaa/end now", "", "next"]
    let (text, places) = TerminalLink.line(at: 1, rows: rows.count, cells: cells(rows, columns: 19))
    #expect(text.hasPrefix("see https://x.dev/aaaa/end now"))
    let link = TerminalLink.at(places.firstIndex { $0 == .init(row: 1, column: 2) } ?? -1, in: text)
    #expect(link?.target == "https://x.dev/aaaa/end")
    #expect(places[link?.range.lowerBound ?? 0] == .init(row: 0, column: 4))
    #expect(places[(link?.range.upperBound ?? 1) - 1] == .init(row: 1, column: 6))
}

@Test func `a row that does not fill its width ends its line`() {
    let rows = ["/tmp/a.txt", "b/c.swift"]
    let (text, _) = TerminalLink.line(at: 0, rows: rows.count, cells: cells(rows, columns: 20))
    #expect(text.trimmingCharacters(in: .whitespaces) == "/tmp/a.txt")
    let (second, _) = TerminalLink.line(at: 1, rows: rows.count, cells: cells(rows, columns: 20))
    #expect(second.hasPrefix("b/c.swift"))
}

@Test func `a wide glyph's cells map to one character`() {
    let rows = ["東京 /tmp/a.txt"]
    let (text, places) = TerminalLink.line(at: 0, rows: 1, cells: cells(rows, columns: 20))
    let link = TerminalLink.at(places.firstIndex { $0.column == 6 } ?? -1, in: text)
    #expect(link?.target == "/tmp/a.txt")
    #expect(places[link?.range.lowerBound ?? 0].column == 5)
}
