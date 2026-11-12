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
    /// The links' color: the accent, white in the user's bubble.
    @Entry var chatLink = Color.accentColor
}

/// Text whose links look like links in any app: underlined, in the link color, and lighter with the pointing hand
/// under the pointer. A clear area over each link takes its pointer and click: selectable text shows its I-beam over a
/// `pointerStyle` of its own, and SwiftUI then sends no hover, so an AppKit tracking area tells the link.
/// ponytail: past `hovers` links (a tool's output that lists paths) no hover: each link nests the joined `Text` a level
/// deeper, and 750 levels overflowed the stack. Join in pairs if long lists need it.
struct LinkedText: View {
    let text: AttributedString
    @State private var hovered: Int?
    @Environment(\.openURL) private var openURL
    @Environment(\.chatLink) private var color
    private static let hovers = 100

    var body: some View {
        let links = text.runs[\.link].compactMap { url, range in url.map { ($0, range) } }
        if links.isEmpty {
            Text(text)
        } else if links.count > Self.hovers {
            Text(links.reduce(into: text) { text, link in
                text[link.1].underlineStyle = .single
                text[link.1].foregroundColor = color
            })
        } else {
            joined(links.map(\.1))
                .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { geometry in
                        let parts = Self.frames(layouts, geometry)
                        LinkHover(parts: parts) { link in
                            if link != hovered {
                                hovered = link
                            }
                        }
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
                .textRenderer(Hover(link: hovered))
        }
    }

    /// Each link a `Text` of its own, marked, so that the layout tells where it is.
    private func joined(_ links: [Range<AttributedString.Index>]) -> Text {
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
private struct LinkPart: Equatable {
    let link: Int, rect: CGRect
}

/// The link under the pointer lighter, drawn without a new layout: a new one clears a selection.
private struct Hover: TextRenderer {
    let link: Int?

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flatMap(\.self) {
            var context = context
            if link != nil, run[LinkMark.self]?.index == link {
                context.opacity = 0.7
            }
            context.draw(run)
        }
    }
}

/// Which link the pointer is over, from an AppKit tracking area: SwiftUI sends no hover under the links' click areas.
private struct LinkHover: NSViewRepresentable {
    let parts: [LinkPart]
    let hover: (Int?) -> Void

    func makeNSView(context _: Context) -> Tracker {
        Tracker()
    }

    func updateNSView(_ view: Tracker, context _: Context) {
        view.parts = parts
        view.hover = hover
    }

    final class Tracker: NSView {
        var parts: [LinkPart] = []
        var hover: (Int?) -> Void = { _ in }
        override var isFlipped: Bool {
            true
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited,
                                                                  .activeInActiveApp, .inVisibleRect],
                                           owner: self))
        }

        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            hover(parts.first { $0.rect.contains(point) }?.link)
        }

        override func mouseExited(with _: NSEvent) {
            hover(nil)
        }
    }
}
