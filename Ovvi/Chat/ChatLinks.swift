import HerdrKit
import SwiftUI

/// The chat's links: what the terminal finds in its text (`TerminalLink`), opened as the terminal opens them.
enum ChatLinks {
    /// A found link rides in SwiftUI's `.link` as JSON under this scheme: a path is no URL.
    private static let scheme = "ovvi-chat-link"

    /// Each line's links, as the terminal finds them in a line.
    static func linked(_ string: String) -> AttributedString {
        var text = AttributedString(string)
        var start = text.startIndex
        for line in string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            // Every link holds one: most lines have none, and the finder shows in a long chat's layout.
            let links = line.contains { $0 == "/" || $0 == "@" } ? TerminalLink.all(in: String(line)) : []
            for link in links {
                guard let data = try? JSONEncoder().encode(link),
                      let json = String(data: data, encoding: .utf8)?
                          .addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                      let url = URL(string: "\(scheme):\(json)") else { continue }
                let from = text.characters.index(start, offsetBy: link.range.lowerBound)
                text[from ..< text.characters.index(from, offsetBy: link.range.count)].link = url
            }
            start = text.characters.index(start, offsetBy: line.count)
            if start < text.endIndex {
                start = text.characters.index(after: start)
            }
        }
        return text
    }

    /// A Markdown link opens only a web page or a mail address: its label hides where it goes, and a transcript (or a
    /// page the agent quotes) could hold `file:`, `ovvi:` or this file's own links.
    static func markdown(_ destination: String?) -> URL? {
        guard let url = destination.flatMap(URL.init(string:)),
              url.isWebAddress || url.scheme?.lowercased() == "mailto" else { return nil }
        return url
    }

    /// A text without links stays a plain `Text`: no layout reads, hover tracking or `openURL` for most paragraphs.
    @ViewBuilder static func text(_ text: AttributedString) -> some View {
        if text.runs[\.link].contains(where: { $0.0 != nil }) {
            LinkedText(text: text)
        } else {
            Text(text)
        }
    }

    static func link(_ url: URL) -> TerminalLink? {
        if url.scheme == scheme {
            let json = url.absoluteString.dropFirst(scheme.count + 1).removingPercentEncoding ?? ""
            return try? JSONDecoder().decode(TerminalLink.self, from: Data(json.utf8))
        }
        return markdown(url.absoluteString).map {
            TerminalLink(range: 0 ..< 0, kind: $0.isWebAddress ? .web : .mail, target: $0.absoluteString)
        }
    }
}

extension EnvironmentValues {
    /// The links' color: white in the user's bubble, else the look's.
    @Entry var chatLink: Color?
}

/// Text whose links look as a browser draws them by default: underlined, in the link color, with the pointing hand and
/// no change under the pointer. A clear area over each link takes its pointer and click: selectable text shows its
/// I-beam over a `pointerStyle` of its own.
/// ponytail: past `areas` links (a tool's output that lists paths) no areas, so the I-beam: each link nests the joined
/// `Text` a level deeper, and 750 levels overflowed the stack. Join in pairs if long lists need it.
struct LinkedText: View {
    let text: AttributedString
    @Environment(\.openURL) private var openURL
    @Environment(\.chatLink) private var chatLink
    @Environment(\.look) private var look
    private static let areas = 100

    var body: some View {
        let links = text.runs[\.link].compactMap { url, range in url.map { ($0, range) } }
        let color = chatLink ?? look.link
        if links.count > Self.areas {
            Text(links.reduce(into: text) { text, link in
                text[link.1].underlineStyle = .single
                text[link.1].foregroundColor = color
            })
        } else {
            joined(links.map(\.1), color: color)
                .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { geometry in
                        let parts = Self.frames(layouts, geometry)
                        ForEach(parts.indices, id: \.self) { place in
                            let part = parts[place]
                            Color.clear.contentShape(.rect)
                                .frame(width: part.rect.width, height: part.rect.height)
                                .position(x: part.rect.midX, y: part.rect.midY)
                                .pointerStyle(.link)
                                .accessibilityHidden(true)
                                .onTapGesture {
                                    if part.link < links.count {
                                        openURL(links[part.link].0)
                                    }
                                }
                        }
                    }
                }
        }
    }

    /// Each link a `Text` of its own, marked, so that the layout tells where it is.
    private func joined(_ links: [Range<AttributedString.Index>], color: Color) -> Text {
        var parts: [Text] = [], end = text.startIndex
        for (index, range) in links.enumerated() {
            var link = AttributedString(text[range])
            link.underlineStyle = .single
            link.foregroundColor = color
            parts += [Text(AttributedString(text[end ..< range.lowerBound])),
                      Text(link).customAttribute(LinkMark(index: index))]
            end = range.upperBound
        }
        parts.append(Text(AttributedString(text[end...])))
        return parts.dropFirst().reduce(parts[0]) { Text("\($0)\($1)") }
    }

    /// Each line's part of each link.
    private static func frames(_ layouts: [Text.LayoutKey.AnchoredLayout],
                               _ geometry: GeometryProxy) -> [LinkPart]
    {
        layouts.flatMap { anchored in
            let origin = geometry[anchored.origin]
            return anchored.layout.flatMap { line in
                line.compactMap { run in
                    run[LinkMark.self]
                        .map { LinkPart(
                            link: $0.index,
                            rect: run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y),
                        ) }
                }
            }
        }
    }
}

private struct LinkMark: TextAttribute {
    let index: Int
}

/// A line's part of a link.
private struct LinkPart {
    let link: Int, rect: CGRect
}
