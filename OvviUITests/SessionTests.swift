import XCTest

extension OvviUITests {
    func testOpenSessionListsSessionsAndOpensAPage() {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openSessionPanel()
        expectRow("open-session.session.\(two)", under: "Running", above: "Stopped")
        expectRow("open-session.session.\(three)", under: "Stopped", above: "Open in this window")
        expectRow("open-session.open.\(one)", under: "Open in this window", above: nil)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'open-session.new.'"))
            .firstMatch.isSelected)
        app.typeText(String(one.dropLast()))
        XCTAssertTrue(element("open-session.new.\(one.dropLast())").exists(within: 2))
        keepScreenshot("open session")
        element("open-session.session.\(two)").click()

        XCTAssertTrue(element("open-session.filter").vanishes(within: 2))
        XCTAssertTrue(until(3) { header == two })
        XCTAssertTrue(pageList().contains(one))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'workspace.w1' AND label == 'gamma'"))
            .firstMatch.exists(within: connect))
        keepScreenshot("two pages")
        showPage(one)
        XCTAssertTrue(until(3) { header == one })
        XCTAssertTrue(element("workspace.w2").exists(within: 2))

        showPage(two)
        XCTAssertTrue(until(3) { header == two })
        app.typeKey("s", modifierFlags: [.command, .control])
        let button = element("titlebar.workspace")
        XCTAssertTrue(button.exists(within: 2))
        button.click()
        XCTAssertTrue(element("workspaces.\(two).w1").exists(within: 2))
        element("workspaces.\(one).w2").click()
        XCTAssertTrue(until(3) { button.value as? String == "\(one) | beta" })
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 2))
        XCTAssertTrue(until(3) { header == one })

        showPage(two)
        XCTAssertTrue(until(3) { header == two })
        openSessionPanel()
        app.typeText(one)
        XCTAssertTrue(element("open-session.open.\(one)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(until(3) { header == one })
        XCTAssertTrue(pageList().contains(two))
    }

    func testOptionCommandTCreatesASessionAsANewPage() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        app.typeKey("t", modifierFlags: [.command, .option])
        XCTAssertTrue(hasKeyboard("open-session.filter"))
        app.typeText(four)
        XCTAssertTrue(element("open-session.new.\(four)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(until(connect) { header == four })
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let snapshot = try await Self.snapshot(four)
        XCTAssertEqual((snapshot["workspaces"] as? [Any])?.count, 1)
        XCTAssertTrue(pageList().contains(one))
    }

    func testOpenSessionStartsAStoppedSession() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        try await running(five)
        try await Self.post("\(five)/stop")
        openSessionPanel()
        // Other stopped sessions on this Mac may push its row out of the list's view.
        app.typeText(five)
        let row = element("open-session.session.\(five)")
        XCTAssertTrue(row.has(\.isSelected, true, within: 2))
        expectRow(row.identifier, under: "Stopped", above: nil)
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(until(connect) { header == five })
        try await Self.snapshot(five)
    }

    func testOpenSessionStopsAndDeletesASession() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openSessionPanel()
        app.typeText(seven)
        let row = element("open-session.session.\(seven)")
        XCTAssertTrue(row.has(\.isSelected, true, within: 2))
        expectRow(row.identifier, under: "Running", above: nil)
        XCTAssertFalse(element("\(row.identifier).delete").exists)
        XCTAssertTrue(isRed(element("\(row.identifier).stop")))
        keepScreenshot("stop on the lit row")
        element("\(row.identifier).stop").click()
        let stop = app.sheets.buttons["Stop Session"]
        XCTAssertTrue(stop.exists(within: 2))
        XCTAssertTrue(until(2) { isRed(stop) })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("\(row.identifier).delete").exists(within: 10))
        expectRow(row.identifier, under: "Stopped", above: nil)
        let stopped = try await answer(seven)
        XCTAssertNil(stopped)

        element("\(row.identifier).delete").click()
        let confirm = app.sheets.buttons["Delete Session"]
        XCTAssertTrue(confirm.exists(within: 2))
        keepScreenshot("delete asks")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(row.vanishes(within: 10))
        XCTAssertTrue(element("open-session.new.\(seven)").exists(within: 2))
    }

    func testOpenSessionDetachesAnOpenSession() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openSessionPanel()
        app.typeText(one)
        let last = element("open-session.open.\(one)")
        XCTAssertTrue(last.has(\.isSelected, true, within: 2))
        XCTAssertFalse(element("\(last.identifier).detach").exists)
        app.typeKey("a", modifierFlags: .command)
        app.typeText(two)
        element("open-session.session.\(two)").click()
        XCTAssertTrue(until(3) { header == two })

        openSessionPanel()
        app.typeText(two)
        let row = element("open-session.open.\(two)")
        XCTAssertTrue(row.has(\.isSelected, true, within: 2))
        let detach = element("\(row.identifier).detach")
        XCTAssertTrue(detach.exists)
        XCTAssertFalse(isRed(detach))
        keepScreenshot("detach on the lit open row")
        detach.click()
        XCTAssertTrue(until(3) { !pageList().contains(two) })
        XCTAssertTrue(until(3) { header == one })
        XCTAssertTrue(element("open-session.session.\(two)").exists(within: 2))
        expectRow("open-session.session.\(two)", under: "Running", above: nil)
        try await Self.snapshot(two)
    }

    func testOpenedSessionsGoLast() async throws {
        try await running(five)
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        showPage(one)
        XCTAssertTrue(until(3) { header == one })
        openPage(five)
        XCTAssertEqual(pageList(), [one, two, five])
    }

    func testDetachSessionKeepsTheSessionRunning() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        closePage(two)
        XCTAssertTrue(until(3) { header == one })
        XCTAssertEqual(pageList(), [one])
        try await Self.snapshot(two)

        // At its center: the page that slid away may leave it unhittable for a moment.
        element("sidebar.header").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        XCTAssertTrue(app.windows.firstMatch.menuItems["Detach Session"].exists(within: 2))
        XCTAssertFalse(app.windows.firstMatch.menuItems["Detach Session"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testKeysGoToTheSessionShown() async throws {
        let mine = try await shown(Self.snapshot(one)).pane, theirs = try await shown(Self.snapshot(two)).pane
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        // Not by the terminal's id: both sessions have it.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'workspace.w1' AND label == 'gamma'"))
            .firstMatch.exists(within: connect))
        try await type("opened", into: theirs, of: two)
        try await swipe(element("sidebar"), until: element("sidebar.header"), \.stringValue, one)
        try await type("back", into: mine, of: one)
        app.typeKey("]", modifierFlags: [.command, .option])
        XCTAssertTrue(until(3) { header == two })
        try await type("next", into: theirs, of: two)
    }

    private func type(_ word: String, into pane: String, of session: String) async throws {
        app.typeText("echo \(word)-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await expect("\(word)-42 in \(session)'s \(pane)") {
            try await read(pane, in: session).contains("\n\(word)-42")
        }
    }

    private func expectRow(_ row: String, under section: String, above next: String?) {
        let frame = element(row).frame
        XCTAssertGreaterThan(frame.minY, element("open-session.section.\(section)").frame.maxY, row)
        if let next {
            XCTAssertLessThan(frame.maxY, element("open-session.section.\(next)").frame.minY, row)
        }
    }

    func openPage(_ session: String, in window: XCUIElement? = nil) {
        openSessionPanel(in: window)
        element("open-session.session.\(session)", in: window).click()
        XCTAssertTrue(until(connect) { pageList(in: window).contains(session) })
    }

    /// In the window, not the menu bar's File ▸ Detach Session.
    func closePage(_ session: String, in window: XCUIElement? = nil) {
        showPage(session, in: window)
        XCTAssertTrue(element("sidebar.header", in: window).has(\.stringValue, session, within: 3))
        // At its center: the page that slid away may leave it unhittable for a moment.
        element("sidebar.header", in: window).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        (window ?? app.windows.firstMatch).menuItems["Detach Session"].click()
        XCTAssertTrue(until(3) { !pageList(in: window).contains(session) })
    }

    func pageList(in window: XCUIElement? = nil) -> [String] {
        element("sidebar.sessions", in: window).stringValue.split(separator: " ").map(String.init)
    }

    func showPage(_ session: String, in window: XCUIElement? = nil) {
        if let window {
            raise(window)
        }
        guard let index = pageList(in: window).firstIndex(of: session) else {
            return XCTFail("no page \(session) in \(pageList(in: window))")
        }
        app.typeKey("\(index + 1)", modifierFlags: [.command, .option])
    }

    @discardableResult
    func openSessionPanel(in window: XCUIElement? = nil) -> XCUIElement {
        element("sidebar.open-session", in: window).click()
        let filter = element("open-session.filter", in: window)
        XCTAssertTrue(hasKeyboard(filter))
        return filter
    }

    /// By its pixels: XCUITest reads no color. An alert's fades in: wait.
    func isRed(_ element: XCUIElement) -> Bool {
        let pixels = Self.pixels(element.screenshot().image)
        let count = max(pixels.count / 4, 1)
        let mean = (0 ..< 3).map { channel in
            stride(from: channel, to: pixels.count, by: 4).reduce(0) { $0 + Int(pixels[$1]) } / count
        }
        return mean[0] > mean[1] + 30 && mean[0] > mean[2] + 30
    }

    var header: String? {
        element("sidebar.header").value as? String
    }

    func testAnotherSessionsAgentCountsInTheDockBadgeOnly() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        openPage(two)
        showPage(one)
        XCTAssertTrue(element("workspace.w2").exists(within: 2))

        addTeardownBlock { [two] in
            _ = try? await Self.call(two, "pane.release_agent", ["pane_id": "w1:p1", "source": "ovvi-e2e",
                                                                 "agent": "codex"])
        }
        try await report("w1:p1", "blocked", session: two)
        try await expect("the badge to count the other page") { element("app.badge").value as? String == "1" }
        XCTAssertFalse(element("workspace.w1").stringValue.contains("needs you"))
        showPage(two)
        XCTAssertEqual(element("sidebar.header").value as? String, two)
        try await waitForValue("workspace.w1", containing: "needs you")
        unfold("w1")
        try await waitForValue("agent.w1:p1", containing: "Needs you")
    }
}
