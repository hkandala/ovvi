import XCTest

extension OvviUITests {
    func testSecondPagesServerStopsAndStartsAloneOnItsPage() async throws {
        let (workspace, pane) = try await shown(running(five))
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openPage(five)
        XCTAssertTrue(element("workspace.\(workspace)").exists(within: connect))

        try await Self.post("\(five)/stop")
        let start = element("detail.start")
        XCTAssertTrue(start.exists(within: 10))
        showPage(one)
        XCTAssertTrue(element("terminal.w1:p1").exists(within: 3))
        XCTAssertFalse(start.exists)
        try await expect("one's three streams") { try await streams(one).count == 3 }

        showPage(five)
        XCTAssertTrue(start.exists(within: 3))
        start.click()
        XCTAssertTrue(element("terminal.\(pane)").exists(within: connect))
        XCTAssertFalse(start.exists)
        try await Self.snapshot(five)
    }

    func testAFailedStartKeepsThePanelOpenWithRetry() async throws {
        // No time to answer: every start the app makes fails, though launchd starts the server.
        relaunch(one, ["-startTimeout", "0"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        app.typeKey("t", modifierFlags: [.command, .option])
        let filter = element("open-session.filter")
        XCTAssertTrue(hasKeyboard(filter))
        app.typeText(six)
        XCTAssertTrue(element("open-session.new.\(six)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])

        let notice = element("open-session.notice")
        XCTAssertTrue(notice.exists(within: 10))
        let text = "Could not start \(six)."
        let said = notice.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text,
                                                           text)).firstMatch
        XCTAssertTrue(said.exists, notice.debugDescription)
        XCTAssertEqual(notice.images["notice.symbol"].label, "Error")
        XCTAssertTrue(filter.exists)
        XCTAssertTrue(element("open-session.new.\(six)").exists)
        keepScreenshot("could not start")

        try await running(six, start: false)
        notice.buttons["notice.retry"].click()
        XCTAssertTrue(filter.vanishes(within: connect))
        XCTAssertTrue(until(connect) { element("sidebar.header").value as? String == six })
    }

    func testFindScrollsHerdrsViewportToTheMatch() async throws {
        step("200 lines in a shell")
        let pane = try await twoHundredLines("find")

        step("Find: counts, steps through the matches, scrolls herdr to one")
        app.typeKey("f", modifierFlags: .command)
        let field = element("find.field"), count = element("find.count")
        XCTAssertTrue(hasKeyboard(field))
        field.typeText("line 4")
        XCTAssertTrue(count.has(\.stringValue, "11 of 11", within: 2), count.stringValue)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(count.has(\.stringValue, "1 of 11", within: 2), count.stringValue)
        app.typeKey(.return, modifierFlags: .shift)
        XCTAssertTrue(count.has(\.stringValue, "11 of 11", within: 2), count.stringValue)
        app.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(count.has(\.stringValue, "1 of 11", within: 2), count.stringValue)
        element("find.previous").click()
        XCTAssertTrue(count.has(\.stringValue, "11 of 11", within: 2), count.stringValue)
        element("find.next").click()
        XCTAssertTrue(count.has(\.stringValue, "1 of 11", within: 2), count.stringValue)
        // The Window menu has an item named "find" too: the bar is the group.
        XCTAssertEqual(app.groups.matching(identifier: "find").firstMatch.frame.width, 320, accuracy: 1)
        field.click()
        app.typeKey("a", modifierFlags: .command)

        app.typeText("line 42")
        XCTAssertTrue(count.has(\.stringValue, "1 of 1", within: 2), count.stringValue)
        // line 42 sits 158 lines above the bottom line: herdr's viewport scrolled to it.
        try await expect("herdr to scroll") { try await scrollOffset(pane) > 100 }
        try await expectHighlight("line 42", in: pane)
        keepScreenshot("find bar")

        step("Find: Escape and the close button close it, herdr back at the bottom")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 2))
        try await expect("herdr back at the bottom") { try await scrollOffset(pane) == 0 }
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(field))
        element("find.close").click()
        XCTAssertTrue(field.vanishes(within: 2))

        step("Find: the blank rows under the text count; a tab switch closes it")
        // The screen cleared (its text goes to the scrollback) and two more matches under it: the blank rows under the
        // prompt count too, and the selected match is the lower one.
        try await send("printf '\\033[2J\\033[H'\r", to: pane)
        try await waitFor(pane) { !$0.contains("line 199") }
        try await send("for i in 42 42; do echo line $i; done\r", to: pane)
        try await waitFor(pane) { $0.contains("line 42\nline 42\n") }
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(field))
        app.typeText("line 42")
        XCTAssertTrue(count.has(\.stringValue, "3 of 3", within: 2), count.stringValue)
        try await expectHighlight("line 42", in: pane)
        try await expect("herdr to center the match") { try await scrollOffset(pane) > 0 }
        element("tab.w2:t1").click()
        XCTAssertTrue(field.vanishes(within: 2))
        try await expect("herdr back at the bottom") { try await scrollOffset(pane) == 0 }
    }

    func testAFindBarClosedBeforeItsReadLeavesHerdrAtTheBottom() async throws {
        app.launchEnvironment["SHELL"] = "\(Self.agents)/login-shell"
        app.launchEnvironment["PATH"] = "\(Self.fixtures)/late-herdr:/usr/bin:/bin"
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        // The fixture marks its late answer here: a file of this run's, in the runner's own folder (it is sandboxed).
        let answered = NSTemporaryDirectory() + "ovvi-late-answer-" + UUID().uuidString
        app.launchEnvironment["OVVI_E2E_LATE_MARK"] = answered
        defer { try? FileManager.default.removeItem(atPath: answered) }
        relaunch()
        let pane = try await twoHundredLines("late")
        app.typeKey("f", modifierFlags: .command)
        let field = element("find.field")
        XCTAssertTrue(hasKeyboard(field))
        field.typeText("line 42")
        // herdr's text has not come yet.
        XCTAssertEqual(element("find.count").stringValue, "0 of 0")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 2))
        // The read answers 3 s after ⌘F: the fixture marks it just before it lets the answer go, and a scroll it
        // set off would land well within a second of that.
        try await expect("herdr's late answer", times: 60) { FileManager.default.fileExists(atPath: answered) }
        try await Task.sleep(for: .seconds(1))
        let offset = try await scrollOffset(pane)
        XCTAssertEqual(offset, 0)
    }

    private func twoHundredLines(_ label: String) async throws -> String {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab(label)
        element("tab.\(tab)").click()
        try await send("for i in $(seq 1 200); do echo line $i; done\r", to: pane)
        try await waitFor(pane) { $0.contains("\nline 200\n") }
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        return pane
    }

    private func expectHighlight(_ text: String, in pane: String) async throws {
        let lit = element("find.highlights")
        var expected = ""
        do {
            try await expect("the highlights") {
                let rows = try await read(pane).split(separator: "\n", omittingEmptySubsequences: false)
                let last = rows.lastIndex { $0 == text }.map(String.init) ?? "none"
                expected = "\(rows.count { $0 == text }) shown, current row \(last)"
                return lit.stringValue == expected
            }
        } catch is Waited {
            throw Waited(description: "expected \(expected); the highlights say \(lit.stringValue)")
        }
    }

    func testCommandClickOnALinkOpensIt() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("link")
        element("tab.\(tab)").click()
        let folder = "/tmp/ovvi-e2e-links", address = "https://example.com/ovvi"
        try await send(
            "rm -rf \(folder) && mkdir -p \(folder) && touch \(folder)/notes.md \(folder)/page.html && clear; "
                + "echo ftp://example.com/x; echo \(address).; echo /reload your open pi; echo \(folder)/notes.md.; "
                + "echo \(folder)/page.html\r",
            to: pane,
        )
        try await waitFor(pane) { $0.hasPrefix("ftp://example.com/x\n\(address).\n") }
        sendAfter("rm -rf \(folder)\r", to: pane)
        let terminal = element("terminal.\(pane)")
        let grid = try XCTUnwrap(terminal.value as? String).split(separator: " ").compactMap { Double($0) }
        let cell = CGSize(width: terminal.frame.width / grid[1], height: terminal.frame.height / grid[0])
        let link = { (row: Double) in
            terminal.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: cell.width * 5.5, dy: cell.height * (row + 0.5)))
        }
        let before = try await tabIDs()
        for row in [0.0, 2.0, 1.0] {
            link(row).hover()
            XCUIElement.perform(withKeyModifiers: .command) { link(row).click() }
        }
        try await expectBrowser(newTabID(after: before), " \(address)")
        let tabs = try await tabIDs()
        XCTAssertEqual(tabs.count, before.count + 1, "\(tabs)")
        XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected })
        XCUIElement.perform(withKeyModifiers: .command) { link(4).click() }
        try await expectBrowser(newTabID(after: tabs), "\(folder)/page.html")

        optionShowsLinks(terminal, link(1), address, link(4), "page.html")

        XCUIElement.perform(withKeyModifiers: .option) { link(3).click() }
        let side = try await sidePane(in: tab, besides: [pane])
        try await labelEnds(side, " \(folder)/notes.md")

        link(1).rightClick()
        XCTAssertTrue(app.windows.menuItems["Select All"].exists(within: 2))
        XCTAssertFalse(app.windows.menuItems["Open to the Side"].exists)
        keepScreenshot("terminal menu over a link")
        app.typeKey(.escape, modifierFlags: [])
    }

    private func optionShowsLinks(_ terminal: XCUIElement, _ start: XCUICoordinate, _ first: String,
                                  _ other: XCUICoordinate, _ end: String)
    {
        start.hover()
        XCTAssertTrue(until(3) { terminal.title.isEmpty }, terminal.title)
        XCUIElement.perform(withKeyModifiers: .option) {
            XCTAssertTrue(until(3) { terminal.title.hasPrefix(first) }, terminal.title)
            other.hover()
            XCTAssertTrue(until(3) { terminal.title.hasSuffix(end) }, terminal.title)
        }
        XCTAssertTrue(until(3) { terminal.title.isEmpty }, terminal.title)
    }

    private func expectBrowser(_ tab: String, _ end: String) async throws {
        closeAfter("tab", tab)
        let pane = try await pane(of: tab)
        try await expect("ovvi:browser#…\(end) in \(tab)") {
            let label = try await paneLabel(pane)
            return label.hasPrefix("ovvi:browser#") && label.hasSuffix(end)
        }
    }

    func testCardShowsItsTerminalOnceHerdrDrewItAtItsSize() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("ready")
        let terminal = try await terminalID(pane)
        try await Self.post("\(one)/control", Data(terminal.utf8))
        try await send("trap 'echo resized $(stty size)' WINCH\r", to: pane)
        try await waitFor(pane) { $0.contains("WINCH") }

        element("tab.\(tab)").click()
        let card = element("pane.\(pane)")
        XCTAssertTrue(card.exists(within: 3))
        try await expect("\(pane) ready, it says \(card.stringValue)", times: 100) {
            card.exists && card.stringValue != "loading"
        }
        let grid = try XCTUnwrap(element("terminal.\(pane)").value as? String)
        // Unwrapped: the line after CI's long prompt wraps.
        let screen = try await read(pane, "recent_unwrapped")
        XCTAssertTrue(screen.contains("resized \(grid)"), "card \(grid), screen:\n\(screen)")
    }

    func testNeverShownTabsCardNamesItsProgram() async throws {
        let capsule = element("tab.w1:t2")
        XCTAssertTrue(capsule.exists(within: connect))
        XCTAssertFalse(capsule.isSelected)
        let names = try await foreground("w1:p4")
        let program = try XCTUnwrap(names.first)
        capsule.hover()
        let row = element("hovercard.w1:p4")
        XCTAssertTrue(row.exists(within: 2))
        XCTAssertTrue(until(3) { row.label.hasPrefix("\(program), ") }, "\(row.label), not \(program)")
    }

    func testFoldersDroppedOnTheDockOpenWorkspaces() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let ovvi = Self.devApp
        let warm = try await dropFolder(ovvi)
        let opened = try await workspace(in: warm)
        XCTAssertTrue(element("workspace.\(opened)").has(\.isSelected, true, within: 3))
        XCTAssertEqual(app.windows.count, 1)

        app.terminate()
        let cold = try await dropFolder(ovvi)
        // The Debug build's own id, never the installed app's.
        let relaunched = XCUIApplication(bundleIdentifier: "dev.ovvi.app.debug")
        addTeardownBlock { relaunched.terminate() }
        // The launch connects first (login shell, herdr checks): slow on CI.
        let started = try await workspace(in: cold, times: Int(connect * 10))
        XCTAssertTrue(relaunched.descendants(matching: .any)["workspace.\(started)"].has(\.isSelected, true,
                                                                                         within: connect))
        XCTAssertEqual(relaunched.windows.count, 1)
    }

    private func dropFolder(_ ovvi: String) async throws -> String {
        try await String(decoding: Self.post("\(one)/open-folder", Data(ovvi.utf8)), as: UTF8.self)
    }

    private func workspace(in folder: String, times: Int = 50) async throws -> String {
        let name = (folder as NSString).lastPathComponent
        let id = try await poll("a workspace in \(name)", times: times) { () async throws -> String? in
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
            return panes.first { ($0["cwd"] as? String)?.hasSuffix(name) == true }?["workspace_id"] as? String
        }
        closeAfter("workspace", id)
        return id
    }

    private func scrollOffset(_ pane: String) async throws -> Int {
        try await field((self.pane(pane)["scroll"] as? [String: Any])?["offset_from_bottom"], "\(pane)'s scroll offset")
    }
}
