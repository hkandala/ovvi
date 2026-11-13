import XCTest

extension OvviUITests {
    func testClosingAPaneAsksUnlessOnlyItsShellRuns() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, first) = try await newTab("close")
        let second = try await split(first)
        element("tab.\(tab)").click()

        try await runSleep(second)
        hoverHeader(second)
        element("pane.\(second).close").click()
        let confirm = app.sheets.buttons["Close Pane"]
        XCTAssertTrue(confirm.exists(within: 2))
        XCTAssertTrue(until(2) { isRed(confirm) })
        XCTAssertTrue(app.sheets.staticTexts["sleep is running in it and will end, here and in every herdr client. "
                + "This cannot be undone."].exists)
        keepScreenshot("close pane dialog")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(confirm.vanishes(within: 2))
        XCTAssertTrue(element("pane.\(second)").exists)
        hoverHeader(second)
        element("pane.\(second).close").click()
        XCTAssertTrue(confirm.exists(within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("pane.\(second)").vanishes(within: 3))

        try await waitForPrompt(first)
        hoverHeader(first)
        element("pane.\(first).close").click()
        XCTAssertTrue(element("pane.\(first)").vanishes(within: 3))
        // The card hides at once, but herdr closes the pane only once no program runs in it, after any ask.
        try await expect("herdr closed \(first)") { try await !Self.ids("pane", in: one).contains(first) }
        XCTAssertFalse(confirm.exists)
    }

    func testClosingTheKeyboardCardHandsKeysToItsNeighbor() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("handoff")
        let right = try await split(left)
        element("tab.\(tab)").click()
        try await waitForPrompt(left)
        try await waitForPrompt(right)
        element("terminal.\(left)").click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(left)").vanishes(within: 3))
        try await typeAndRead(right)
    }

    func testClosingATabAsksOnlyWhileAProgramRuns() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("doomed")
        let second = try await split(pane)
        // A startup program still running would make the second close ask.
        try await waitForPrompt(pane)
        try await runSleep(second)
        let row = element("tab.\(tab)")
        row.hover()
        element("tab.\(tab).close").click()
        let confirm = app.sheets.buttons["Close Tab"]
        XCTAssertTrue(confirm.exists(within: 2))
        let text = "sleep is running in it. Its 2 panes and everything running in them will end, here and in every "
            + "herdr client. This cannot be undone."
        XCTAssertTrue(sheetText(text).exists(within: 2))
        keepScreenshot("close tab dialog")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(confirm.vanishes(within: 2))

        try await Self.call(one, "pane.send_keys", ["pane_id": second, "keys": ["ctrl+c"]])
        try await expect("the shell to be back") { try await !foreground(second).contains("sleep") }
        // Off and back on: the capsule under the dialog saw no hover end, so a hover there starts nothing.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.9)).hover()
        row.hover()
        element("tab.\(tab).close").click()
        XCTAssertTrue(row.vanishes(within: 3))
        // herdr closes the tab only once no program runs in it, after any ask.
        try await expect("herdr closed \(tab)") { try await !tabIDs().contains(tab) }
        XCTAssertFalse(confirm.exists)
    }

    func testCommandTOpensInTheKeyboardCardsDirectoryAndCommandWClosesIt() async throws {
        XCTAssertTrue(element("terminal.w1:p2").exists(within: connect))
        try await waitForPrompt("w1:p2")
        try await send("cd /usr\r", to: "w1:p2")
        element("terminal.w1:p2").click()

        var pane = try await commandT()
        try await waitForPrompt(pane)
        pickTerminal(pane)
        try await typeAndRead(pane)
        let tab = try await tabOf(pane)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").vanishes(within: 3))

        element("tab.w1:t1").click()
        let header = element("pane.w1:p2").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 17))
        header.doubleClick()
        XCTAssertTrue(element("pane.w1:p1").vanishes(within: 2))
        header.doubleClick()
        XCTAssertTrue(element("pane.w1:p1").exists(within: 2))
        pane = try await commandT()
        try await closeAfter("tab", tabOf(pane))
    }

    private func commandT() async throws -> String {
        let before = try await tabIDs()
        app.typeKey("t", modifierFlags: .command)
        let tab = try await newTabID(after: before)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))
        let panes = try await snapshot()["panes"] as? [[String: Any]]
        let pane = try XCTUnwrap(panes?.first { $0["tab_id"] as? String == tab })
        XCTAssertEqual(pane["cwd"] as? String, "/usr")
        return try XCTUnwrap(pane["pane_id"] as? String)
    }

    func testNewWorkspaceAppearsSelected() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("tab.w1:t2").click()
        element("titlebar.sidebar").click()
        XCTAssertTrue(element("sidebar.filter").vanishes(within: 2))
        element("titlebar.sidebar").click()
        XCTAssertTrue(element("sidebar.new-workspace").exists(within: 2))
        let before = try await tabIDs()
        element("sidebar.new-workspace").click()
        let tab = try await newTabID(after: before)
        let workspace = workspace(of: tab)
        closeAfter("workspace", workspace)
        XCTAssertTrue(element("workspace.\(workspace)").exists(within: 3))
        XCTAssertTrue(element("page.\(tab)").exists(within: 3))
        XCTAssertFalse(element("page.w1:t1").exists)
        let pane = "\(workspace):p1"
        XCTAssertTrue(element("pane.\(pane)").has(\.isHittable, true, within: 3))
        try await waitForPrompt(pane)
        pickTerminal(pane)
        try await typeAndRead(pane)
    }

    func testZoomFillsThePageAndRestores() async throws {
        let card = element("pane.w1:p2")
        XCTAssertTrue(element("terminal.w1:p2").exists(within: connect))
        try await expectPTYSize("w1:p2")
        let page = element("page.w1:t1").frame, before = card.frame
        let neighbor = try XCTUnwrap(element("terminal.w1:p3").value as? String)
        hoverHeader("w1:p2")
        element("pane.w1:p2.zoom").click()
        XCTAssertTrue(element("pane.w1:p1").vanishes(within: 2))
        XCTAssertTrue(element("pane.w1:p3").vanishes(within: 2))
        XCTAssertEqual(card.frame.width, page.width, accuracy: 2)
        try await expectPTYSize("w1:p2")
        keepScreenshot("zoom")
        element("terminal.w1:p2").click()
        app.typeText("echo ovvi-zoom-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p2") { $0.contains("\novvi-zoom-42") }
        // The columns within one: CI's 1x display rounds a hidden card's width differently.
        try await send("clear; stty size\r", to: "w1:p3")
        let grid = neighbor.split(separator: " ").compactMap { Int($0) }
        try await waitFor("w1:p3") { text in
            text.split(separator: "\n").contains { line in
                let size = line.split(separator: " ").compactMap { Int($0) }
                return size.count == 2 && grid.count == 2 && size[0] == grid[0] && abs(size[1] - grid[1]) <= 1
            }
        }

        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.w1:p1").exists(within: 2))
        XCTAssertTrue(element("pane.w1:p3").exists)
        XCTAssertEqual(card.frame.width, before.width, accuracy: 2)
        try await expectPTYSize("w1:p2")
    }

    /// The user's steps: a zoom in one tab, then in another, leaves the first tab zoomed.
    func testEachTabKeepsItsOwnZoom() async throws {
        let (first, one) = try await newTab("zoom-one")
        let oneHidden = try await split(one)
        let (second, two) = try await newTab("zoom-two")
        let twoHidden = try await split(two)
        for (tab, pane, hidden) in [(first, one, oneHidden), (second, two, twoHidden)] {
            element("tab.\(tab)").click()
            XCTAssertTrue(element("pane.\(hidden)").has(\.isHittable, true, within: 3))
            hoverHeader(pane)
            element("pane.\(pane).zoom").click()
            XCTAssertTrue(element("pane.\(hidden)").vanishes(within: 2))
        }
        for (tab, pane, hidden) in [(first, one, oneHidden), (second, two, twoHidden)] {
            element("tab.\(tab)").click()
            XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3), tab)
            XCTAssertTrue(element("pane.\(pane).zoom").has(\.label, "Restore Pane ⇧⌘↩", within: 3), tab)
            XCTAssertFalse(element("pane.\(hidden)").exists, tab)
            XCTAssertTrue(hasKeyboard("terminal.\(pane)"), tab)
        }
        // A card that comes into a zoomed tab is not hidden under its zoom.
        paneMenu(two, "Move Pane to Tab", "zoom-one")
        XCTAssertTrue(element("pane.\(oneHidden)").has(\.isHittable, true, within: 3))
        XCTAssertTrue(hasKeyboard("terminal.\(two)"))
    }

    func testPaletteFiltersAndJumps() {
        step("Palette: keys typed right after ⌘K from a terminal reach the filter")
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("terminal.w1:p1").click()
        app.typeKey("k", modifierFlags: .command)
        app.typeText("seco")
        let filter = element("palette.filter")
        XCTAssertTrue(element("palette.tab.w1:t1").vanishes(within: 2))
        XCTAssertTrue(element("palette.tab.w1:t2").exists)
        XCTAssertTrue(hasKeyboard(filter), "the keyboard is on \(keyboardOwner())")

        step("Palette: Return jumps to the tab, then to a space")
        keepScreenshot("palette")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))

        element("titlebar.palette").click()
        XCTAssertTrue(hasKeyboard(filter))
        app.typeText("beta")
        XCTAssertTrue(element("palette.workspace.\(one).w2").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("page.w2:t1").exists(within: 2))

        step("Palette: Escape closes it")
        openPalette()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
    }

    func testPaletteEnterTakesTheMovedRowAndKeysFollow() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openPalette()
        app.typeText("show")
        XCTAssertTrue(element("palette.command.Show Overview").has(\.isSelected, true, within: 2))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(element("palette.command.Show Previous Tab").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))
        try await waitForPrompt("w1:p4")
        try await typeAndRead("w1:p4")
    }
}
