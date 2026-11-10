import ImageIO
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
    static let whole = CGRect(x: -186, y: -22, width: 1812, height: 944)

    static let pages = [
        Page(title: "Welcome to Ovvi",
             text: "Your terminals, agents and tools in one Mac window. They run in sessions, so they keep going when "
                 + "you close the window or quit Ovvi.",
             shot: "welcome-main",
             callouts: [
                 Callout(label: "Tabs", point: CGPoint(x: 379, y: 30), end: CGPoint(x: 214, y: 46), side: .left),
                 Callout(label: "Spaces", point: CGPoint(x: 14, y: 320), end: CGPoint(x: 90, y: 181), side: .left),
                 Callout(label: "An agent", point: CGPoint(x: 445, y: 700), end: CGPoint(x: 90, y: 382), side: .left),
                 Callout(label: "Panes", point: CGPoint(x: 1150, y: 470), end: CGPoint(x: 870, y: 261), side: .right),
             ]),
        Page(title: "Panes and splits",
             text: "Every card is a pane. Split one, and the new pane asks what it runs: a terminal, an agent, a "
                 + "browser, File Explorer or Git.",
             shot: "welcome-split", focus: CGRect(x: 280, y: 260, width: 960, height: 500),
             callouts: [
                 Callout(
                     label: "Split Right",
                     keys: ["⌘D"],
                     point: CGPoint(x: 866, y: 330),
                     end: CGPoint(x: 680, y: 70),
                     side: .right,
                 ),
                 Callout(
                     label: "It asks what it runs",
                     point: CGPoint(x: 449, y: 613),
                     end: CGPoint(x: 169, y: 290),
                     side: .above,
                 ),
                 Callout(
                     label: "Split Down",
                     keys: ["⇧⌘D"],
                     point: CGPoint(x: 700, y: 469),
                     end: CGPoint(x: 420, y: 262),
                     side: .below,
                 ),
             ]),
        Page(title: "Tabs and spaces",
             text: "A tab holds a set of panes. A space is one project, with its folder, its Git branch and its own "
                 + "tabs. Its agents show their state: blue works, orange needs you, green is done.",
             shot: "welcome-agents", focus: CGRect(x: 0, y: 0, width: 960, height: 500),
             callouts: [
                 Callout(
                     label: "Tabs",
                     keys: ["⌘T", "⌘1–9"],
                     point: CGPoint(x: 601, y: 34),
                     end: CGPoint(x: 601, y: 150),
                     side: .below,
                 ),
                 Callout(
                     label: "Its Git branch",
                     point: CGPoint(x: 60, y: 115),
                     end: CGPoint(x: 340, y: 128),
                     side: .right,
                 ),
                 Callout(
                     label: "Spaces",
                     keys: ["⌃⌘T", "⌃⌘1–9"],
                     point: CGPoint(x: 200, y: 300),
                     end: CGPoint(x: 340, y: 300),
                     side: .right,
                 ),
                 Callout(
                     label: "Its agents, and their state",
                     point: CGPoint(x: 268, y: 428),
                     end: CGPoint(x: 340, y: 428),
                     side: .right,
                 ),
             ]),
        Page(title: "Agents, as a terminal or a chat",
             text: "Run Claude Code, Codex, Pi or OpenCode in a pane. Read it as its terminal or as a chat: it is "
                 + "the same running agent.",
             shot: "welcome-pi", focus: CGRect(x: 240, y: 46, width: 1200, height: 625),
             callouts: [
                 Callout(
                     label: "Chat or TUI: the same agent",
                     point: CGPoint(x: 814, y: 98),
                     end: CGPoint(x: 459, y: 140),
                     side: .below,
                 ),
                 Callout(
                     label: "Pi, at work",
                     point: CGPoint(x: 406, y: 98),
                     end: CGPoint(x: 158, y: 220),
                     side: .below,
                 ),
                 Callout(
                     label: "Its tool calls, in one line",
                     point: CGPoint(x: 408, y: 548),
                     end: CGPoint(x: 230, y: 402),
                     side: .right,
                 ),
             ]),
        Page(title: "Plugins, built in and your own",
             text: "Browser, Git and File Explorer come with Ovvi. Make your own in TypeScript with New Plugin…, or "
                 + "ask your agent: it builds and opens them with the ovvi command.",
             shot: "welcome-plugins", focus: CGRect(x: 300, y: 46, width: 1140, height: 593),
             callouts: [
                 Callout(
                     label: "File Explorer",
                     point: CGPoint(x: 500, y: 98),
                     end: CGPoint(x: 168, y: 95),
                     side: .below,
                 ),
                 Callout(
                     label: "Your own plugin, in TypeScript",
                     point: CGPoint(x: 947, y: 64),
                     end: CGPoint(x: 580, y: 15),
                     side: .right,
                 ),
             ]),
        Page(title: "Any machine you can ssh to",
             text: "Add a machine, and its sessions open in a window of their own. Your SSH config works as it is, "
                 + "and work there keeps running while your Mac sleeps.",
             shot: "welcome-machines", focus: CGRect(x: 0, y: 0, width: 960, height: 500),
             callouts: [
                 Callout(label: "This Mac", point: CGPoint(x: 240, y: 57), end: CGPoint(x: 400, y: 57), side: .right),
                 Callout(
                     label: "Your machines",
                     point: CGPoint(x: 255, y: 105),
                     end: CGPoint(x: 400, y: 105),
                     side: .right,
                 ),
                 Callout(
                     label: "Add Machine…",
                     point: CGPoint(x: 255, y: 199),
                     end: CGPoint(x: 400, y: 199),
                     side: .right,
                 ),
             ]),
    ]

    static let herdr = Page(title: "One more thing: herdr",
                            text: "Ovvi keeps your terminals and agents in herdr's sessions on This Mac. Install it "
                                + "to begin.")
}

/// The shown look's shots (Pictures/welcome-<name>-<look>.heic), decoded off the main thread with ImageIO, each when
/// its page comes next: a 2880 × 1800 HEIC decoded on the main thread took 240 to 730 ms, and decoding them all at once
/// stalled the intro for 0.2 s every few frames.
@MainActor @Observable
final class TourShots {
    private(set) var images: [String: CGImage] = [:]
    /// The look of `images`; nil until the first is decoded.
    private(set) var dark: Bool?

    /// Decodes the shots this look lacks; another look's set stays in view until the first of this one's is in.
    func load(_ names: [String], dark: Bool) async {
        for name in names where self.dark != dark || images[name] == nil {
            let url = Bundle.main.url(forResource: "\(name)-\(dark ? "dark" : "light")", withExtension: "heic")
            let image = await Task.detached(priority: .utility) { Self.decode(url) }.value
            guard !Task.isCancelled, let image else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                if self.dark == dark {
                    images[name] = image
                } else {
                    (images, self.dark) = ([name: image], dark)
                }
            }
        }
    }

    private nonisolated static func decode(_ url: URL?) -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
