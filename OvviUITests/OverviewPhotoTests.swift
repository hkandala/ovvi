import XCTest

extension OvviUITests {
    /// A chat, a browser and a plugin card never drawn in this run get their pictures in the overview's tile: each
    /// draws live in it, one at a time, until it has one.
    func testOverviewPicturesCardsNeverDrawn() async throws {
        // Dark: the light page's picture is told from the card's fill.
        relaunch(one, ["-agentView", "chat", "-appearance", "dark"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, chat) = try await createTab(in: "w2")
        closeAfter("tab", tab)
        try await waitForPrompt(chat)
        let folder = "/tmp/ovvi-e2e-unseen", standIn = Self.scripts.appending(path: "claude-stand-in.py").path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: folder) }
        try await send("mkdir -p \(folder) && printf '<title>Light</title><body style=\"background:white\">' "
            + ">\(folder)/light.html && printf '# Unseen\\n' >\(folder)/notes.md && "
            + "function claude { python3 '\(standIn)' \"$@\"; } && clear && claude\r", to: chat)
        try await waitFor(chat, toShow: "Claude Code stand-in")
        try await Self.call(one, "agent.prompt", ["target": chat, "text": "hello"])
        try await waitFor(chat, toShow: "Echo")
        let browser = try await split(chat), plugin = try await split(browser, "down")
        try await relabel(browser, "ovvi:browser#e2eunb file://\(folder)/light.html")
        try await relabel(plugin, "ovvi:explorer#e2eunp /private\(folder)/notes.md")
        XCTAssertFalse(element("tab.\(tab)").exists, "w2's tabs never show")

        let before = try await measure("before the overview", seconds: 1)
        app.typeKey("o", modifierFlags: [.command, .control])
        let tile = element("overview.tab.\(tab)")
        XCTAssertTrue(tile.exists(within: 3))
        scrollOverview(to: tile, whole: true)
        // Failing on the old code: each kept its symbol.
        for (pane, picture) in [(chat, "chat"), (browser, "browser"), (plugin, "explorer")] {
            XCTAssertTrue(element("overview.card.\(pane)").has(\.stringValue, picture, within: 30),
                          "\(picture): \(element("overview.card.\(pane)").stringValue)")
        }
        keepScreenshot("overview, cards never drawn")
        XCTAssertGreaterThan(mean(element("overview.card.\(browser)")), 150, "the light page's picture")
        // The web cards made for their pictures go: WebKit's shared processes may stay (and one it starts ahead).
        try await poll("the photos' web views to go") { () async throws -> Int? in
            let count = try await webPages(measure("overview", seconds: 1))
            return count <= webPages(before) + 3 ? count : nil
        }
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
    }

    func webPages(_ usage: String) -> Int {
        usage.split(separator: "\n").first { $0.hasPrefix("webkit ") }.flatMap { Int($0.split(separator: " ")[1]) }
            ?? .max
    }
}
