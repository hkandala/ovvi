import AppKit
import SwiftUI

/// A callout on a page's picture: the point it names (in the shot's points), where its line ends (in the picture's
/// points, so labels line up as on a keynote slide), the side of that end its label sits on, and its keys.
struct Callout {
    let label: String
    var keys: [String] = []
    let point: CGPoint
    let end: CGPoint
    let side: Side

    enum Side {
        case left, right, above, below

        /// The label's edge that touches the line's end.
        var alignment: Alignment {
            switch self {
            case .left: .trailing
            case .right: .leading
            case .above: .bottom
            case .below: .top
            }
        }

        /// The space between the line's end and the label.
        var gap: CGSize {
            switch self {
            case .left: CGSize(width: -4, height: 0)
            case .right: CGSize(width: 4, height: 0)
            case .above: CGSize(width: 0, height: -4)
            case .below: CGSize(width: 0, height: 4)
            }
        }

        /// Where the label comes from as it fades in: a few points back along the line.
        var lift: CGSize {
            CGSize(width: -gap.width, height: -gap.height)
        }
    }
}

/// The welcome's pages: an annotated tour of one window (ui/welcome).
enum Tour {
    struct Page {
        let title: String
        let text: String
        /// The image set; nil on the herdr step, which draws its own.
        var shot: String?
        var focus = Tour.whole
        var callouts: [Callout] = []
    }

    /// The panel's picture, over its text band.
    static let picture = CGSize(width: 960, height: 500)
    /// The shots' size in points (taken at 2x by scripts/welcome-pictures.sh).
    static let shot = CGSize(width: 1440, height: 900)
    /// The whole window, with room around it for the first page's labels.
    static let whole = CGRect(x: -370, y: -118, width: 2180, height: 1136)

    static let pages = [
        Page(title: "Welcome to Ovvi",
             text: "Your terminals, agents and tools in one Mac window. They run in sessions, so they keep going when "
                 + "you close the window or quit Ovvi.",
             shot: "welcome-main",
             callouts: [
                 Callout(label: "Spaces", point: CGPoint(x: 150, y: 300), end: CGPoint(x: 140, y: 184), side: .left),
                 Callout(label: "Tabs", point: CGPoint(x: 601, y: 30), end: CGPoint(x: 427, y: 36), side: .above),
                 Callout(label: "Panes", point: CGPoint(x: 1150, y: 470), end: CGPoint(x: 830, y: 259),
                         side: .right),
                 Callout(label: "An agent", point: CGPoint(x: 580, y: 760), end: CGPoint(x: 418, y: 462),
                         side: .below),
             ]),
        Page(title: "Panes and splits",
             text: "Every card is a pane. Split one, and the new pane asks what it runs: a terminal, an agent, a "
                 + "browser, File Explorer or Git.",
             shot: "welcome-split", focus: CGRect(x: 472, y: 250, width: 960, height: 500),
             callouts: [
                 Callout(label: "Split Right", keys: ["⌘D"], point: CGPoint(x: 866, y: 330),
                         end: CGPoint(x: 308, y: 80), side: .left),
                 Callout(label: "It asks what it runs", keys: ["↩ Terminal"], point: CGPoint(x: 1020, y: 613),
                         end: CGPoint(x: 548, y: 295), side: .above),
                 Callout(label: "Split Down", keys: ["⇧⌘D"], point: CGPoint(x: 1320, y: 467),
                         end: CGPoint(x: 848, y: 262), side: .below),
             ]),
        Page(title: "Tabs and spaces",
             text: "A tab holds a set of panes. A space is one project, with its folder, its Git branch and its own "
                 + "tabs. Its agents show their state: blue works, orange needs you, green is done.",
             shot: "welcome-agents", focus: CGRect(x: 0, y: 0, width: 960, height: 500),
             callouts: [
                 Callout(label: "Tabs", keys: ["⌘T", "⌘1–9"], point: CGPoint(x: 601, y: 34),
                         end: CGPoint(x: 601, y: 150), side: .below),
                 Callout(label: "Its Git branch", point: CGPoint(x: 50, y: 115), end: CGPoint(x: 340, y: 128),
                         side: .right),
                 Callout(label: "Spaces", keys: ["⌃⌘T", "⌃⌘1–9"], point: CGPoint(x: 200, y: 300),
                         end: CGPoint(x: 340, y: 300), side: .right),
                 Callout(label: "Its agents, and their state", point: CGPoint(x: 268, y: 428),
                         end: CGPoint(x: 340, y: 428), side: .right),
             ]),
        Page(title: "Agents, as a terminal or a chat",
             text: "Run Claude Code, Codex, Pi or OpenCode in a pane. Read it as its terminal or as a chat: it is "
                 + "the same running agent.",
             shot: "welcome-main", focus: CGRect(x: 240, y: 40, width: 960, height: 500),
             callouts: [
                 Callout(label: "Chat or TUI: the same agent", point: CGPoint(x: 814, y: 98),
                         end: CGPoint(x: 574, y: 124), side: .below),
                 Callout(label: "Each tool call, one row", point: CGPoint(x: 520, y: 330),
                         end: CGPoint(x: 430, y: 290), side: .right),
             ]),
        Page(title: "Plugins, built in and your own",
             text: "Browser, Git and File Explorer come with Ovvi. Make your own in TypeScript with New Plugin…, or "
                 + "ask your agent: it builds and opens them with the ovvi command.",
             shot: "welcome-plugins", focus: CGRect(x: 300, y: 46, width: 1140, height: 593),
             callouts: [
                 Callout(label: "File Explorer", point: CGPoint(x: 700, y: 130), end: CGPoint(x: 200, y: 130),
                         side: .left),
                 Callout(label: "Your own plugin, in TypeScript", point: CGPoint(x: 375, y: 567),
                         end: CGPoint(x: 300, y: 439), side: .right),
             ]),
        Page(title: "Any machine you can ssh to",
             text: "Add a machine, and its sessions open in a window of their own. Your SSH config works as it is, "
                 + "and work there keeps running while your Mac sleeps.",
             shot: "welcome-machines", focus: CGRect(x: 0, y: 0, width: 960, height: 500),
             callouts: [
                 Callout(label: "This Mac", point: CGPoint(x: 240, y: 57), end: CGPoint(x: 400, y: 57), side: .right),
                 Callout(label: "Your machines", point: CGPoint(x: 255, y: 105), end: CGPoint(x: 400, y: 105),
                         side: .right),
                 Callout(label: "Add Machine…", point: CGPoint(x: 255, y: 199), end: CGPoint(x: 400, y: 199),
                         side: .right),
             ]),
    ]

    static let herdr = Page(title: "One more thing: herdr",
                            text: "Ovvi keeps your terminals and agents in herdr's sessions on This Mac. Install it "
                                + "to begin.")
}

/// The shots of the panel's appearance, decoded off the main thread while the intro plays: drawn straight from the
/// asset catalog, a 2880 × 1800 HEIC decoded on the main thread as its page came in, for 240 to 730 ms.
@MainActor @Observable
final class TourShots {
    private(set) var images: [String: CGImage] = [:]

    static func key(_ name: String, dark: Bool) -> String {
        "\(name) \(dark ? "dark" : "light")"
    }

    func load(dark: Bool) async {
        for name in Set(Tour.pages.compactMap(\.shot)) where images[Self.key(name, dark: dark)] == nil {
            let image = await Task.detached(priority: .userInitiated) { Self.decode(name, dark: dark) }.value
            images[Self.key(name, dark: dark)] = image
        }
    }

    private nonisolated static func decode(_ name: String, dark: Bool) -> CGImage? {
        guard let image = NSImage(named: name), let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else {
            return nil
        }
        var decoded: CGImage?
        appearance.performAsCurrentDrawingAppearance {
            var rect = CGRect(origin: .zero, size: image.size)
            guard let source = image.cgImage(
                      forProposedRect: &rect,
                      context: nil,
                      hints: [.ctm: AffineTransform(scale: 2)],
                  ),
                  let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: source.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return }
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            decoded = context.makeImage()
        }
        return decoded
    }
}
