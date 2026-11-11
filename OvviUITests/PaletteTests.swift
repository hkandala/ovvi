import XCTest

extension OvviUITests {
    func testPaletteSplitsTheKeyboardCardRight() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("palette")
        element("tab.\(tab)").click()
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        openPalette()
        // The first group, its places, then its commands: a lazy list builds only the rows in view, and CI's screen
        // is small.
        let tabs = element("palette.section.Tabs")
        XCTAssertTrue(tabs.exists(within: 2))
        let rows = [tabs, element("palette.tab.\(tab)"), element("palette.command.New Tab"),
                    element("palette.command.Close Other Tabs")].map(\.frame.minY)
        XCTAssertEqual(rows, rows.sorted(), "\(rows)")
        XCTAssertEqual(Set(rows).count, 4, "\(rows)")
        keepScreenshot("palette root")
        app.typeText("split r")
        XCTAssertTrue(element("palette.command.Split Right").has(\.isSelected, true, within: 2))
        XCTAssertEqual(element("palette.command.Split Right").value as? String, "Panes")
        XCTAssertFalse(element("palette.section.Panes").exists)
        keepScreenshot("palette filtered")
        app.typeKey(.return, modifierFlags: [])
        let panes = try await poll("a second pane in the tab") { () async throws -> [[String: Any]]? in
            let panes = try await (snapshot()["panes"] as? [[String: Any]] ?? [])
                .filter { $0["tab_id"] as? String == tab }
            return panes.count == 2 ? panes : nil
        }
        let other = try XCTUnwrap(panes.compactMap { $0["pane_id"] as? String }.first { $0 != pane })
        XCTAssertTrue(element("pane.\(other)").exists(within: 2))
        XCTAssertLessThan(element("pane.\(pane)").frame.maxX, element("pane.\(other)").frame.minX)
    }

    func testPaletteLightStaysWhileTheListScrolls() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openPalette()
        let lit = element("palette.command.New Tab"), other = element("palette.command.Close Other Tabs")
        XCTAssertTrue(lit.exists(within: 2))
        lit.hover()
        XCTAssertTrue(lit.has(\.isSelected, true, within: 2))
        let pointer = lit.frame.midY
        lit.scroll(byDeltaX: 0, deltaY: -40)
        XCTAssertTrue(until(2) { lit.frame.maxY < pointer }, "not scrolled off: \(pointer) → \(lit.frame)")
        XCTAssertFalse(until(0.5) { !lit.isSelected }, "the light followed the scroll")
        other.hover()
        XCTAssertTrue(other.has(\.isSelected, true, within: 2))

        // Its frame first: at the end the lazy list holds no New Tab, which finds it.
        let list = app.scrollViews.containing(.button, identifier: "palette.command.New Tab").firstMatch
        let bottom = list.frame.maxY
        list.scroll(byDeltaX: 0, deltaY: -10000)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'palette.'"))
        let gap = { bottom - (rows.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0) }
        XCTAssertTrue(until(3) { abs(gap() - 10) < 1.5 }, "the end's gap: \(gap())")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testPaletteRenamesTheWorkspaceAndThePane() async throws {
        step("Palette: Rename Space, prefilled with its label")
        let (tabs, pane) = try await newWorkspace("before")
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        let filter = openPalette()
        app.typeText("rename space")
        XCTAssertTrue(element("palette.command.Rename Space").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.has(\.stringValue, "before", within: 2))
        app.typeKey("a", modifierFlags: .command)
        app.typeText("after")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        try await expect("herdr's workspace label") { try await workspaceLabel(workspace(of: tabs[0])) == "after" }

        try await expectPaletteRenamesTheTab(tabs[0], filter)

        step("Palette: Rename Pane and Reset Pane Name")
        openPalette()
        app.typeText("rename pane")
        XCTAssertTrue(element("palette.command.Rename Pane…").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.has(\.stringValue, "", within: 2))
        app.typeText("named")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        try await expect("herdr's pane label") { try await paneLabel(pane) == "named" }

        openPalette()
        app.typeText("reset pane name")
        XCTAssertTrue(element("palette.command.Reset Pane Name").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        try await expect("no pane label") { try await paneLabel(pane).isEmpty }
    }

    private func expectPaletteRenamesTheTab(_ tab: String, _ filter: XCUIElement) async throws {
        step("Palette: Rename Tab, prefilled with its label; an empty name goes back to the list")
        // Its own label, not the space's: the field must show the tab's.
        try await Self.call(one, "tab.rename", ["tab_id": tab, "label": "tab-before"])
        let capsule = element("tab.\(tab)")
        XCTAssertTrue(until(3) { capsule.label.contains("tab-before") }, capsule.label)
        openPalette()
        app.typeText("rename tab")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.has(\.stringValue, "tab-before", within: 2))
        XCTAssertFalse(element("palette.section.Tabs").exists)
        keepScreenshot("palette rename")
        app.typeKey("a", modifierFlags: .command)
        app.typeText("tab-after")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        try await expect("herdr's tab label") {
            let found = try await snapshot()["tabs"] as? [[String: Any]] ?? []
            return found.contains { $0["tab_id"] as? String == tab && $0["label"] as? String == "tab-after" }
        }

        openPalette()
        app.typeText("rename tab")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.has(\.stringValue, "tab-after", within: 2))
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(filter.has(\.stringValue, "", within: 2))
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(element("palette.section.Tabs").exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
    }

    func testPaletteAppearancePreviewsAndEscRestores() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        // Settings persist in the app's own defaults: start dark, and end dark even when a step fails.
        pick("Appearance", "Dark")
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        let look = element("window.look")
        XCTAssertTrue(until(2) { look.stringValue.hasSuffix(" dark") })
        let dark = look.stringValue, light = dark.replacing("dark", with: "light")
        let filter = openPalette()
        app.typeText("dark")
        XCTAssertTrue(element("palette.command.Appearance").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(pageTitle(is: "Appearance"))
        XCTAssertTrue(element("palette.choice.Dark").has(\.isSelected, true, within: 2))
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(element("palette.choice.Light").has(\.isSelected, true, within: 2))
        XCTAssertEqual(look.stringValue, dark)
        XCTAssertTrue(look.has(\.stringValue, light, within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(look.has(\.stringValue, dark, within: 2))
        XCTAssertTrue(element("palette.section.Tabs").exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))

        openPalette()
        app.typeText("dark")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("palette.choice.Dark").has(\.isSelected, true, within: 2))
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(look.has(\.stringValue, light, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        XCTAssertFalse(until(0.5) { look.stringValue != light })
    }

    func testSecondShortcuts() {
        XCTAssertTrue(element("tab.w1:t1").has(\.isSelected, true, within: connect))
        element("terminal.w1:p1").click()
        app.typeKey("p", modifierFlags: [.command, .shift])
        let filter = element("palette.filter")
        XCTAssertTrue(filter.exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))

        // The menu's state, not the grid: on a 1x display one step can keep the grid.
        addTeardownBlock { @MainActor [self] in app.typeKey("0", modifierFlags: .command) }
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(resetFontSize(enabled: false))
        app.typeKey("=", modifierFlags: .command)
        XCTAssertTrue(resetFontSize(enabled: true))

        openPalette()
        app.typeText("font size")
        for title in ["Increase Font Size", "Decrease Font Size", "Reset Font Size"] {
            XCTAssertTrue(element("palette.command.\(title)").exists(within: 2), title)
        }
        app.typeKey(.return, modifierFlags: [])
        app.typeText("30")
        app.typeKey(.return, modifierFlags: [])
        openPalette()
        app.typeText("font size")
        app.typeKey(.return, modifierFlags: [])
        let size = element("palette.choice.30 pt")
        XCTAssertTrue(size.has(\.isSelected, true, within: 2))
        XCTAssertTrue(size.isHittable)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])

        // Settings persist: Focus Follows Mouse ends off even when a step fails.
        let row = element("palette.command.Focus Follows Mouse")
        addTeardownBlock { @MainActor [self] in
            openPalette()
            app.typeText("focus follows")
            app.typeKey(row.exists(within: 2) && row.label == "Turn Off Focus Follows Mouse" ? .return : .escape,
                        modifierFlags: [])
        }
        openPalette()
        app.typeText("focus follows")
        XCTAssertTrue(row.has(\.label, "Turn On Focus Follows Mouse", within: 2))
        app.typeKey(.return, modifierFlags: [])
        openPalette()
        app.typeText("focus follows")
        XCTAssertTrue(row.has(\.label, "Turn Off Focus Follows Mouse", within: 2))
        app.typeKey(.return, modifierFlags: [])
    }

    func testPaletteOpensThePanelAndANewWindow() throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openPalette()
        app.typeText("open session")
        app.typeKey(.return, modifierFlags: [])
        let panel = element("open-session.filter")
        XCTAssertTrue(panel.exists(within: 2))
        element("open-session.session.\(two)").click()
        XCTAssertTrue(until(connect) { pageList().contains(two) })

        let identifier = app.windows.firstMatch.identifier
        openPalette()
        app.typeText("new window")
        app.typeKey(.return, modifierFlags: [])
        let pick = element("picker.local.\(one)")
        XCTAssertTrue(pick.exists(within: connect))
        pick.click()
        let window = try otherWindow(than: identifier)
        XCTAssertTrue(element("sidebar.header", in: window).has(\.stringValue, one, within: 3))
        XCTAssertFalse(pageList(in: window).contains(two))
    }

    func testPaletteShowsAnotherOpenPage() {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        showPage(one)
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, one, within: 3))
        openPalette()
        app.typeText(two)
        XCTAssertTrue(element("palette.session.\(two)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, two, within: 3))
    }

    func testGoToDirectoryAndInsertPath() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("paths")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(pane)").has(\.isHittable, true, within: 3))
        let folder = "/private/tmp/ovvi-e2e-go-\(Int.random(in: 1000 ... 9999))"
        try await waitForPrompt(pane)
        try await send("mkdir -p \(folder) && touch '\(folder)/a b'; clear\r", to: pane)
        sendAfter("rm -rf \(folder)\r", to: pane)
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        try await send("cat\r", to: pane)
        try await expect("cat in the pane") { try await foreground(pane).contains("cat") }
        app.typeKey("g", modifierFlags: [.command, .shift])
        choose(folder)
        XCTAssertTrue(app.staticTexts["A program is running in the pane"].exists(within: 3))
        let text = try await read(pane)
        XCTAssertFalse(text.contains("cd --"))
        try await Self.call(one, "pane.send_keys", ["pane_id": pane, "keys": ["ctrl+c"]])
        try await expect("the shell again") { try await !foreground(pane).contains("cat") }

        element("terminal.\(pane)").click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        choose(folder)
        // The line may wrap at the card's width.
        try await waitFor(pane, toShow: "cd -- '\(folder)/'", times: 100)
        try await send("clear; pwd\r", to: pane)
        try await waitFor(pane) { $0.split(separator: "\n").contains { $0 == folder } }

        try await send("clear\r", to: pane)
        element("terminal.\(pane)").click()
        app.typeKey("i", modifierFlags: [.command, .shift])
        choose("\(folder)/a b")
        try await waitFor(pane, toShow: "'\(folder)/a b'", times: 100)
    }

    private func choose(_ path: String) {
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.exists(within: 3))
        keepScreenshot("open panel")
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(path)
        app.typeKey(.return, modifierFlags: [])
        panel.buttons["Open"].click()
        // The Go to Folder field looks up each typed letter: slow.
        XCTAssertTrue(panel.vanishes(within: 10))
    }

    func testMoveToTabLandsBesideTheLastCard() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (mover, pane) = try await newTab("mover")
        let (target, first) = try await newTab("target")
        let last = try await split(first)
        element("tab.\(target)").click()
        XCTAssertTrue(element("pane.\(last)").exists(within: 2))
        element("tab.\(mover)").click()
        XCTAssertTrue(element("pane.\(pane)").has(\.isHittable, true, within: 3))
        paneMenu(pane, "Move Pane to Tab")
        let entry = app.windows.firstMatch.menuItems["Move Pane to Tab"]
        XCTAssertTrue(entry.menuItems["second"].exists(within: 2))
        XCTAssertTrue(entry.menuItems["alpha"].exists)
        XCTAssertFalse(entry.menuItems["mover"].exists)
        XCTAssertEqual(entry.menuItems.firstMatch.title, "New Tab")
        keepScreenshot("move pane to tab")
        entry.menuItems["target"].click()
        try await expect("the pane right of the last card") { try await order(target) == [first, last, pane] }
        // Drawn there ahead of the click: herdr's order comes first, and a click on the card's earlier frame goes to
        // the last card (on CI).
        let (card, lastCard) = (element("pane.\(pane)"), element("pane.\(last)"))
        XCTAssertTrue(until(3) { card.frame.minX > lastCard.frame.maxX })

        XCTAssertTrue(element("terminal.\(pane)").exists(within: 5))
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        // The menu bar's has no tabs: AppKit searches them at every key.
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Pane"].hover()
        let bar = app.menuBars.menuItems["Move Pane to Tab"]
        bar.hover()
        XCTAssertTrue(bar.menuItems["New Space"].exists(within: 2))
        XCTAssertFalse(bar.menuItems["second"].exists)
        XCTAssertFalse(bar.menuItems["alpha"].exists)
        app.menuBars.menuBarItems["View"].click()
        let before = try await tabIDs()
        openPalette()
        app.typeText("move pane to")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(pageTitle(is: "Move Pane to Tab"))
        XCTAssertTrue(element("palette.section.alpha").exists(within: 2))
        app.typeText("new tab")
        app.typeKey(.return, modifierFlags: [])
        let moved = try await newTabID(after: before)
        closeAfter("tab", moved)
        try await expect("the pane alone in the new tab") { try await order(moved) == [pane] }
    }

    /// Read with the menu open: SwiftUI updates a closed menu's items late.
    private func resetFontSize(enabled: Bool) -> Bool {
        app.menuBars.menuBarItems["View"].click()
        let found = app.menuBars.menuItems["Reset Font Size"].has(\.isEnabled, enabled, within: 2)
        app.typeKey(.escape, modifierFlags: [])
        return found
    }

    /// A heading: XCUITest may give its text as the label or the value.
    private func pageTitle(is title: String) -> Bool {
        let header = element("palette.title")
        return until(2) { header.exists && [header.label, header.stringValue].contains(title) }
    }
}
