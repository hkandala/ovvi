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
        for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
            for link in TerminalLink.all(in: String(line)) {
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

    static func link(_ url: URL) -> TerminalLink? {
        if url.scheme == scheme {
            let json = url.absoluteString.dropFirst(scheme.count + 1).removingPercentEncoding ?? ""
            return try? JSONDecoder().decode(TerminalLink.self, from: Data(json.utf8))
        }
        return markdown(url.absoluteString).flatMap { TerminalLink.all(in: $0.absoluteString).first }
    }
}

extension EnvironmentValues {
    /// The links' color: the accent, white in the user's bubble.
    @Entry var chatLink = Color.accentColor
}

/// Text whose links look like links in any app: underlined, in the link color, and lighter with the pointing hand
/// under the pointer.
struct LinkedText: View {
    let text: AttributedString
    @State private var frames: [[CGRect]] = []
    @State private var hovered: Int?
    @Environment(\.chatLink) private var color

    var body: some View {
        let links = text.runs[\.link].filter { $0.0 != nil }.map(\.1)
        if links.isEmpty {
            Text(text)
        } else {
            joined(links)
                .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { geometry in
                        Color.clear.preference(key: LinkFrames.self, value: Self.frames(layouts, geometry, links.count))
                    }
                }
                .onPreferenceChange(LinkFrames.self) { frames = $0 }
                .onContinuousHover { phase in
                    guard case let .active(point) = phase else { return hovered = nil }
                    let found = frames.firstIndex { $0.contains { $0.insetBy(dx: 0, dy: -2).contains(point) } }
                    if found != hovered {
                        hovered = found
                    }
                }
                .pointerStyle(hovered == nil ? nil : .link)
        }
    }

    /// Each link a `Text` of its own, marked, so that the layout tells where it is.
    private func joined(_ links: [Range<AttributedString.Index>]) -> Text {
        var parts: [Text] = [], end = text.startIndex
        for (index, range) in links.enumerated() {
            var link = AttributedString(text[range])
            link.underlineStyle = .single
            link.foregroundColor = hovered == index ? color.opacity(0.7) : color
            parts += [Text(AttributedString(text[end ..< range.lowerBound])),
                      Text(link).customAttribute(LinkMark(index: index))]
            end = range.upperBound
        }
        parts.append(Text(AttributedString(text[end...])))
        return parts.dropFirst().reduce(parts[0]) { Text("\($0)\($1)") }
    }

    private static func frames(_ layouts: [Text.LayoutKey.AnchoredLayout], _ geometry: GeometryProxy,
                               _ count: Int) -> [[CGRect]]
    {
        var frames = Array(repeating: [CGRect](), count: count)
        for anchored in layouts {
            let origin = geometry[anchored.origin]
            for line in anchored.layout {
                for run in line {
                    if let mark = run[LinkMark.self], mark.index < count {
                        frames[mark.index].append(run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y))
                    }
                }
            }
        }
        return frames
    }
}

private struct LinkMark: TextAttribute {
    let index: Int
}

private struct LinkFrames: PreferenceKey {
    static let defaultValue: [[CGRect]] = []

    static func reduce(value: inout [[CGRect]], nextValue: () -> [[CGRect]]) {
        value += nextValue()
    }
}
