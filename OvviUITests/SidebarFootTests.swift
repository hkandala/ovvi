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
        XCTAssertTrue(element("sidebar.agents", in: second).has(\.stringValue, "1 done", within: 2))
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
        XCTAssertFalse(element("tab.\(needs.tab)", in: first).isSelected)
        needsRow.click()
        XCTAssertTrue(panel.vanishes(within: 2))
        XCTAssertTrue(element("tab.\(needs.tab)", in: first).has(\.isSelected, true, within: 3))

        step("A pick in the other window's session brings that window forward")
        XCTAssertFalse(element("tab.\(done.tab)", in: second).isSelected)
        summary.click()
        doneRow.click()
        XCTAssertTrue(until(3) { app.windows.firstMatch.identifier == second.identifier }, "the other window in front")
        XCTAssertTrue(element("tab.\(done.tab)", in: second).has(\.isSelected, true, within: 3))
    }

    /// The foot's buttons name their keys and open what those keys open.
    func testTheSidebarFootsButtonsOpenTheirPanels() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        // On Archived Sessions' text, and as far over the window's bottom.
        let summary = element("sidebar.agents"), window = mainWindows.firstMatch
        XCTAssertEqual(summary.frame.minX - window.frame.minX, 18, accuracy: 0.5, "\(summary.frame)")
        XCTAssertEqual(window.frame.maxY - summary.frame.maxY, 18, accuracy: 0.5, "\(summary.frame) in \(window.frame)")
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
        summary.click()
        let panel = element("agents.panel")
        XCTAssertTrue(panel.exists(within: 2))
        XCTAssertEqual(panel.frame.minX, summary.frame.minX, accuracy: 0.5, "the panel on the summary's left edge")
        XCTAssertEqual(panel.frame.maxX, element("sidebar.settings").frame.maxX, accuracy: 0.5,
                       "the panel on the gear's right edge")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.vanishes(within: 2))
        element("sidebar.settings").click()
        XCTAssertTrue(settingsWindow.exists(within: 3))
    }

    /// The panel scrolls past its most height. Clear All on Done and a done row's × mark finishes seen, so those agents
    /// turn idle; an agent that needs you has neither.
    func testTheAgentsPanelScrollsAndClearsItsDoneAgents() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let summary = element("sidebar.agents"), panel = element("agents.panel")

        step("One agent needs you and 11 are done")
        var done: [String] = []
        // Over the list's 440 pt.
        for index in 0 ..< 12 {
            let made = try await createTab(in: "w2", label: "clear-\(index)")
            closeAfter("tab", made.tab)
            try await report(made.pane, "working")
            done.append(made.pane)
        }
        XCTAssertTrue(summary.has(\.stringValue, "12 working", within: 10), summary.stringValue)
        let needs = done.removeFirst()
        try await report(needs, "blocked")
        for pane in done {
            try await report(pane, "idle")
        }
        summary.click()
        let header = element("agents.panel.group.Done")
        XCTAssertTrue(header.has(\.stringValue, "Done · 11", within: 5), header.stringValue)

        step("The list scrolls inside the panel")
        let prefix = "agents.panel.\(one)."
        // Ids, not the bound elements: a removed row shifts their indexes.
        let order = panel.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }.map(\.identifier)
        XCTAssertEqual(order.count, 12)
        XCTAssertEqual(order.first, prefix + needs)
        XCTAssertLessThanOrEqual(panel.frame.height, 440 + 60, "\(panel.frame)")
        let last = element(order[11])
        XCTAssertFalse(last.isHittable, "the last row shows unscrolled: \(last.frame) in \(panel.frame)")
        keepScreenshot("agents panel, 12 agents")
        panel.scroll(byDeltaX: 0, deltaY: -3000)
        XCTAssertTrue(last.has(\.isHittable, true, within: 2), "\(last.frame) in \(panel.frame)")
        keepScreenshot("agents panel, scrolled to the end")
        clearsDone(order, needs: needs)
    }

    /// `order`: the panel's rows from the top, scrolled to the end; the first needs you.
    private func clearsDone(_ order: [String], needs: String) {
        let panel = element("agents.panel"), header = element("agents.panel.group.Done")
        let prefix = "agents.panel.\(one).", clearPrefix = "agents.panel.clear.\(one)."
        let last = element(order[11]), clearLast = element(order[11].replacing(prefix, with: clearPrefix))
        step("A done row under the pointer lights and shows its ×, which clears it")
        last.hover()
        XCTAssertTrue(clearLast.exists(within: 2), "no × on a done row under the pointer")
        XCTAssertTrue(last.isSelected, "a done row under the pointer is not lit")
        keepScreenshot("agents panel, a done row under the pointer")
        clearLast.click()
        XCTAssertTrue(last.vanishes(within: 2))
        XCTAssertTrue(header.has(\.stringValue, "Done · 10", within: 2), header.stringValue)
        // At the list's end the row above slides under the resting pointer.
        XCTAssertTrue(element(order[10].replacing(prefix, with: clearPrefix)).exists(within: 2),
                      "the row that came under the pointer shows no ×")

        step("A row that needs you lights with no ×")
        panel.scroll(byDeltaX: 0, deltaY: 3000)
        let needsRow = element(prefix + needs)
        XCTAssertTrue(needsRow.has(\.isHittable, true, within: 2))
        XCTAssertEqual(needsRow.frame.minX - panel.frame.minX, 8, accuracy: 0.5, "the rows' side inset")
        XCTAssertEqual(panel.frame.maxX - needsRow.frame.maxX, 8, accuracy: 0.5, "the rows' side inset")
        needsRow.hover()
        XCTAssertTrue(needsRow.has(\.isSelected, true, within: 2), "a row under the pointer is not lit")
        XCTAssertFalse(element(clearPrefix + needs).exists, "a × on a row that needs you")
        keepScreenshot("agents panel, a row that needs you under the pointer")

        step("Clear All is on Done only and clears every done agent")
        let all = panel.descendants(matching: .any).matching(identifier: "agents.panel.clearAll")
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.firstMatch.frame.midY, header.frame.midY, accuracy: 2)
        all.firstMatch.click()
        XCTAssertTrue(header.vanishes(within: 2))
        XCTAssertTrue(needsRow.exists)
        keepScreenshot("agents panel, cleared")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.vanishes(within: 2))
        element("sidebar.agents").hover()
        let tip = element("tooltip")
        XCTAssertTrue(tip.has(\.stringValue, "1 needs you · 11 idle", within: 3), tip.stringValue)
    }
}
