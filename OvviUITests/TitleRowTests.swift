import XCTest

extension OvviUITests {
    func testTabsLineUpWithTheCards() {
        let tab = element("tab.w1:t1"), card = element("pane.w1:p1"), handle = element("sidebar.resize")
        XCTAssertTrue(card.exists(within: connect))
        XCTAssertEqual(tab.frame.minX, card.frame.minX, accuracy: 1)
        for offset: CGFloat in [60, -60] {
            let before = card.frame.minX
            let from = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.click(forDuration: 0.2, thenDragTo: from.withOffset(CGVector(dx: offset, dy: 0)))
            XCTAssertTrue(until(1) { abs(card.frame.minX - before - offset) <= 2 }, "the drag resized nothing")
            XCTAssertTrue(until(1) { abs(tab.frame.minX - card.frame.minX) <= 1 }, "\(tab.frame) \(card.frame)")
        }
    }

    func testTabsStayInTheTitleRowWithTheSidebarOpenOrCollapsed() {
        let window = app.windows.firstMatch, toggle = element("titlebar.sidebar")
        let tab = element("tab.w1:t2"), workspace = element("titlebar.workspace")
        XCTAssertTrue(tab.exists(within: connect))
        XCTAssertEqual(toggle.value as? String, "open")
        XCTAssertLessThan(tab.frame.maxY, window.frame.minY + 46)
        XCTAssertFalse(workspace.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "tab.w1:t2").count, 1)
        keepScreenshot("sidebar open")

        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(element("sidebar.filter").vanishes(within: 2))
        XCTAssertEqual(toggle.value as? String, "closed")
        XCTAssertTrue(workspace.exists(within: 2))
        XCTAssertEqual(workspace.value as? String, "\(one) | alpha")
        XCTAssertLessThan(tab.frame.maxY, window.frame.minY + 46)
        XCTAssertGreaterThan(tab.frame.minX, workspace.frame.maxX)
        keepScreenshot("sidebar collapsed")

        toggle.click()
        XCTAssertTrue(element("sidebar.filter").exists(within: 2))
        XCTAssertEqual(toggle.value as? String, "open")
        XCTAssertTrue(workspace.vanishes(within: 2))
    }

    func testMachineMenuListsThisMac() {
        XCTAssertTrue(element("titlebar.machine").exists(within: connect))
        element("titlebar.machine").click()
        let thisMac = app.menuItems["This Mac"]
        XCTAssertTrue(thisMac.exists(within: 2))
        // Its checkmark is not in XCUITest's view of a menu item; the screenshot shows it.
        XCTAssertTrue(app.menuItems["Add Machine…"].exists)
        keepScreenshot("machine menu")
        thisMac.click()
        XCTAssertTrue(thisMac.vanishes(within: 2))
        XCTAssertFalse(until(0.5) { app.windows.count != 1 || !element("tab.w1:t2").exists })
    }

    func testWorkspaceMenuMakesAndPicksWorkspaces() async throws {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        app.typeKey("s", modifierFlags: [.command, .control])
        let button = element("titlebar.workspace")
        XCTAssertTrue(button.exists(within: 2))
        let filter = openWorkspaceMenu()
        XCTAssertTrue(element("workspaces.\(one).w1").isSelected)
        keepScreenshot("workspace menu")
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(element("workspaces.\(one).w2").has(\.isSelected, true, within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        openWorkspaceMenu()

        let name = "made-\(Int.random(in: 1000 ... 9999))"
        app.typeText(name)
        XCTAssertTrue(element("workspaces.create").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        let made = try await poll("herdr to have \(name)") { () async throws -> String? in
            let workspaces = try await snapshot()["workspaces"] as? [[String: Any]] ?? []
            return workspaces.first { $0["label"] as? String == name }?["workspace_id"] as? String
        }
        closeAfter("workspace", made)
        // In home, not the server's cwd (the runner's own home is its sandbox container).
        let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
        XCTAssertEqual(
            panes.first { $0["workspace_id"] as? String == made }?["cwd"] as? String,
            "/Users/\(NSUserName())",
        )
        try await expect("the button to show \(name)") { button.value as? String == "\(one) | \(name)" }
        XCTAssertTrue(element("tab.\(made):t1").exists(within: 2))

        openWorkspaceMenu()
        element("workspaces.\(one).w2").click()
        XCTAssertTrue(element("tab.w2:t1").exists(within: 2))
        XCTAssertTrue(element("tab.\(made):t1").vanishes(within: 2))
        XCTAssertEqual(button.value as? String, "\(one) | beta")
        keepScreenshot("one tab")
    }

    func testWorkspaceMenuFiltersAndItsItemsAct() async throws {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(element("titlebar.workspace").exists(within: 2))
        let filter = openWorkspaceMenu()
        app.typeText("bet")
        XCTAssertTrue(element("workspaces.\(one).w1").vanishes(within: 2))
        XCTAssertTrue(element("workspaces.\(one).w2").exists)

        let before = try await workspaceIDs()
        closeNew("workspace", besides: before)
        element("workspaces.new").click()
        let made = try await poll("a new workspace") { () async throws -> String? in
            try await workspaceIDs().first { !before.contains($0) }
        }
        XCTAssertTrue(element("tab.\(made):t1").has(\.isSelected, true, within: 3))

        openWorkspaceMenu()
        element("workspaces.open-session").click()
        XCTAssertTrue(hasKeyboard("open-session.filter"))
        XCTAssertFalse(filter.exists)
    }

    func testCloseButtonShowsOnTheHoveredTabAndCloses() async throws {
        let tabs = try await newWorkspace("row", tabs: 3).tabs
        let workspace = workspace(of: tabs[0])
        let close = element("tab.\(tabs[1]).close")
        XCTAssertFalse(close.exists)
        XCTAssertTrue(element("tab.\(tabs[0])").isSelected)
        XCTAssertFalse(element("tab.\(tabs[0]).close").exists)
        element("tab.\(tabs[1])").hover()
        XCTAssertTrue(close.exists(within: 2))
        keepScreenshot("hover and close")
        element("tab.\(tabs[2])").hover()
        XCTAssertTrue(close.vanishes(within: 2))
        element("tab.\(tabs[1])").hover()
        XCTAssertTrue(close.exists(within: 2))
        try await settle([tabs[1]])
        close.click()
        try await expect("herdr to close it") { try await tabsOf(workspace).map(\.id) == [tabs[0], tabs[2]] }
        XCTAssertTrue(element("tab.\(tabs[1])").vanishes(within: 2))
    }

    func testTabContextMenuRenamesAndMoves() async throws {
        let tabs = try await newWorkspace("row", tabs: 3).tabs
        let workspace = workspace(of: tabs[0])
        keepScreenshot("three tabs")
        let field = element("tab.\(tabs[0]).rename")
        let before = try await tabsOf(workspace).first?.label
        element("tab.\(tabs[0])").doubleClick()
        XCTAssertTrue(field.exists(within: 2))
        app.typeKey("a", modifierFlags: .command)
        app.typeText("nope")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 2))
        XCTAssertFalse(element("tab.\(tabs[0])").label.contains("nope"))

        element("tab.\(tabs[0])").rightClick()
        app.menuItems["Rename Tab"].click()
        XCTAssertTrue(field.exists(within: 2))
        // A herdr read after Esc: a write Esc made by mistake has landed by then.
        let after = try await tabsOf(workspace).first?.label
        XCTAssertEqual(after, before)
        XCTAssertTrue(hasKeyboard(field))
        app.typeKey("a", modifierFlags: .command)
        app.typeText("renamed\r")
        try await expect("herdr's label") { try await tabsOf(workspace).first?.label == "renamed" }
        XCTAssertTrue(field.vanishes(within: 2))

        element("tab.\(tabs[0])").rightClick()
        XCTAssertFalse(app.windows.firstMatch.menuItems["Move Tab Left"].isEnabled)
        app.windows.firstMatch.menuItems["Move Tab Right"].click()
        try await expect("the new order") { try await tabsOf(workspace).map(\.id) == [tabs[1], tabs[0], tabs[2]] }
        let moved = element("tab.\(tabs[0])")
        XCTAssertTrue(moved.isSelected)
        app.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        try await expect("the order back") { try await tabsOf(workspace).map(\.id) == tabs }
        // Drawn there too: a right click can read the capsule's place ahead of the snapshot's draw, and hit the next
        // tab.
        let next = element("tab.\(tabs[1])")
        XCTAssertTrue(until(2) { moved.frame.maxX <= next.frame.minX }, "\(moved.frame), \(next.frame)")
        moved.rightClick()
        app.menuItems["Rename Tab"].click()
        XCTAssertTrue(field.exists(within: 2))
        app.typeKey(.rightArrow, modifierFlags: [.command, .shift])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 2))
        // A move would go through herdr: give it time to land.
        try await Task.sleep(for: .seconds(1))
        let order = try await tabsOf(workspace).map(\.id)
        XCTAssertEqual(order, tabs)
        openPalette()
        app.typeText("move tab right")
        app.typeKey(.return, modifierFlags: [])
        try await expect("moved from the palette") {
            try await tabsOf(workspace).map(\.id) == [tabs[1], tabs[0], tabs[2]]
        }
    }

    func testCloseOtherTabsAsksOnceAndLeavesOneTab() async throws {
        let tabs = try await newWorkspace("row", tabs: 3).tabs
        let workspace = workspace(of: tabs[0])
        try await runSleep(split("\(workspace):p1"))
        try await settle(tabs)
        element("tab.\(tabs[1])").rightClick()
        app.windows.firstMatch.menuItems["Close Other Tabs"].click()
        let confirm = app.sheets.buttons["Close Tabs"]
        XCTAssertTrue(confirm.exists(within: 2))
        XCTAssertTrue(app.sheets.staticTexts
            .matching(NSPredicate(format: "value BEGINSWITH 'sleep is running in them. Their 3 panes' "
                    + "OR label BEGINSWITH 'sleep is running in them. Their 3 panes'")).firstMatch
            .exists(within: 2))
        confirm.click()
        try await expect("one tab left") { try await tabsOf(workspace).map(\.id) == [tabs[1]] }
        XCTAssertTrue(element("tab.\(tabs[0])").vanishes(within: 2))
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testTabsKeepTheirWidthAndTheRowScrolls() async throws {
        let tabs = try await newWorkspace("row", tabs: 8).tabs
        let capsules = tabs.map { element("tab.\($0)") }, first = capsules[0], last = capsules[7]
        let fades = element("tabs.fades"), rowEnd = element("titlebar.overview").frame.minX - 8
        XCTAssertTrue(first.exists(within: 3))
        XCTAssertEqual(first.frame.width, 220, accuracy: 1)
        XCTAssertLessThan(element("titlebar.new-tab").frame.maxX, app.windows.firstMatch.frame.maxX)
        XCTAssertTrue(fades.has(\.stringValue, "trailing", within: 2))
        keepScreenshot("eight tabs")

        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(last.has(\.isSelected, true, within: 2))
        XCTAssertEqual(last.frame.width, 220, accuracy: 1)
        XCTAssertLessThanOrEqual(last.frame.maxX, rowEnd + 1)
        XCTAssertTrue(fades.has(\.stringValue, "leading", within: 2))
        keepScreenshot("scrolled to the last tab")

        try await swipe(last, by: 330, until: fades, \.stringValue, "leading, trailing")
        let inView = capsules.filter(\.exists)
        let cut = try XCTUnwrap(inView.first { $0.frame.minX < rowEnd - 20 && $0.frame.maxX > rowEnd },
                                "\(inView.map(\.frame.minX)) to \(rowEnd)")
        let start = cut.frame.minX
        XCTAssertFalse(cut.isSelected)
        cut.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 10, dy: 0)).click()
        XCTAssertTrue(cut.has(\.isSelected, true, within: 2))
        XCTAssertFalse(until(0.6) { abs(cut.frame.minX - start) > 0.5 }, "scrolled from \(start) to \(cut.frame.minX)")

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(first.has(\.isSelected, true, within: 2))
        app.typeKey("t", modifierFlags: .command)
        let made = try await poll("the new tab") {
            try await tabsOf(workspace(of: tabs[0])).last.flatMap { tabs.contains($0.id) ? nil : $0.id }
        }
        XCTAssertTrue(element("tab.\(made)").has(\.isSelected, true, within: 3))
        XCTAssertTrue(until(1) { element("tab.\(made)").frame.maxX <= rowEnd + 1 })
    }

    func testWindowTitleOfADefaultLabelIsTheProgramAndFolder() async throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        // The shell is zsh here, bash on CI.
        try await expect("the window title ‹shell› | tmp - ‹session›") { window.title.hasSuffix("sh | tmp - \(one)") }
    }

    @discardableResult
    private func openWorkspaceMenu() -> XCUIElement {
        element("titlebar.workspace").click()
        let filter = element("workspaces.filter")
        XCTAssertTrue(hasKeyboard(filter))
        return filter
    }

    private func tabsOf(_ workspace: String) async throws -> [(id: String, label: String)] {
        let snapshot = try await snapshot()
        return (snapshot["tabs"] as? [[String: Any]] ?? []).filter { $0["workspace_id"] as? String == workspace }
            .compactMap { tab in (tab["tab_id"] as? String).map { ($0, tab["label"] as? String ?? "") } }
    }
}
