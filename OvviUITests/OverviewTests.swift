import XCTest

extension OvviUITests {
    func testOverviewShowsEveryTabLiveAndOpensOne() async throws {
        step("The overview shows every tab live and opens one")
        relaunch(one, ["-recordLatency", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (closing, _) = try await newTab("closing", in: "w1")
        let made = sidebarsMade
        let block = "clear; for i in 1 2 3 4 5 6 7 8 9 10; do printf '\\033[107m%300s\\033[0m\\n' ''; done"
        try await send("\(block); echo block-$((6*7))\r", to: "w2:p1")
        try await waitFor("w2:p1") { $0.contains("\nblock-42") }

        app.typeKey("o", modifierFlags: [.command, .control])
        let overview = element("overview")
        XCTAssertTrue(overview.exists(within: 2))
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        XCTAssertFalse(element("tab.w1:t1").exists)
        element("overview.tab.\(closing)").hover()
        element("overview.tab.\(closing).close").click()
        XCTAssertTrue(element("overview.tab.\(closing)").vanishes(within: 3))
        try await expect("herdr closed \(closing)") { try await !Self.ids("tab", in: one).contains(closing) }
        for id in ["overview.workspace.w1", "overview.workspace.w2", "overview.tab.w1:t1", "overview.tab.w1:t2"] {
            XCTAssertTrue(element(id).exists(within: 2), id)
        }
        let first = element("overview.tab.w1:t1").frame, second = element("overview.tab.w1:t2").frame
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertEqual(second.minX - first.maxX, 16, accuracy: 1)
        expectOverviewChrome(first: first, second: second)
        XCTAssertEqual(element("overview.tab.w1:t1").stringValue, "selected")
        keepScreenshot("overview")
        // w2's row is below CI's window: the lazy rows make it as it scrolls in.
        let tile = element("overview.tab.w2:t1")
        scrollOverview(to: tile)
        XCTAssertLessThan(element("overview.workspace.w2").frame.maxY, tile.frame.minY)
        XCTAssertTrue(until(3) { mean(tile) > 60 }, "\(mean(tile))")

        tile.click()
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(element("sidebar").exists(within: 2))
        XCTAssertEqual(sidebarsMade, made)
        XCTAssertTrue(element("tab.w2:t1").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard("terminal.w2:p1"))
        try await expectPTYSize("w2:p1")

        element("titlebar.overview").click()
        XCTAssertTrue(overview.exists(within: 2))
        scrollOverview(to: tile)
        XCTAssertEqual(tile.stringValue, "selected")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(hasKeyboard("terminal.w2:p1"))

        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(overview.exists(within: 2))
        element("overview.close").click()
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(element("titlebar.overview").exists(within: 2))
        try await expectEveryTileLoadsInTurn()
    }

    private func expectEveryTileLoadsInTurn() async throws {
        step("The overview loads every tile in turn")
        let (loads, root) = try await createWorkspace("loads")
        let next = try await createTab(in: workspace(of: loads))
        // A 3 × 3 grid each: halving one pane eight times leaves cards too small to draw a row at CI's 1x.
        for pane in [root, next.pane] {
            let middle = try await split(pane), right = try await split(middle)
            for column in [pane, middle, right] {
                _ = try await split(split(column, "down"), "down")
            }
        }
        app.typeKey("o", modifierFlags: [.command, .control])
        scrollOverview(to: element("overview.tab.\(next.tab)"))
        // Recorded: CI's queries are too slow to see the loader.
        let tabs = [loads, next.tab], loaders = tabs.map { element("overview.tab.\($0).loading") }
        // One query each, not one per card: CI's queries are slow.
        XCTAssertTrue(until(30) { !loaders.contains { $0.exists } })
        let record = element("app.latency").stringValue
        XCTAssertTrue(tabs.allSatisfy { record.contains("loader \($0)") }, record)
    }

    func testOverviewTileIntoAnUnshownTabShowsItSteadily() async throws {
        relaunch(one, ["-recordMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("unshown", in: "w1")
        try await send("seq 1 40\r", to: pane)
        for round in ["unshown", "shown"] {
            app.typeKey("o", modifierFlags: [.command, .control])
            let overview = element("overview"), tile = element("overview.tab.\(tab)")
            XCTAssertTrue(tile.has(\.isHittable, true, within: 3))
            tile.click()
            XCTAssertTrue(overview.vanishes(within: 2))
            let card = element("pane.\(pane)")
            var values: [String] = []
            let end = Date.now + 1.5
            while Date.now < end {
                values.append(card.stringValue)
            }
            print("tile, \(round): \(values) host \(element("host.\(pane)").label)")
            let drawn = values.drop { round == "unshown" && $0.contains("loading") }
            XCTAssertFalse(drawn.isEmpty || drawn.contains { $0.contains("loading") }, "\(round): \(values)")
        }
    }

    private func expectOverviewChrome(first: CGRect, second: CGRect) {
        for id in ["titlebar.sidebar", "titlebar.machine", "titlebar.overview", "titlebar.palette",
                   "titlebar.new-tab"]
        {
            XCTAssertFalse(element(id).exists, id)
        }
        XCTAssertEqual(element("overview.title").stringValue, one)
        let canvas = element("overview").frame, title = element("overview.title").frame
        let side = first.minX - canvas.minX, room = canvas.width - 2 * side + 16
        let columns = (room / (second.width + 16)).rounded()
        XCTAssertEqual(side, max(48, canvas.width * 0.08), accuracy: 1)
        XCTAssertEqual(canvas.maxX - (first.minX + columns * second.width + (columns - 1) * 16), side, accuracy: 2)
        XCTAssertTrue((2 ... 4).contains(columns), "\(columns)")
        XCTAssertTrue(columns == 2 || second.width >= 340, "\(second)")
        XCTAssertTrue(columns == 4 || (columns + 1) * (340 + 16) > room, "\(columns) in \(room)")
        XCTAssertEqual(title.minY - canvas.minY, 40, accuracy: 2)
    }

    func testOverviewStepsBetweenSessions() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openSessionPanel()
        app.typeText(two)
        element("open-session.session.\(two)").click()
        XCTAssertTrue(until(3) { header == two })
        app.typeKey("[", modifierFlags: [.command, .option])
        XCTAssertTrue(until(3) { header == one })
        let (tab, pane) = try await createTab(in: "w1", session: two)
        closeAfter("tab", tab, in: two)
        let block = "clear; for i in 1 2 3 4 5 6 7 8 9 10; do printf '\\033[107m%300s\\033[0m\\n' ''; done"
        try await send("\(block)\r", to: pane, in: two)

        app.typeKey("o", modifierFlags: [.command, .control])
        let overview = element("overview"), window = app.windows.firstMatch, title = element("overview.title")
        XCTAssertTrue(title.has(\.stringValue, one, within: 2))
        // Both ways: the sign follows the natural scrolling setting.
        for delta in [-300.0, 300] {
            overview.scroll(byDeltaX: delta, deltaY: 0)
            let changed = until(0.5) { window.title.hasSuffix(" - \(two)") }
            XCTAssertFalse(changed, "a wheel of \(delta) changed the session")
        }
        app.typeKey("]", modifierFlags: [.command, .option])
        XCTAssertTrue(title.has(\.stringValue, two, within: 2))
        XCTAssertTrue(until(3) { window.title.hasSuffix(" - \(two)") }, window.title)
        keepScreenshot("overview of session two")
        let live = element("overview.tab.\(tab)"), dark = element("overview.tab.w1:t1")
        XCTAssertTrue(until(3) { mean(live) > mean(dark) + 30 }, "\(mean(live)) \(mean(dark))")
        dark.click()
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(until(3) { header == two })

        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(overview.exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(hasKeyboard("terminal.w1:p1"))
    }

    func testOverviewCostsAndLetsGoAfter() async throws {
        let (tabs, _) = try await newWorkspace("usage", tabs: 6)
        var panes: [String] = []
        for (index, tab) in tabs.enumerated() {
            var last = try await pane(of: tab)
            panes.append(last)
            // The second tab's one card is wide enough to tell its snapshot's size at 1x (below).
            for _ in 0 ..< (index + 2) % 3 {
                last = try await split(last)
                panes.append(last)
            }
        }
        for pane in panes.dropFirst(4) {
            try await waitForPrompt(pane)
            try await send("while :; do echo $RANDOM $RANDOM $RANDOM $RANDOM; sleep 0.1; done\r", to: pane)
        }
        let page = try await measure("page")
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").exists(within: 2))
        let card = element("overview.card.\(panes[3])")
        scrollOverview(to: element("overview.tab.\(tabs[1])"))
        XCTAssertTrue(until(10) { card.stringValue.hasPrefix("snapshot") }, card.stringValue)
        try await poll("the tiles' streams to end") { () async throws -> Int? in
            let count = try await helpers(measure("overview", seconds: 1))
            return count <= helpers(page) + 1 ? count : nil
        }
        let open = try await measure("overview")
        // Either way: the sign follows the natural scrolling setting.
        let last = element("overview.tab.\(tabs[5])")
        for delta in [-3000.0, 3000, -3000] where !(last.exists && last.isHittable) {
            element("overview").scroll(byDeltaX: 0, deltaY: delta)
            _ = last.has(\.isHittable, true, within: 1)
        }
        XCTAssertTrue(last.isHittable)
        keepScreenshot("overview of 6 tabs")
        let scrolled = try await measure("overview, scrolled")
        XCTAssertLessThanOrEqual(helpers(scrolled), helpers(page) + 16 + 2, scrolled)
        scrollOverview(to: element("overview.tab.\(tabs[1])"), step: 3000, steps: 1)
        XCTAssertTrue(card.exists)
        XCTAssertFalse(card.stringValue.hasPrefix("loading"), card.stringValue)
        XCTAssertTrue(card.stringValue.hasPrefix("snapshot"), card.stringValue)
        let width = Double(card.stringValue.split(separator: " ").last ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(width, card.frame.width * (NSScreen.main?.backingScaleFactor ?? 1) - 2,
                                    card.stringValue)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        try await poll("the overview's streams to end") { () async throws -> Int? in
            let count = try await helpers(measure("after", seconds: 1))
            return count == helpers(page) ? count : nil
        }
        _ = try await measure("after the overview")
        print("overview cost: page\n\(page)\nopen\n\(open)\nscrolled\n\(scrolled)")
    }

    func testOverviewOfManyTabsStaysBounded() async throws {
        executionTimeAllowance = 600
        addTeardownBlock { [eight] in _ = try? await Self.post("\(eight)/stress") }
        _ = try await Self.post("\(eight)/stress", Data("200 8 272 50".utf8))
        relaunch(eight, ["-recordMotion", "YES", "-recordLatency", "YES"])
        addTeardownBlock { @MainActor in self.note(self.element("app.latency").stringValue) }
        XCTAssertTrue(element("pane.w1:p1").exists(within: 120))
        try await Task.sleep(for: .seconds(5))
        let page = try await measure("page, 200 tabs", seconds: 5, session: eight)
        app.typeKey("o", modifierFlags: [.command, .control])
        let overview = element("overview")
        XCTAssertTrue(overview.exists(within: 5))
        _ = try await measure("overview, 200 tabs", seconds: 5, session: eight)
        let frame = overview.frame
        var sign = -1.0, most = 0
        for index in 0 ..< 20 {
            try await Self.post("\(one)/swipe", Data("\(frame.midX) \(frame.midY) \(30 * sign) 20 0 1".utf8))
            if index == 0, element("overview.title").isHittable {
                sign = -sign
            }
            most = try await max(most, streams(eight).count)
        }
        let sample = "\(eight)/sample"
        async let profile = Self.post(sample, Data("3".utf8))
        for _ in 0 ..< 4 {
            try await Self.post("\(one)/swipe", Data("\(frame.midX) \(frame.midY) \(-30 * sign) 20 0 1".utf8))
        }
        try await keep(String(decoding: profile, as: UTF8.self), as: "sample, overview scrolling")
        let scrolled = try await measure("overview, 200 tabs, scrolled", seconds: 5, session: eight)
        let snapshots = element("overview.snapshots").stringValue
        note("overview: most runs \(most), live and snapshots \(snapshots)")
        XCTAssertLessThanOrEqual(most, helpers(page) + 16 + 2, "\(most) runs")
        XCTAssertGreaterThan(Int(snapshots.split(separator: " ").last ?? "") ?? 0, 8, snapshots)
        // Bounded by the live cap, whatever the tab count: 16 full-window cards are about 1.1 GB on Retina.
        XCTAssertLessThan(footprint(scrolled), footprint(page) + 1600, scrolled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(overview.vanishes(within: 2))
    }

    func testOverviewShowsBrowserAndChatCards() async throws {
        let (tab, chat) = try await startChat()
        closeAfter("tab", tab)
        try await say("hello", in: chat)
        XCTAssertTrue(row(chat, "reply", "Echo: **hello**").exists(within: 5))
        let browser = try await split(chat)
        try await waitForPrompt(browser, in: one)
        let folder = "/tmp/ovvi-e2e-browser", keys = "<script>onkeydown = e => document.title = \\x27key \\x27 + e.key"
            + "</script>"
        try await send("mkdir -p \(folder) && printf '<title>Light</title>\(keys)' >\(folder)/light.html && printf "
            + "'<title>Dark</title><body style=\"background:black\">\(keys)' >\(folder)/dark.html && clear\r",
            to: browser)
        try await waitFor(browser, in: one) { !$0.contains("printf") }
        let iid = String(format: "e2e%03x", Int.random(in: 0 ..< 4096)), title = element("pane.\(browser).title")
        try await Self.call(one, "pane.rename", ["pane_id": browser,
                                                 "label": "ovvi:browser#\(iid) file://\(folder)/light.html"])
        XCTAssertTrue(title.has(\.stringValue, "Light", within: connect))
        // The web view's focus is not in the accessibility tree: the page's title shows it has the keyboard.
        element("browser.\(browser)").click()
        app.typeText("a")
        XCTAssertTrue(title.has(\.stringValue, "key a", within: 2))

        app.typeKey("o", modifierFlags: [.command, .control])
        let shot = element("overview.card.\(browser)")
        XCTAssertTrue(shot.has(\.stringValue, "browser", within: 3))
        XCTAssertEqual(element("overview.card.\(chat)").stringValue, "chat")
        // w2's row is below CI's window.
        scrollOverview(to: shot, whole: true)
        let light = mean(shot)
        keepScreenshot("overview, browser and chat")
        XCTAssertGreaterThan(light, 150, "the light page's picture")
        try await relabel(browser, "ovvi:browser#\(iid) file://\(folder)/dark.html")
        let tile = element("overview.tab.\(tab)")
        XCTAssertTrue(until(5) { tile.label.contains("Dark") }, tile.label)
        XCTAssertGreaterThan(mean(shot), 150, "the tile's picture")
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(element("palette.filter")))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("palette.filter").vanishes(within: 2))
        app.typeText("x")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        XCTAssertEqual(title.stringValue, "Dark")
        app.typeText("y")
        XCTAssertTrue(title.has(\.stringValue, "key y", within: 2))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, false, within: 3))
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(chat)").has(\.stringValue, "chat", within: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    var sidebarsMade: Int {
        element("app.latency").stringValue.components(separatedBy: "sidebar made").count
    }

    func footprint(_ usage: String) -> Int {
        usage.firstMatch(of: /Footprint: (\d+) MB/).flatMap { Int($0.1) } ?? .max
    }

    func scrollOverview(to target: XCUIElement, whole: Bool = false, step: Double = 300, steps: Int = 10) {
        let shown = {
            target.exists && target.isHittable && (!whole || self.element("overview").frame.contains(target.frame))
        }
        for delta in [-step, step, -step] {
            for _ in 0 ..< steps where !shown() {
                element("overview").scroll(byDeltaX: 0, deltaY: delta)
            }
        }
    }

    func mean(_ element: XCUIElement) -> Int {
        let brightness = Self.brightness(element.screenshot().image)
        return brightness.isEmpty ? 0 : brightness.reduce(0, +) / brightness.count
    }
}
