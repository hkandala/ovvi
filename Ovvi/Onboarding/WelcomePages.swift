import SwiftUI

/// One picture of a page: a full-window capture of Ovvi (`scripts/welcome-scene.sh`,
/// `welcome-<picture>-dark|light.heic`),
/// the part the camera frames, and the ring and its label on the part the words talk about, in the window's points.
struct WelcomeShot {
    let picture: String
    let focus: CGRect
    let ring: CGRect
    let label: String
}

/// A page of the welcome: a picture on top (a page with more shots steps through them by itself), words below.
struct WelcomePage {
    let title: String
    let words: (Look) -> Text
    let shots: [WelcomeShot]

    /// The rects are in the 1280 × 800 pt window of the pictures.
    static let all = [
        WelcomePage(title: "Welcome to Ovvi", words: { _ in
            Text("""
            Your terminals, agents and tools, side by side in one Mac window. They run in sessions that keep going \
            when you close the window or quit Ovvi, and on another machine even while your Mac sleeps. Come back to \
            find it all as you left it.
            """)
        }, shots: [WelcomeShot(picture: "overview", focus: CGRect(x: 0, y: 0, width: 1150, height: 505),
                               ring: CGRect(x: 8, y: 82, width: 283, height: 420), label: "Still running")]),
        WelcomePage(title: "Panes and splits", words: { _ in
            Text("""
            A new pane asks what it runs: a terminal, an agent, a browser, File Explorer or Git. \(key("⌘D")) splits \
            it to the right and \(key("⇧⌘D")) splits it down, and each new pane asks again. Drag a divider to resize.
            """)
        }, shots: [
            WelcomeShot(picture: "splitdown", focus: CGRect(x: 560, y: 330, width: 720, height: 470),
                        ring: CGRect(x: 874, y: 515, width: 314, height: 192), label: "New pane"),
            WelcomeShot(picture: "server", focus: CGRect(x: 360, y: 40, width: 920, height: 404),
                        ring: CGRect(x: 789, y: 45, width: 484, height: 748), label: "⌘D"),
            WelcomeShot(picture: "splitdown", focus: CGRect(x: 360, y: 396, width: 920, height: 404),
                        ring: CGRect(x: 790, y: 422, width: 484, height: 371), label: "⇧⌘D"),
        ]),
        WelcomePage(title: "Tabs", words: { _ in
            Text("""
            A tab holds a set of panes. Its capsule in the tab bar shows the programs running there and whether an \
            agent needs you. \(key("⌘T")) opens a tab, \
            \(key("⌘1"))–\(key("⌘9")) jumps to one, and \(key("⌃⌘O")) shows every tab at once.
            """)
        }, shots: [WelcomeShot(picture: "overview", focus: CGRect(x: 280, y: 0, width: 1000, height: 440),
                               ring: CGRect(x: 299, y: 6, width: 866, height: 34), label: "⌘T")]),
        WelcomePage(title: "Spaces", words: { _ in
            Text("""
            A space is one project: its folder, its Git branch and its own tabs. The sidebar lists your spaces and \
            the agents at work in each. \(key("⌃⌘T")) makes a space and \(key("⌃⌘1"))–\(key("⌃⌘9")) jumps to one.
            """)
        }, shots: [WelcomeShot(picture: "docs", focus: CGRect(x: 0, y: 76, width: 300, height: 430),
                               ring: CGRect(x: 8, y: 82, width: 283, height: 420), label: "5 spaces")]),
        WelcomePage(title: "Agents, as a terminal or a chat", words: { look in
            Text("""
            Start Claude Code, Codex, Pi or OpenCode in a new pane. Switch it to Chat to answer it as messages, or \
            back to its terminal (TUI): it is the same running agent. \(Text("Orange").foregroundStyle(look.needsYou)) \
            needs you, \(Text("blue").foregroundStyle(look.working)) works, \
            \(Text("green").foregroundStyle(look.finished)) is done.
            """)
        }, shots: [WelcomeShot(picture: "chat", focus: CGRect(x: 300, y: 40, width: 920, height: 404),
                               ring: CGRect(x: 691, y: 84, width: 85, height: 28), label: "Chat or TUI")]),
        WelcomePage(title: "Plugins, built in and your own", words: { _ in
            Text("""
            Browser, Git and File Explorer come with Ovvi and open beside your agents. Your own plugins are small \
            TypeScript packages: start one with New Plugin… in Settings, or ask your agent, which builds, opens and \
            reloads them with the \(Text("ovvi").font(.system(size: 13, design: .monospaced))) command.
            """)
        }, shots: [
            WelcomeShot(picture: "overview", focus: CGRect(x: 360, y: 30, width: 920, height: 404),
                        ring: CGRect(x: 789, y: 45, width: 484, height: 748), label: "Browser"),
            WelcomeShot(picture: "chat", focus: CGRect(x: 360, y: 120, width: 920, height: 404),
                        ring: CGRect(x: 789, y: 45, width: 484, height: 748), label: "Git"),
            WelcomeShot(picture: "docs", focus: CGRect(x: 360, y: 60, width: 920, height: 404),
                        ring: CGRect(x: 789, y: 45, width: 484, height: 748), label: "File Explorer"),
        ]),
        WelcomePage(title: "Any machine you can ssh to", words: { _ in
            Text("""
            Add a machine, and its sessions open in a window of their own, with the same panes, agents and plugins. \
            Your SSH config and keys work as they are, and work there keeps running while your Mac sleeps.
            """)
        }, shots: [WelcomeShot(picture: "machines", focus: CGRect(x: 0, y: 0, width: 920, height: 404),
                               ring: CGRect(x: 120, y: 38, width: 146, height: 204), label: "Your machines")]),
    ]

    /// A key as a keycap in the words: thin spaces pad its cap (`KeycapText`).
    private static func key(_ key: String) -> Text {
        Text("\u{2009}\(key)\u{2009}").font(.system(size: 13, weight: .medium)).customAttribute(WelcomeKey())
    }
}

/// Marks a key in a page's words.
struct WelcomeKey: TextAttribute {}

/// Draws a cap behind each key of the words.
struct KeycapText: TextRenderer {
    let fill: Color
    let rim: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[WelcomeKey.self] != nil {
                    let cap = RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .path(in: run.typographicBounds.rect.insetBy(dx: 0, dy: -1.5))
                    context.fill(cap, with: .color(fill))
                    context.stroke(cap, with: .color(rim), lineWidth: 0.5)
                }
                context.draw(run)
            }
        }
    }
}
