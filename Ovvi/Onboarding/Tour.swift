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
                 Callout(label: "Spaces", point: CGPoint(x: 20, y: 184), end: CGPoint(x: 130, y: 133), side: .left),
                 Callout(label: "Tabs", point: CGPoint(x: 576, y: 23), end: CGPoint(x: 416, y: 40), side: .above),
                 Callout(label: "Panes", point: CGPoint(x: 1152, y: 288), end: CGPoint(x: 830, y: 179),
                         side: .right),
                 Callout(label: "An agent", point: CGPoint(x: 576, y: 752), end: CGPoint(x: 416, y: 458),
                         side: .below),
             ]),
        Page(title: "Panes and splits",
             text: "Every card is a pane. Split one, and the new pane asks what it runs: a terminal, an agent, a "
                 + "browser, File Explorer or Git.",
             shot: "welcome-split", focus: CGRect(x: 480, y: 250, width: 960, height: 500),
             callouts: [
                 Callout(label: "Split Right", keys: ["⌘D"], point: CGPoint(x: 866, y: 330),
                         end: CGPoint(x: 300, y: 80), side: .left),
                 Callout(label: "Split Down", keys: ["⇧⌘D"], point: CGPoint(x: 1150, y: 469),
                         end: CGPoint(x: 670, y: 185), side: .above),
                 Callout(label: "It asks what it runs", keys: ["↩ Terminal"], point: CGPoint(x: 1010, y: 642),
                         end: CGPoint(x: 420, y: 392), side: .left),
             ]),
        Page(title: "Tabs and spaces",
             text: "A tab holds a set of panes. A space is one project, with its folder, its Git branch and its own "
                 + "tabs.",
             shot: "welcome-main", focus: CGRect(x: 0, y: 0, width: 960, height: 500),
             callouts: [
                 Callout(label: "Tabs", keys: ["⌘T", "⌘1–9"], point: CGPoint(x: 576, y: 23),
                         end: CGPoint(x: 640, y: 70), side: .right),
                 Callout(label: "Its Git branch", point: CGPoint(x: 60, y: 115), end: CGPoint(x: 360, y: 120),
                         side: .right),
                 Callout(label: "Spaces", keys: ["⌃⌘T", "⌃⌘1–9"], point: CGPoint(x: 150, y: 184),
                         end: CGPoint(x: 360, y: 184), side: .right),
             ]),
        Page(title: "Agents, as a terminal or a chat",
             text: "Run Claude Code, Codex, Pi or OpenCode in a pane. Read it as its terminal or as a chat: it is "
                 + "the same running agent.",
             shot: "welcome-main", focus: CGRect(x: 200, y: 40, width: 960, height: 500),
             callouts: [
                 Callout(label: "Chat or TUI", point: CGPoint(x: 814, y: 98), end: CGPoint(x: 700, y: 150),
                         side: .right),
                 Callout(label: "Orange: it needs you", point: CGPoint(x: 677, y: 98), end: CGPoint(x: 477, y: 150),
                         side: .below),
                 Callout(label: "Blue works · green is done", point: CGPoint(x: 253, y: 228),
                         end: CGPoint(x: 160, y: 300), side: .right),
             ]),
        Page(title: "Plugins, built in and your own",
             text: "Browser, Git and File Explorer come with Ovvi. Make your own in TypeScript with New Plugin…, or "
                 + "ask your agent: it drives them with ovvi.",
             shot: "welcome-review", focus: CGRect(x: 300, y: 46, width: 1140, height: 593),
             callouts: [
                 Callout(label: "File Explorer", point: CGPoint(x: 400, y: 250), end: CGPoint(x: 84, y: 280),
                         side: .below),
                 Callout(label: "Git", point: CGPoint(x: 1000, y: 263), end: CGPoint(x: 440, y: 230), side: .left),
                 Callout(label: "Your own plugin", point: CGPoint(x: 930, y: 567), end: CGPoint(x: 440, y: 440),
                         side: .left),
             ]),
        Page(title: "Any machine you can ssh to",
             text: "Add a machine, and its sessions open in a window of their own. Your SSH config works as it is, "
                 + "and work there keeps running while your Mac sleeps.",
             shot: "welcome-machines", focus: CGRect(x: 0, y: 0, width: 960, height: 500),
             callouts: [
                 Callout(label: "This Mac", point: CGPoint(x: 220, y: 57), end: CGPoint(x: 400, y: 57), side: .right),
                 Callout(label: "Your machines", point: CGPoint(x: 250, y: 105), end: CGPoint(x: 400, y: 105),
                         side: .right),
                 Callout(label: "Add Machine…", point: CGPoint(x: 250, y: 199), end: CGPoint(x: 400, y: 199),
                         side: .right),
             ]),
    ]

    static let herdr = Page(title: "One more thing: herdr",
                            text: "Ovvi keeps your terminals and agents in herdr's sessions on This Mac. Install it "
                                + "to begin.")
}
