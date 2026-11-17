import XCTest

extension OvviUITests {
    /// A chat, a browser and a plugin card never drawn in this run get their pictures in the overview's tile: each
    /// draws live in it, one at a time, until it has one.
    func testOverviewPicturesCardsNeverDrawn() async throws {
        // Dark: the light page's picture is told from the card's fill.
        let (tab, chat) = try await startChat(["-appearance", "dark"])
        try await say("hello", in: chat)
        XCTAssertTrue(row(chat, "reply", "Echo: **hello**").exists(within: 5))
        // The pictures live in memory: after a relaunch no card of the tab was drawn (herdr's focused space shows).
        relaunch(one, ["-appearance", "dark"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        XCTAssertFalse(element("tab.\(tab)").exists, "w2's tabs never show")
        let folder = "/tmp/ovvi-e2e-unseen", browser = try await split(chat)
        try await waitForPrompt(browser)
        try await send("mkdir -p \(folder) && printf '<title>Light</title><body style=\"background:white\">' "
            + ">\(folder)/light.html && printf '# Unseen\\n' >\(folder)/notes.md && clear\r", to: browser)
        try await waitFor(browser) { !$0.contains("printf") }
        sendAfter("rm -rf \(folder)\r", to: browser)
        let plugin = try await split(browser, "down")
        try await relabel(browser, "ovvi:browser#e2eunb file://\(folder)/light.html")
        try await relabel(plugin, "ovvi:explorer#e2eunp /private\(folder)/notes.md")

        // Once the two warm views' (`Browser.prewarm`) page processes run. Page processes only: CI's virtual Mac
        // runs WebKit with no GPU process.
        let before = try await poll("the warm views' page processes") { () async throws -> Int? in
            let count = try await web("web-pids", "").count
            return count >= 2 ? count : nil
        }
        app.typeKey("o", modifierFlags: [.command, .control])
        let tile = element("overview.tab.\(tab)")
        XCTAssertTrue(tile.exists(within: 3))
        scrollOverview(to: tile, whole: true)
        for (pane, picture) in [(chat, "chat"), (browser, "browser"), (plugin, "explorer")] {
            XCTAssertTrue(element("overview.card.\(pane)").has(\.stringValue, picture, within: 30),
                          "\(picture): \(element("overview.card.\(pane)").stringValue)")
        }
        keepScreenshot("overview, cards never drawn")
        XCTAssertGreaterThan(mean(element("overview.card.\(browser)")), 150, "the light page's picture")
        // The chat's rows, light on the dark card: a blank picture has no light pixel.
        let light = Self.brightness(element("overview.card.\(chat)").screenshot().image).count { $0 > 150 }
        XCTAssertGreaterThan(light, 20, "the chat's picture")
        // The web cards made for their pictures go with their page processes (a warm view taken starts another).
        try await poll("the photos' web views to go (to \(before))", times: 300) { () async throws -> Int? in
            let count = try await web("web-pids", "").count
            return count <= before ? count : nil
        }
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
    }
}
