import XCTest

extension OvviUITests {
    func testSwitchingTabsShowsOnlyTheirPage() async throws {
        step("Tabs: clicks, keys and the palette show only their page")
        let first = element("tab.w1:t1"), second = element("tab.w1:t2")
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        let before = try await tabIDs()
        closeNew("tab", besides: before)

        second.click()
        XCTAssertTrue(showsOnly("w1:t2"))
        first.click()
        XCTAssertTrue(showsOnly("w1:t1"))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(showsOnly("w1:t2"))
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        XCTAssertTrue(app.windows.firstMatch.has(\.title, "second - \(one)", within: 2))
        try await expectPTYSize("w1:p4")
        keepScreenshot("command 2")
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(first.has(\.isSelected, true, within: 2))
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(showsOnly("w1:t1"))
        openPalette()
        element("palette.tab.w1:t2").click()
        XCTAssertTrue(showsOnly("w1:t2"))
        XCTAssertTrue(second.isSelected)
        expectTheWorkspaceKeeps(second)

        step("Tabs: + makes a selected tab; ⌘⇧W, ⌘T and herdr close tabs")
        element("titlebar.new-tab").click()
        let plus = try await newTabID(after: before)
        XCTAssertTrue(plus.hasPrefix("w1:"), plus)
        XCTAssertTrue(showsOnly(plus))
        XCTAssertTrue(element("tab.\(plus)").has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("page.\(plus)").has(\.isHittable, true, within: 3))
        try await settle([plus])
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("tab.\(plus)").vanishes(within: 3))
        XCTAssertTrue(showsOnly("w1:t2"))
        app.typeKey("t", modifierFlags: .command)
        let made = try await newTabID(after: before)
        XCTAssertTrue(showsOnly(made))
        try await Self.call(one, "tab.close", ["tab_id": made])
        XCTAssertTrue(showsOnly("w1:t2"))
        try await expectCardSwipesKeep(second)
    }

    /// ⌘1 in a workspace of one tab keeps it.
    private func expectTheWorkspaceKeeps(_ tab: XCUIElement) {
        step("Tabs: each workspace keeps its tab")
        element("workspace.w2").click()
        XCTAssertTrue(element("pane.w2:p1").has(\.isHittable, true, within: 2))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("pane.w2:p1").has(\.isHittable, true, within: 2))
        element("workspace.w1").click()
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        XCTAssertTrue(tab.isSelected)
    }

    private func expectCardSwipesKeep(_ tab: XCUIElement) async throws {
        step("Tabs: a card swipe keeps the tab")
        let card = element("terminal.w1:p4").frame
        for delta in [30, -30] {
            try await Self.post("\(one)/swipe", Data("\(card.midX) \(card.midY) \(delta) 14".utf8))
            // A swipe that changes the tab does so within a frame or two.
            XCTAssertFalse(until(0.5) { !tab.isSelected }, "a swipe of \(delta) changed the tab")
        }
        XCTAssertTrue(showsOnly("w1:t2"))
    }

    /// Only that tab's page, of every tab's.
    private func showsOnly(_ tab: String) -> Bool {
        let pages = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'page.'"))
        return until(2) { pages.allElementsBoundByIndex.map(\.identifier) == ["page.\(tab)"] }
    }

    func testSidewaysScrollsReachAWidePage() async throws {
        let (tab, pane) = try await newTab("wide")
        element("tab.\(tab)").click()
        try await waitForPrompt(pane)
        let file = "/tmp/ovvi-e2e-wide.html"
        try await send("printf '<title>x 0</title><body style=\"margin:0\"><div style=\"width:6000px;"
            + "height:200px;background:linear-gradient(90deg,red,blue)\"></div><script>onscroll = () => "
            + "document.title = \\x27x \\x27 + scrollX</script>' >\(file) && clear\r", to: pane)
        try await waitFor(pane) { !$0.contains("printf") }
        let iid = String(format: "e2e%03x", Int.random(in: 0 ..< 4096)), title = element("pane.\(pane).title")
        try await Self.call(one, "pane.rename", ["pane_id": pane, "label": "ovvi:browser#\(iid) file://\(file)"])
        XCTAssertTrue(title.has(\.stringValue, "x 0", within: connect))
        let page = element("browser.\(pane)"), capsule = element("tab.\(tab)")
        XCTAssertTrue(page.has(\.isHittable, true, within: 5))
        // Fingers right to left move the page to the right, or the other way if natural scrolling is off.
        let swipe = "\(page.frame.midX) \(page.frame.midY)"
        for sign in [Self.forward, -Self.forward] where title.stringValue == "x 0" {
            try await Self.post("\(one)/swipe", Data("\(swipe) \(30 * sign) 14".utf8))
            if until(2, { title.stringValue != "x 0" }) {
                Self.forward = sign
            }
        }
        let swiped = title.stringValue
        XCTAssertNotEqual(swiped, "x 0", "a swipe did not scroll the page")
        page.scroll(byDeltaX: -200, deltaY: 0)
        XCTAssertTrue(until(2) { title.stringValue != swiped }, "a sideways wheel left the page at \(swiped)")
        XCTAssertTrue(capsule.isSelected)
    }

    func testClosingTheSelectedTabGoesToTheOneUsedBefore() async throws {
        let tabs = try await newWorkspace("used", tabs: 5).tabs
        let capsules = tabs.map { element("tab.\($0)") }
        XCTAssertTrue(capsules[0].has(\.isSelected, true, within: 2))
        // ⌘ keys: only 3 tabs fit on CI's window.
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(capsules[4].has(\.isSelected, true, within: 2))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(capsules[2].has(\.isSelected, true, within: 2))

        try await Self.call(one, "tab.close", ["tab_id": tabs[2]])
        XCTAssertTrue(capsules[4].has(\.isSelected, true, within: 3))
        try await Self.call(one, "tab.close", ["tab_id": tabs[0]])
        XCTAssertTrue(capsules[0].vanishes(within: 3))
        try await Self.call(one, "tab.close", ["tab_id": tabs[4]])
        XCTAssertTrue(capsules[3].has(\.isSelected, true, within: 3))
    }

    func testQuickNewTabsThenClosesStepBackOneTabEach() async throws {
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        let first = element("tab.w1:t1")
        XCTAssertTrue(first.has(\.isSelected, true, within: connect))
        for _ in 0 ..< 3 {
            app.typeKey("t", modifierFlags: .command)
        }
        let selected = { () -> Int? in
            let capsule = NSPredicate(format: "identifier MATCHES %@", #"tab\.(new\.)?[^.]+"#)
            let capsules = self.app.buttons.matching(capsule).allElementsBoundByIndex
                .sorted { $0.frame.minX < $1.frame.minX }
            return capsules.firstIndex { $0.isSelected }
        }
        XCTAssertTrue(until(3) { selected() == 4 })
        for place in [3, 2, 0] {
            app.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(until(2) { selected() == place }, "after ⌘W: \(String(describing: selected()))")
        }
        try await expect("herdr's tabs as before") { try await tabIDs().sorted() == before.sorted() }
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testCloseTabsToTheRightKeepsTheTabsOnTheLeft() async throws {
        let tabs = try await newWorkspace("right", tabs: 4).tabs
        let workspace = workspace(of: tabs[0])
        let order: () async throws -> [String] = { try await self.tabIDs().filter { $0.hasPrefix("\(workspace):") } }
        try await settle(tabs)
        try await runSleep(pane(of: tabs[3]))
        let confirm = app.sheets.buttons["Close Tabs"]
        element("tab.\(tabs[1])").rightClick()
        // The capsule's menu, not the File menu's item.
        app.windows.firstMatch.menuItems["Close Tabs to the Right"].click()
        XCTAssertTrue(sheetText("Close the 2 tabs to the right?").exists(within: 2))
        XCTAssertTrue(sheetText("sleep is running in them. Their 2 panes and everything running in them will end, "
                + "here and in every herdr client. This cannot be undone.").exists)
        confirm.click()
        try await expect("the two tabs on the left") { try await order() == [tabs[0], tabs[1]] }
        XCTAssertTrue(element("tab.\(tabs[2])").vanishes(within: 2))

        openPalette()
        app.typeText("close tabs to the right")
        app.typeKey(.return, modifierFlags: [])
        try await expect("the first tab alone") { try await order() == [tabs[0]] }
        XCTAssertFalse(confirm.exists)
    }

    func testHoldingADraggedTabAtTheRowsEndScrollsTheRow() async throws {
        let tabs = try await newWorkspace("far", tabs: 8).tabs
        let first = element("tab.\(tabs[0])")
        let rowEnd = element("titlebar.overview").frame.minX - 8
        XCTAssertTrue(element("tabs.fades").has(\.stringValue, "trailing", within: 2))
        let from = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        during(from, to: from.withOffset(CGVector(dx: rowEnd - 5 - first.frame.midX, dy: 0)), hold: 6)
        try await expect("the first tab past the third") {
            try await tabIDs().filter { $0.hasPrefix("\(workspace(of: tabs[0])):") }.firstIndex(of: tabs[0]) ?? 0 > 3
        }
    }

    func testEachWorkspaceShowsItsTabClickedBackAndForth() async throws {
        var shown: [(workspace: String, tab: String)] = []
        for (index, count) in [5, 1].enumerated() {
            let tabs = try await newWorkspace("order\(index)", tabs: count).tabs
            shown.append((workspace(of: tabs[0]), tabs[count == 5 ? 3 : 0]))
        }
        element("workspace.\(shown[0].workspace)").click()
        app.typeKey("4", modifierFlags: .command)
        try await expectShown(shown[0].tab, "the 4th tab")
        for (workspace, tab) in shown.dropFirst() + shown.reversed().dropFirst() {
            element("workspace.\(workspace)").click()
            try await expectShown(tab, "then \(workspace)")
        }
        openSessionPanel()
        element("open-session.session.\(two)").click()
        XCTAssertTrue(element("pane.w1:p1").has(\.isHittable, true, within: connect), "the other session")
        showPage(one)
        try await expectShown(shown[0].tab, "back from the other session")
    }

    func testATabThatOpensOutOfViewSlidesIntoView() async throws {
        relaunch(one, ["-recordMotion", "YES"])
        let (tabs, pane) = try await newWorkspace("opens", tabs: 8)
        let first = element("tab.\(tabs[0])"), rowEnd = element("titlebar.overview").frame.minX - 8
        XCTAssertTrue(first.has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("tabs.fades").has(\.stringValue, "trailing", within: 2))
        // Another client's tab: last, in the background.
        let tab = try await createTab(in: workspace(of: tabs[0])).tab
        let capsule = element("tab.\(tab)")
        XCTAssertTrue(until(3) { capsule.exists && capsule.frame.maxX <= rowEnd + 1 }, "\(capsule.frame) to \(rowEnd)")
        XCTAssertTrue(element("pane.\(pane)").isHittable, "the first tab's page left")
        // It glows as it opens; a tab that opens selected does not.
        let glowed = element("tabs.glowed")
        XCTAssertTrue(glowed.has(\.stringValue, tab, within: 3), glowed.stringValue)
        let before = try await tabIDs()
        app.typeKey("t", modifierFlags: .command)
        let made = try await newTabID(after: before)
        XCTAssertTrue(element("tab.\(made)").has(\.isSelected, true, within: 3))
        let next = try await createTab(in: workspace(of: tabs[0])).tab
        XCTAssertTrue(glowed.has(\.stringValue, "\(tab), \(next)", within: 3), glowed.stringValue)
    }

    func testGoBackAndForwardStepThroughTheTabsShownAcrossSpaces() async throws {
        let tabs = try await newWorkspace("history", tabs: 3).tabs
        let other = try await newWorkspace("elsewhere").tabs[0]
        element("workspace.\(workspace(of: tabs[0]))").click()
        try await expectShown(tabs[0], "back on the first space")
        app.typeKey("3", modifierFlags: .command)
        try await expectShown(tabs[2], "its third tab")
        for (key, tab) in [("[", tabs[0]), ("[", other), ("]", tabs[0])] {
            app.typeKey(key, modifierFlags: [.control, .shift])
            try await expectShown(tab, "\(key == "[" ? "back" : "forward") to \(tab)")
        }
        openPalette()
        app.typeText("go forward")
        app.typeKey(.return, modifierFlags: [])
        try await expectShown(tabs[2], "forward from the palette")
        try await Self.call(one, "tab.close", ["tab_id": tabs[0]])
        XCTAssertTrue(element("tab.\(tabs[0])").vanishes(within: 3))
        app.typeKey("[", modifierFlags: [.control, .shift])
        try await expectShown(other, "back past the closed tab")
    }

    private func expectShown(_ tab: String, _ step: String) async throws {
        let pane = try await pane(of: tab)
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.' AND selected == true"))
        var lit: [String] = []
        let shown = until(3) {
            lit = selected.allElementsBoundByIndex.map(\.identifier)
            return element("pane.\(pane)").exists && element("pane.\(pane)").isHittable && lit == ["tab.\(tab)"]
        }
        keepScreenshot(step)
        XCTAssertTrue(shown, "\(step): \(tab)'s page is not in view, lit: \(lit)")
    }

    func sheetText(_ text: String) -> XCUIElement {
        app.sheets.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", text, text)).firstMatch
    }

    func testCapsulesKeepTheirFramesWhenARowOfOneGrows() async throws {
        let row = element("workspace.w2")
        XCTAssertTrue(row.exists(within: connect))
        row.click()
        let first = element("tab.w2:t1")
        XCTAssertTrue(first.has(\.isHittable, true, within: 3))
        let (tab, _) = try await createTab(in: "w2", label: "grown")
        closeAfter("tab", tab)
        let second = element("tab.\(tab)")
        XCTAssertTrue(second.has(\.isHittable, true, within: 3))
        XCTAssertTrue(until(2) { first.frame.width == second.frame.width }, "\(first.frame) \(second.frame)")
        XCTAssertEqual(first.frame.maxX + 1, second.frame.minX, "\(first.frame) \(second.frame)")
    }

    func testAnnouncementStaysInItsSession() async throws {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        let tab = try await createTab(in: "w1", label: "delta", session: two).tab
        closeAfter("tab", tab, in: two)
        // The agent in a pane of its own, closed after: a released agent on w1:p1 still counts as needing you.
        let agent = try await split("w1:p1", "down")
        closeAfter("pane", agent)
        openPage(two)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        showPage(one)
        element("tab.w1:t2").click()
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))

        try await report(agent, "blocked", agent: "claude")
        let capsule = element("tab.w1:t1")
        XCTAssertTrue(until(3) { capsule.label.contains("claude needs you") }, capsule.label)
        showPage(two)
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, two, within: 2))
        XCTAssertFalse(capsule.label.contains("needs you"), capsule.label)
    }
}

extension OvviUITests {
    /// SwiftUI's lazy stack makes a view's width ahead.
    func testAWorkspaceSwitchMakesOnlyTheCapsulesInView() async throws {
        relaunch(one, ["-recordMotion", "YES"])
        let tabs = try await newWorkspace("many", tabs: 24).tabs
        let first = element("tab.\(tabs[0])"), beta = element("workspace.w2"), made = element("tabs.made")
        let fit = Int((element("titlebar.overview").frame.minX - 8 - first.frame.minX) / (220 + 1)) + 1
        beta.click()
        XCTAssertTrue(beta.has(\.isSelected, true, within: 3))
        let before = Int(made.stringValue) ?? 0
        element("workspace.\(workspace(of: tabs[0]))").click()
        XCTAssertTrue(first.has(\.isSelected, true, within: 3))
        let count = { (Int(made.stringValue) ?? 0) - before }
        // The lazy stack makes the capsules in view on the switch, which the selected capsule above already shows.
        XCTAssertFalse(until(0.5) { count() > 2 * fit + 2 }, "\(count()) capsules made for 24 tabs, \(fit) fit")
        XCTAssertGreaterThan(count(), 0)
    }
}
