import XCTest

extension OvviUITests {
    func testTheSidebarsEmptyAreaHasTheSessionMenu() {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let shelf = element("agents.shelf.Archived Sessions")
        if shelf.value as? String == "expanded" {
            shelf.click()
            addTeardownBlock { @MainActor in shelf.click() }
        }
        let below = element("workspace.w2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 120))
        below.rightClick()
        let menu = app.windows.firstMatch.menuItems
        XCTAssertTrue(menu["New Space"].exists(within: 2))
        XCTAssertTrue(menu["Open Session…"].exists)
        XCTAssertFalse(menu["Detach Session"].isEnabled)
        keepScreenshot("sidebar menu")
        menu["Show Archived Sessions"].click()
        XCTAssertTrue(shelf.has(\.stringValue, "expanded", within: 2))
        element("sidebar.header").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        menu["Hide Archived Sessions"].click()
        XCTAssertTrue(shelf.has(\.stringValue, "collapsed", within: 2))
        below.rightClick()
        menu["Open Session…"].click()
        XCTAssertTrue(element("open-session.filter").exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
    }

    func testLaunchOpensOnePageAndNoOtherSession() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        XCTAssertEqual(header, one)
        XCTAssertEqual(pageList(), [one])
        let runs = try await runs(two)
        XCTAssertEqual(runs, [])

        let filter = openSessionPanel()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        openSessionPanel()
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).click()
        XCTAssertTrue(filter.vanishes(within: 2))
    }

    func testMenuLightFollowsThePointer() {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(element("titlebar.workspace").exists(within: 2))
        element("titlebar.workspace").click()
        let alpha = element("workspaces.\(one).w1"), beta = element("workspaces.\(one).w2")
        XCTAssertTrue(alpha.has(\.isSelected, true, within: 2))
        beta.hover()
        XCTAssertTrue(beta.has(\.isSelected, true, within: 2))
        XCTAssertFalse(alpha.isSelected)
        element("workspaces.open-session").click()
        let open = element("open-session.session.\(two)") // above the fold: other tests' sessions push rows down
        XCTAssertTrue(open.exists(within: 2))
        XCTAssertFalse(open.isSelected)
        open.hover()
        XCTAssertTrue(open.has(\.isSelected, true, within: 2))
        keepScreenshot("open session lit by the pointer")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("k", modifierFlags: .command)
        let tab = element("palette.tab.w1:t1"), workspace = element("palette.workspace.\(one).w2")
        XCTAssertTrue(workspace.exists(within: 2))
        workspace.hover()
        XCTAssertTrue(workspace.has(\.isSelected, true, within: 2))
        tab.hover()
        XCTAssertTrue(tab.has(\.isSelected, true, within: 2))
        XCTAssertFalse(workspace.isSelected)
    }

    func testOptionSwipesMoveBetweenSessionsAndWorkspaces() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        showPage(one)
        XCTAssertTrue(until(3) { header == one })
        let card = element("terminal.w1:p1").frame, center = "\(card.midX) \(card.midY)"
        // The other way if natural scrolling is off.
        var forward = -1.0
        for sign in [-1.0, 1.0] where header != two {
            forward = sign
            try await Self.post("\(one)/swipe", Data("\(center) \(10 * sign) 14 0 0 1".utf8))
            _ = until(3) { header == two }
        }
        XCTAssertEqual(header, two)
        try await Self.post("\(one)/swipe", Data("\(center) \(-10 * forward) 14 0 0 1".utf8))
        XCTAssertTrue(until(3) { header == one })
        XCTAssertTrue(element("tab.w1:t1").isSelected)

        XCTAssertTrue(element("workspace.w1").isSelected)
        try await Self.post("\(one)/swipe", Data("\(center) 10 4 0 1 1".utf8))
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 3))
        try await Self.post("\(one)/swipe", Data("\(center) -10 4 0 1 1".utf8))
        XCTAssertTrue(element("workspace.w1").has(\.isSelected, true, within: 3))
        XCTAssertEqual(header, one)

        XCUIElement.perform(withKeyModifiers: .option) { element("terminal.w1:p1").scroll(byDeltaX: 0, deltaY: 30) }
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 3))

        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(element("titlebar.workspace").exists(within: 2))
        try await Self.post("\(one)/swipe", Data("\(center) \(10 * forward) 14 0 0 1".utf8))
        XCTAssertTrue(until(3) { self.app.windows.firstMatch.title.hasSuffix(" - \(two)") })
    }

    func testSwipesPageTheSidebarAndNotTheTabs() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        showPage(one)
        let sidebar = element("sidebar"), header = element("sidebar.header")
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        try await swipe(sidebar, until: header, \.stringValue, two)
        try await swipe(sidebar, until: header, \.stringValue, one)
        XCTAssertTrue(element("tab.w1:t1").isSelected)
        let edge = element("terminal.w1:p1").coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 30, dy: 0))
        let width = Double(element("terminal.w1:p1").frame.width)
        for delta in [-width, width] {
            edge.hover()
            edge.scroll(byDeltaX: delta, deltaY: 0)
            XCTAssertFalse(until(1) { !self.element("tab.w1:t1").isSelected }, "a wheel of \(delta) changed the tab")
        }
        XCTAssertEqual(header.stringValue, one)

        try await swipe(sidebar, until: header, \.stringValue, two)
    }

    func testSwipedSessionPagesShowTheirRows() async throws {
        try await running(five)
        openPage(two)
        openPage(five)
        showPage(one)
        let sidebar = element("sidebar"), header = element("sidebar.header")
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.'"))
        var delta = -Double(sidebar.frame.width)
        for session in [two, five] {
            sidebar.hover()
            sidebar.scroll(byDeltaX: delta, deltaY: 0)
            if !header.has(\.stringValue, session, within: 1.5) {
                delta = -delta
                sidebar.scroll(byDeltaX: delta, deltaY: 0)
            }
            XCTAssertTrue(header.has(\.stringValue, session, within: 1.5))
            try await Task.sleep(for: .seconds(0.5))
            XCTAssertTrue(rows.firstMatch.exists(within: 3), session)
            XCTAssertTrue(sidebar.frame.contains(rows.firstMatch.frame), "\(rows.firstMatch.frame) \(sidebar.frame)")
            XCTAssertTrue(rows.firstMatch.isHittable, session)
        }
    }

    func testRelaunchRestoresThePagesThatStillRun() async throws {
        try await running(five)
        try await forgetWindows()
        relaunch(windows: .saved)
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 2))
        openPage(five)
        openPage(two)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        try await Self.post("\(five)/stop")

        relaunch(windows: .restored)
        XCTAssertTrue(until(connect) { header == two })
        XCTAssertTrue(pageList().contains(one))
        XCTAssertFalse(pageList().contains(five))
        showPage(one)
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: connect))
    }

    func testEmptyPageOffersNewWorkspace() async throws {
        for workspace in try await running(five)["workspaces"] as? [[String: Any]] ?? [] {
            try await Self.call(five, "workspace.close", ["workspace_id": workspace["workspace_id"] ?? ""])
        }
        relaunch(five)
        let button = element("detail.new-workspace")
        XCTAssertTrue(element("detail.empty").firstMatch.exists(within: connect))
        XCTAssertTrue(element("detail.open-folder").exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.'")).firstMatch
            .exists)
        keepScreenshot("empty page")
        button.click()
        let pane = try await poll("a workspace in herdr") { () async throws -> String? in
            try await (Self.snapshot(five)["panes"] as? [[String: Any]])?.first?["pane_id"] as? String
        }
        XCTAssertTrue(element("terminal.\(pane)").exists(within: 5))
    }

    func testHeaderPlusAndRowMenuChangeHerdr() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let before = try await workspaceIDs()
        element("sidebar.new-workspace").click()
        let made = try await poll("a new workspace") { () async throws -> String? in
            try await workspaceIDs().first { !before.contains($0) }
        }
        closeAfter("workspace", made)
        let row = element("workspace.\(made)")
        XCTAssertTrue(row.has(\.isSelected, true, within: 3))

        row.rightClick()
        app.menuItems["Rename Space"].click()
        let field = element("workspace.\(made).rename")
        XCTAssertTrue(hasKeyboard(field))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("renamed\r")
        try await expect("herdr's label") { try await workspaceLabel(made) == "renamed" }

        let tabs = try await tabIDs()
        row.rightClick()
        // In the window, not the menu bar's File ▸ New Tab.
        app.windows.firstMatch.menuItems["New Tab"].click()
        let tab = try await newTabID(after: tabs)
        XCTAssertEqual(workspace(of: tab), made)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))

        row.rightClick()
        XCTAssertFalse(app.menuItems["Move Down"].isEnabled)
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/resume") }
        _ = try await Self.post("\(one)/pause")
        app.menuItems["Move Up"].click()
        let moved = until(3) { row.frame.maxY <= element("workspace.w2").frame.minY }
        _ = try await Self.post("\(one)/resume")
        XCTAssertTrue(moved, "the row waited for herdr")
        try await expect("herdr's order") { try await workspaceIDs().suffix(2) == [made, "w2"] }
        row.rightClick()
        app.menuItems["Move Down"].click()
        try await expect("herdr's order back") { try await workspaceIDs().last == made }

        try await runSleep(pane(of: tab))
        try await settle(tabIDs().filter { workspace(of: $0) == made })
        row.rightClick()
        app.windows.firstMatch.menuItems["Close Space"].click()
        // A predicate: a query by identifier takes at most 128 characters.
        let text = "sleep is running in it. Its 2 tabs, 2 panes and everything running in them will end, here and "
            + "in every herdr client. This cannot be undone."
        XCTAssertTrue(sheetText(text).exists(within: 2))
        app.sheets.buttons["Close Space"].click()
        try await expect("herdr to close it") { try await !workspaceIDs().contains(made) }
        XCTAssertTrue(row.vanishes(within: 2))
    }

    func testDoubleClickRenamesAndEscapeCancels() async throws {
        let row = element("workspace.w2"), field = element("workspace.w2.rename")
        XCTAssertTrue(row.exists(within: connect))
        row.doubleClick()
        XCTAssertTrue(hasKeyboard(field))
        field.typeText("other")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 2))
        // For a second: a wrong save would land a moment later.
        for _ in 0 ..< 10 {
            let label = try await workspaceLabel("w2")
            XCTAssertEqual(label, "beta")
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(row.label, "beta")
    }

    func testSidebarHandleResizesWithinItsBounds() {
        step("Sidebar handle: the first tab lines up with its card")
        let sidebar = element("sidebar"), handle = element("sidebar.resize")
        let tab = element("tab.w1:t1"), card = element("pane.w1:p1")
        XCTAssertTrue(card.exists(within: connect))
        XCTAssertEqual(tab.frame.minX, card.frame.minX, accuracy: 1)
        let start = sidebar.frame.width
        let drag = { (offset: CGFloat) in
            let width = sidebar.frame.width, left = card.frame.minX
            let from = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.click(forDuration: 0.2, thenDragTo: from.withOffset(CGVector(dx: offset, dy: 0)))
            let moved = sidebar.frame.width - width
            XCTAssertTrue(until(1) { abs(card.frame.minX - left - moved) <= 2 }, "the card did not move by \(moved)")
            XCTAssertTrue(until(1) { abs(tab.frame.minX - card.frame.minX) <= 1 }, "\(tab.frame) \(card.frame)")
        }

        step("Sidebar handle: drags resize within 227 and 480, and the tabs follow the card")
        drag(60)
        XCTAssertEqual(sidebar.frame.width, start + 60, accuracy: 2)
        drag(-600)
        XCTAssertEqual(sidebar.frame.width, 227, accuracy: 1)
        drag(600)
        XCTAssertEqual(sidebar.frame.width, 480, accuracy: 1)
        drag(start - 480)
    }

    func testTheSelectedRowScrollsIntoView() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        var rows: [String] = [], panes: [String] = []
        for index in 0 ..< 24 {
            let (tab, pane) = try await createWorkspace("long\(index)")
            try await report(pane, "working")
            (rows, panes) = (rows + ["workspace.\(workspace(of: tab))"], panes + [pane])
        }
        let header = element("sidebar.header"), filter = element("sidebar.filter")
        let first = element("workspace.w1"), long0 = element(rows[0]), last = element(rows[23])
        let inView = { (row: XCUIElement) in
            row.exists && row.frame.minY >= header.frame.maxY && row.frame.maxY <= filter.frame.minY
        }
        XCTAssertTrue(until(5) {
            self.app.typeKey("1", modifierFlags: [.command, .control])
            self.app.typeKey("[", modifierFlags: [.command, .control])
            return until(1) { last.isSelected }
        })
        XCTAssertTrue(until(2) { inView(last) }, "\(last.frame), filter \(filter.frame)")
        let end = element("agent.\(panes[23])").frame
        XCTAssertGreaterThan(end.maxY, filter.frame.minY - 60, "\(end), filter \(filter.frame)")
        XCTAssertFalse(inView(first))
        app.typeKey("3", modifierFlags: [.command, .control])
        XCTAssertTrue(until(2) { long0.isSelected && long0.frame.minY >= header.frame.maxY + 21 }, "\(long0.frame)")
        app.typeKey("1", modifierFlags: [.command, .control])
        XCTAssertTrue(until(2) { first.isSelected && inView(first) }, "\(first.frame)")
    }

    func workspaceIDs() async throws -> [String] {
        try await Self.ids("workspace", in: one)
    }

    func workspaceLabel(_ id: String) async throws -> String? {
        let snapshot = try await snapshot()
        return (snapshot["workspaces"] as? [[String: Any]])?.first { $0["workspace_id"] as? String == id }?["label"]
            as? String
    }
}
