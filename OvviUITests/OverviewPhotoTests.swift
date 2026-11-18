import XCTest

extension OvviUITests {
    /// A chat, a browser and a plugin card never drawn in this run get their pictures in the overview's tile: each
    /// draws live in it, one at a time, under a loader until it has one.
    func testOverviewPicturesCardsNeverDrawn() async throws {
        executionTimeAllowance = 360
        let (tab, panes) = try await cardsNeverDrawn(), (chat, browser, plugin) = (panes[0], panes[1], panes[2])

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
        // Recorded: XCUITest's queries are too slow to see a loader.
        let loaders = element("app.latency").stringValue
        for pane in [chat, browser, plugin] {
            XCTAssertTrue(loaders.contains("tile loader \(pane)"), "no loader on \(pane): \(loaders)")
        }
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

    /// Scrolled down, up and down again, the overview draws no card again once its picture showed.
    func testOverviewKeepsItsPicturesWhileItScrolls() async throws {
        executionTimeAllowance = 360
        let (tab, panes) = try await cardsNeverDrawn(), (chat, browser, plugin) = (panes[0], panes[1], panes[2])
        let below = try await explorersBelow("/tmp/ovvi-e2e-unseen")
        app.typeKey("o", modifierFlags: [.command, .control])
        let tile = element("overview.tab.\(tab)")
        XCTAssertTrue(tile.exists(within: 3))
        scrollOverview(to: tile, whole: true)
        let first = [(chat, "chat"), (browser, "browser"), (plugin, "explorer")]
        for (pane, picture) in first {
            XCTAssertTrue(element("overview.card.\(pane)").has(\.stringValue, picture, within: 30),
                          "\(picture): \(element("overview.card.\(pane)").stringValue)")
        }
        expectPicturesKept(first, below: below, tile: tile)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
    }

    /// A chat's tab in w2 with a browser and a File Explorer split in (in that order), after a relaunch: no card of it
    /// drawn in this run. Dark: the light page's picture is told from the card's fill.
    private func cardsNeverDrawn() async throws -> (tab: String, panes: [String]) {
        let (tab, chat) = try await startChat(["-appearance", "dark"])
        addTeardownBlock { @MainActor in self.keep(self.element("app.latency").stringValue, as: "latency") }
        try await say("hello", in: chat)
        XCTAssertTrue(row(chat, "reply", "Echo: **hello**").exists(within: 5))
        // The pictures live in memory: after a relaunch no card of the tab was drawn (herdr's focused space shows).
        relaunch(one, ["-appearance", "dark", "-recordLatency", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        XCTAssertFalse(element("tab.\(tab)").exists, "w2's tabs never show")
        let folder = "/tmp/ovvi-e2e-unseen", browser = try await split(chat)
        try await waitForPrompt(browser)
        try await send("mkdir -p \(folder) && printf '<title>Light</title><body style=\"background:white\">' "
            + ">\(folder)/light.html && for i in 0 1 2 3 4 5 6 7 8 9; do printf '# Unseen\\n' >\(folder)/notes$i.md; "
            + "done && clear\r", to: browser)
        try await waitFor(browser) { !$0.contains("printf") }
        sendAfter("rm -rf \(folder)\r", to: browser)
        let plugin = try await split(browser, "down")
        try await relabel(browser, "ovvi:browser#e2eunb file://\(folder)/light.html")
        try await relabel(plugin, "ovvi:explorer#e2eunp /private\(folder)/notes0.md")
        return (tab, [chat, browser, plugin])
    }

    /// Three rows of explorer cards below, so that the first tab's tile scrolls out of view.
    private func explorersBelow(_ folder: String) async throws -> [String] {
        let (first, root) = try await createWorkspace("below")
        var below = [root]
        for _ in 1 ..< 9 {
            try await below.append(createTab(in: workspace(of: first)).pane)
        }
        for (index, pane) in below.enumerated() {
            try await relabel(pane, "ovvi:explorer#e2eub\(index) /private\(folder)/notes\(index + 1).md")
        }
        return below
    }

    private func expectPicturesKept(_ first: [(String, String)], below: [String], tile: XCUIElement) {
        step("Scrolled down, up and down again, each card keeps its picture")
        for pane in below {
            let card = element("overview.card.\(pane)")
            scrollOverview(to: card, whole: true, step: 200, steps: 15)
            XCTAssertTrue(card.has(\.stringValue, "explorer", within: 30), "\(pane): \(card.stringValue)")
        }
        XCTAssertFalse(tile.exists && tile.isHittable, "the first tab's tile stayed in view")
        // A photo cut short (its tile scrolled out, a chat not whole in view) starts again: count only from here.
        let made = (first.map(\.0) + below).map { photos($0) }
        for (pane, picture) in first {
            let card = element("overview.card.\(pane)")
            scrollOverview(to: card, whole: true, step: 200, steps: 15)
            XCTAssertEqual(card.stringValue, picture, pane)
        }
        for pane in below {
            let card = element("overview.card.\(pane)")
            scrollOverview(to: card, whole: true, step: 200, steps: 15)
            XCTAssertEqual(card.stringValue, "explorer", pane)
        }
        XCTAssertEqual((first.map(\.0) + below).map { photos($0) }, made, "a card with its picture drawn again")
    }

    /// Recorded as each starts.
    private func photos(_ pane: String) -> Int {
        element("app.latency").stringValue.components(separatedBy: "; ").count { $0 == "photo \(pane)" }
    }

    /// Past the pictures' bound the least recently shown goes, and its tile draws its card again once it shows.
    func testOverviewDrawsAgainAPictureLetGo() async throws {
        executionTimeAllowance = 400
        // About seven pictures (1.2–1.5 MB each on CI and in the VM), more than the tiles in view.
        relaunch(one, ["-recordLatency", "YES", "-pictureBytes", "10000000"])
        addTeardownBlock { @MainActor in self.keep(self.element("app.latency").stringValue, as: "latency") }
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let folder = "/tmp/ovvi-e2e-let-go"
        try await send("mkdir -p \(folder) && for i in $(seq 0 13); do printf '# Notes\\n' >\(folder)/notes$i.md; "
            + "done && clear\r", to: "w2:p1")
        try await waitFor("w2:p1") { !$0.contains("printf") }
        sendAfter("rm -rf \(folder)\r", to: "w2:p1")
        let (first, root) = try await createWorkspace("let go")
        var panes = [root]
        for _ in 1 ..< 14 {
            try await panes.append(createTab(in: workspace(of: first)).pane)
        }
        for (index, pane) in panes.enumerated() {
            // An iid of exactly 6 characters.
            try await relabel(pane, "ovvi:explorer#e2el\(index / 10)\(index % 10) /private\(folder)/notes\(index).md")
        }
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").exists(within: 3))
        for pane in panes + [panes[0]] {
            let card = element("overview.card.\(pane)")
            scrollOverview(to: card, whole: true, step: 100, steps: 30)
            XCTAssertTrue(card.has(\.stringValue, "explorer", within: 30), "\(pane): \(card.stringValue)")
        }
        XCTAssertGreaterThan(photos(panes[0]), 1, "the first card kept its picture past the bound")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// A while after the overview closes (5 minutes, 8 s here), the pictures only its tiles show go: the terminals'
    /// snapshots and the chats' pictures. A web card's own picture stays. Opened again in time, it keeps them.
    func testOverviewLetsGoOfItsTilePicturesAfterItCloses() async throws {
        executionTimeAllowance = 300
        // w2's terminal leaves view for the chat's tab: its snapshot.
        let (chatTab, chat) = try await startChat(["-recordLatency", "YES", "-tilePictureSeconds", "8"])
        addTeardownBlock { @MainActor in self.keep(self.element("app.latency").stringValue, as: "latency") }
        try await say("hello", in: chat)
        XCTAssertTrue(row(chat, "reply", "Echo: **hello**").exists(within: 5))
        let folder = "/tmp/ovvi-e2e-tile-pictures"
        try await send("mkdir -p \(folder) && printf '<p>ovvi-kept-page</p>' >\(folder)/page.html && clear\r",
                       to: "w2:p1")
        try await waitFor("w2:p1") { !$0.contains("printf") }
        sendAfter("rm -rf \(folder)\r", to: "w2:p1")
        // The chat leaves view for the browser's tab: its picture.
        let (tab, browser) = try await newTab("page")
        try await relabel(browser, "ovvi:browser#e2etpb file://\(folder)/page.html")
        element("tab.\(tab)").click()
        XCTAssertTrue(pageText("ovvi-kept-page").exists(within: 10))
        let cards = [chat: "chat", browser: "browser", "w2:p1": "snapshot"].map { pane, picture in
            (element("overview.card.\(pane)"), picture)
        }
        for opening in ["first", "again in time"] {
            step("Opened \(opening), each card shows its picture")
            app.typeKey("o", modifierFlags: [.command, .control])
            for (card, picture) in cards {
                scrollOverview(to: card, whole: true)
                XCTAssertTrue(until(10) { card.stringValue.hasPrefix(picture) }, "\(picture): \(card.stringValue)")
            }
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(element("overview").vanishes(within: 2))
        }
        XCTAssertEqual(photos(chat), 0)
        XCTAssertFalse(element("app.latency").stringValue.contains("overview let go"), "let go while opened in time")

        step("Let go: the chat is drawn again for its picture, the page keeps its own")
        let latency = element("app.latency")
        XCTAssertTrue(until(30) { latency.stringValue.contains("overview let go") }, latency.stringValue)
        let counts = latency.stringValue.firstMatch(of: /overview let go (\d+) (\d+)/).map { (Int($0.1), Int($0.2)) }
        XCTAssertGreaterThan(counts?.0 ?? 0, 0, "snapshots let go: \(latency.stringValue)")
        XCTAssertEqual(counts?.1, 1, "chat pictures let go: \(latency.stringValue)")
        app.typeKey("o", modifierFlags: [.command, .control])
        // A chat's picture waits until its whole tile is in the window.
        scrollOverview(to: element("overview.tab.\(chatTab)"), whole: true)
        XCTAssertTrue(element("overview.card.\(chat)").has(\.stringValue, "chat", within: 30))
        XCTAssertEqual(photos(chat), 1)
        XCTAssertEqual(element("overview.card.\(browser)").stringValue, "browser")
        XCTAssertEqual(photos(browser), 0)
        app.typeKey(.escape, modifierFlags: [])
    }
}
