import XCTest

extension OvviUITests {
    /// The foot counts the agents of every attached session on the machine, in both windows; its panel lists those
    /// that need you, then those done, and a pick shows the agent's tab in whichever window has its session.
    func testTheSidebarFootSumsUpTheAgentsAndItsPanelGoesToOne() async throws {
        let (first, second) = try newWindow(session: two)
        raise(first)
        let summary = element("sidebar.agents", in: first), panel = element("agents.panel", in: first)

        step("Nothing works, finished or needs you: all caught up, and the panel says so")
        XCTAssertTrue(summary.has(\.stringValue, "All caught up", within: 3), summary.stringValue)
        keepScreenshot("foot, all caught up")
        summary.click()
        XCTAssertTrue(element("agents.panel.empty", in: first).exists(within: 2))
        XCTAssertEqual(element("agents.panel.header", in: first).stringValue, "Agents · This Mac")
        keepScreenshot("agents panel, empty")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.vanishes(within: 2), "Esc closes the panel")

        step("An agent works")
        // In w2: only session one has it, so no query matches both windows.
        let working = try await newTab("foot-work").pane
        try await report(working, "working", agent: "pi")
        XCTAssertTrue(summary.has(\.stringValue, "1 working", within: 5), summary.stringValue)
        keepScreenshot("foot, 1 working")

        step("Another window's session finishes: done comes before working, in both windows")
        let done = try await createTab(in: "w1", label: "foot-done", session: two)
        closeAfter("tab", done.tab, in: two)
        try await report(done.pane, "working", agent: "claude", session: two)
        XCTAssertTrue(element("agent.\(done.pane)", in: second).has(\.stringValue, "Working", within: 5))
        try await report(done.pane, "idle", agent: "claude", session: two)
        XCTAssertTrue(summary.has(\.stringValue, "1 done", within: 5), summary.stringValue)
        XCTAssertEqual(element("sidebar.agents", in: second).stringValue, "1 done")
        keepScreenshot("foot, 1 done")
        summary.click()
        let doneRow = element("agents.panel.\(two).\(done.pane)", in: first)
        XCTAssertTrue(doneRow.exists(within: 2))
        XCTAssertEqual(doneRow.label, "Untitled, \(two) · gamma")
        XCTAssertFalse(element("agents.panel.\(one).\(working)", in: first).exists, "a working agent is listed")
        keepScreenshot("agents panel, done only")
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).click()
        XCTAssertTrue(panel.vanishes(within: 2), "a click outside closes the panel")
        try await needsYouComesFirst(first, second, done: done, doneRow: doneRow)
    }

    private func needsYouComesFirst(_ first: XCUIElement, _ second: XCUIElement, done: (tab: String, pane: String),
                                    doneRow: XCUIElement) async throws
    {
        let summary = element("sidebar.agents", in: first), panel = element("agents.panel", in: first)
        step("An agent needs you: that comes first, and the tooltip lists every count")
        let needs = try await newTab("foot-needs")
        try await report(needs.pane, "blocked")
        XCTAssertTrue(summary.has(\.stringValue, "1 needs you", within: 5), summary.stringValue)
        summary.hover()
        let tip = element("tooltip", in: first)
        XCTAssertTrue(until(3) { tip.stringValue.hasPrefix("1 needs you · 1 done · 1 working") }, tip.stringValue)
        keepScreenshot("foot, 1 needs you, its tooltip")

        step("The panel: Needs you, then Done")
        summary.click()
        let needsRow = element("agents.panel.\(one).\(needs.pane)", in: first)
        try await expectOrder([element("agents.panel.group.Needs you", in: first), needsRow,
                               element("agents.panel.group.Done", in: first), doneRow], "Needs you, then Done")
        XCTAssertEqual(needsRow.frame.height, 48, accuracy: 0.5)
        keepScreenshot("agents panel, needs you and done")

        step("A pick shows its tab")
        needsRow.click()
        XCTAssertTrue(panel.vanishes(within: 2))
        XCTAssertTrue(element("tab.\(needs.tab)", in: first).has(\.isSelected, true, within: 3))

        step("A pick in the other window's session brings that window forward")
        summary.click()
        doneRow.click()
        XCTAssertTrue(until(3) { app.windows.firstMatch.identifier == second.identifier }, "the other window in front")
        XCTAssertTrue(element("tab.\(done.tab)", in: second).has(\.isSelected, true, within: 3))
    }

    /// The foot's buttons name their keys and open what those keys open.
    func testTheSidebarFootsButtonsOpenTheirPanels() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let tip = element("tooltip")
        for (button, text) in [("shortcuts", "Keyboard Shortcuts ⌘/"), ("palette", "Command Palette ⌘K"),
                               ("settings", "Settings ⌘,")]
        {
            element("sidebar.\(button)").hover()
            // A static text: XCUITest gets its label as its value.
            XCTAssertTrue(tip.has(\.stringValue, text, within: 3), tip.stringValue)
            keepScreenshot("foot, \(button) tooltip")
        }
        element("sidebar.shortcuts").click()
        XCTAssertTrue(element("shortcuts").exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("shortcuts").vanishes(within: 2))
        element("sidebar.palette").click()
        XCTAssertTrue(element("palette.filter").exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("palette.filter").vanishes(within: 2))
        element("sidebar.settings").click()
        XCTAssertTrue(settingsWindow.exists(within: 3))
    }
}
