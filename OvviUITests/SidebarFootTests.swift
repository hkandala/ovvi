import XCTest

extension OvviUITests {
    /// The foot counts the agents of every attached session on the machine, in both windows; its section lists those
    /// that need you, then those done, then those that work, and a pick shows the agent's tab in whichever window has
    /// its session.
    func testTheSidebarFootSumsUpTheAgentsAndItsSectionGoesToOne() async throws {
        let (first, second) = try newWindow(session: two)
        raise(first)
        let summary = element("sidebar.agents", in: first), section = element("agents.section", in: first)

        step("Nothing works, finished or needs you: all caught up, and the section says so")
        XCTAssertTrue(summary.has(\.stringValue, "All caught up", within: 3), summary.stringValue)
        XCTAssertGreaterThan(summary.frame.width, 40, "the idle box has no words beside its icon")
        summary.hover()
        let idleTip = element("tooltip", in: first)
        XCTAssertTrue(idleTip.has(\.stringValue, "No agents running", within: 3), idleTip.stringValue)
        keepScreenshot("foot, all caught up")
        openAgents(in: first)
        XCTAssertTrue(element("agents.empty", in: first).exists(within: 2))
        XCTAssertEqual(element("agents.empty.text", in: first).stringValue, "No agent is waiting on you")
        XCTAssertEqual(element("agents.header", in: first).stringValue, "Agents · This Mac")
        XCTAssertEqual(element("agents.summary", in: first).stringValue, "No agents running")
        keepScreenshot("agents section, empty")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(section.vanishes(within: 2), "Esc closes the section")

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
        openAgents(in: first)
        let doneRow = element("agents.row.\(two).\(done.pane)", in: first)
        let workingRow = element("agents.row.\(one).\(working)", in: first)
        XCTAssertTrue(doneRow.exists(within: 2))
        XCTAssertEqual(doneRow.label, "Untitled, \(two) · gamma")
        XCTAssertEqual(element("agents.summary", in: first).stringValue, "1 done · 1 working")
        try await expectOrder([element("agents.group.Done", in: first), doneRow,
                               element("agents.group.Working", in: first), workingRow], "Done, then Working")
        keepScreenshot("agents section, done and working")
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).click()
        XCTAssertFalse(section.vanishes(within: 1), "a click outside closes the section")
        summary.click()
        XCTAssertTrue(section.vanishes(within: 2), "the agents' box does not close the section")
        try await needsYouComesFirst(first, second, done: done, rows: (doneRow, workingRow))
    }

    private func needsYouComesFirst(_ first: XCUIElement, _ second: XCUIElement, done: (tab: String, pane: String),
                                    rows: (done: XCUIElement, working: XCUIElement)) async throws
    {
        let summary = element("sidebar.agents", in: first), section = element("agents.section", in: first)
        step("An agent needs you: that comes first, and the tooltip lists every count")
        let needs = try await newTab("foot-needs")
        try await report(needs.pane, "blocked")
        XCTAssertTrue(summary.has(\.stringValue, "1 needs you", within: 5), summary.stringValue)
        // Off the box first: its click hid its tip until the pointer leaves it.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).hover()
        summary.hover()
        let tip = element("tooltip", in: first)
        XCTAssertTrue(until(3) { tip.stringValue.hasPrefix("1 needs you · 1 done · 1 working") }, tip.stringValue)
        keepScreenshot("foot, 1 needs you, its tooltip")

        step("The section: Needs you, then Done, then Working")
        openAgents(in: first)
        let needsRow = element("agents.row.\(one).\(needs.pane)", in: first)
        try await expectOrder([element("agents.group.Needs you", in: first), needsRow,
                               element("agents.group.Done", in: first), rows.done,
                               element("agents.group.Working", in: first), rows.working], "Needs you, Done, Working")
        XCTAssertEqual(needsRow.frame.height, 48, accuracy: 0.5)
        XCTAssertEqual(element("agents.summary", in: first).stringValue, "1 needs you · 1 done · 1 working")
        keepScreenshot("agents section, needs you, done and working")

        step("A pick shows its tab, and the section stays")
        XCTAssertFalse(element("tab.\(needs.tab)", in: first).isSelected)
        needsRow.click()
        XCTAssertTrue(element("tab.\(needs.tab)", in: first).has(\.isSelected, true, within: 3))
        XCTAssertTrue(section.exists)

        step("A pick in the other window's session brings that window forward")
        XCTAssertFalse(element("tab.\(done.tab)", in: second).isSelected)
        rows.done.click()
        XCTAssertTrue(until(3) { app.windows.firstMatch.identifier == second.identifier }, "the other window in front")
        XCTAssertTrue(element("tab.\(done.tab)", in: second).has(\.isSelected, true, within: 3))
    }

    /// Opens the agents section in its agents view, and closes it after the test.
    func openAgents(in window: XCUIElement? = nil) {
        let section = element("agents.section", in: window)
        if !section.exists {
            element("sidebar.agents", in: window).click()
        }
        XCTAssertTrue(section.exists(within: 2))
        let back = element("agents.back", in: window)
        if back.exists {
            back.click()
        }
        XCTAssertTrue(element("agents.header", in: window).exists(within: 2))
        // Open in one window, it is open in every window on the machine: one click closes them all.
        addTeardownBlock { @MainActor [self] in
            if app.descendants(matching: .any).matching(identifier: "agents.section").firstMatch.exists {
                app.descendants(matching: .any).matching(identifier: "sidebar.agents").firstMatch.click()
            }
        }
    }

    /// The foot's buttons name their keys and open what those keys open.
    func testTheSidebarFootsButtonsOpenTheirPanels() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        // On the space rows' text column; as far over the window's bottom as under the open section.
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
        openAgents()
        let section = element("agents.section"), header = element("agents.header")
        XCTAssertEqual(section.frame.minX - window.frame.minX, 10, accuracy: 0.5, "\(section.frame)")
        XCTAssertEqual(section.frame.height, 408, accuracy: 0.5, "not five agents under three headers")
        XCTAssertEqual(summary.frame.minY - section.frame.maxY, 18, accuracy: 0.5, "the section over the foot")
        XCTAssertEqual(header.frame.minX - section.frame.minX, 12, accuracy: 0.5, "the title's inset")
        XCTAssertEqual(element("agents.archive").frame.minY - section.frame.minY, 6, accuracy: 0.5, "the top inset")
        // The header's 22 pt row, 4 pt, then the summary's 26 pt row.
        XCTAssertEqual(element("agents.summary").frame.midY - header.frame.midY, 28, accuracy: 0.5)
        XCTAssertEqual(element("agents.close").frame.maxX, section.frame.maxX - 6, accuracy: 0.5)
        XCTAssertEqual(element("sidebar.settings").frame.maxX, section.frame.maxX - 1.5, accuracy: 0.5)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(section.vanishes(within: 2))
        element("sidebar.settings").click()
        XCTAssertTrue(settingsWindow.exists(within: 3))
    }

    /// The section keeps its height and scrolls inside. Clear All on Done and a done row's × mark finishes seen, so
    /// those agents turn idle; an agent that needs you has neither. A group's fold stays.
    func testTheAgentsSectionScrollsFoldsAndClearsItsDoneAgents() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let summary = element("sidebar.agents"), section = element("agents.section")

        step("One agent needs you and 11 are done")
        var done: [String] = []
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
        openAgents()
        let header = element("agents.group.Done")
        XCTAssertTrue(header.has(\.stringValue, "11, expanded", within: 5), header.stringValue)
        XCTAssertEqual(element("agents.summary").stringValue, "1 needs you · 11 done")

        step("The list scrolls inside the section, which keeps its height")
        let prefix = "agents.row.\(one)."
        // Ids, not the bound elements: a removed row shifts their indexes.
        let rows = section.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        // The lazy list builds the rows in view only.
        let built = { rows.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }.map(\.identifier) }
        XCTAssertEqual(built().first, prefix + needs)
        XCTAssertEqual(section.frame.height, 408, accuracy: 0.5, "not five agents under three headers")
        keepScreenshot("agents section, 12 agents")
        section.scroll(byDeltaX: 0, deltaY: -3000)
        let first = element(prefix + needs)
        // Out of the list's view: above where the list starts, under the summary.
        let listTop = element("agents.summary").frame.maxY
        XCTAssertTrue(until(2) { !first.exists || first.frame.maxY <= listTop }, "the list did not scroll")
        let end = built().suffix(2)
        XCTAssertEqual(end.count, 2)
        let last = element(end.last ?? "")
        XCTAssertTrue(last.isHittable, "\(last.frame) in \(section.frame)")
        XCTAssertEqual(section.frame.maxY - last.frame.maxY, 6, accuracy: 0.5, "the last row's bottom inset")
        keepScreenshot("agents section, scrolled to the end")
        clearsDone(Array(end), needs: needs)
    }

    /// `end`: the section's last two rows, scrolled to the end; `needs` is the first row's.
    private func clearsDone(_ end: [String], needs: String) {
        let section = element("agents.section"), header = element("agents.group.Done")
        let prefix = "agents.row.\(one).", clearPrefix = "agents.clear.\(one)."
        let last = element(end[1]), clearLast = element(end[1].replacing(prefix, with: clearPrefix))
        step("A done row under the pointer shows its ×, which clears it")
        last.hover()
        XCTAssertTrue(clearLast.exists(within: 2), "no × on a done row under the pointer")
        // Its 16 pt box 6 pt in: its ink 10 pt from the row's edge, 4 pt more than the tile's.
        XCTAssertEqual(last.frame.maxX - clearLast.frame.maxX, 6, accuracy: 0.5)
        keepScreenshot("agents section, a done row under the pointer")
        clearLast.click()
        XCTAssertTrue(last.vanishes(within: 2))
        let summary = element("agents.summary")
        XCTAssertTrue(summary.has(\.stringValue, "1 needs you · 10 done · 1 idle", within: 2), summary.stringValue)
        // The lazy list's height is a guess: the row above need not land exactly under the resting pointer.
        element(end[0]).hover()
        XCTAssertTrue(element(end[0].replacing(prefix, with: clearPrefix)).exists(within: 2),
                      "the next done row under the pointer shows no ×")

        step("A row that needs you shows no ×")
        section.scroll(byDeltaX: 0, deltaY: 3000)
        let needsRow = element(prefix + needs)
        XCTAssertTrue(needsRow.has(\.isHittable, true, within: 2))
        XCTAssertEqual(needsRow.frame.minX - section.frame.minX, 6, accuracy: 0.5, "the rows' side inset")
        XCTAssertEqual(section.frame.maxX - needsRow.frame.maxX, 6, accuracy: 0.5, "the rows' side inset")
        needsRow.hover()
        XCTAssertFalse(element(clearPrefix + needs).exists(within: 1), "a × on a row that needs you")
        keepScreenshot("agents section, a row that needs you under the pointer")

        step("A group folds, and stays folded")
        let needsHeader = element("agents.group.Needs you")
        needsHeader.click()
        XCTAssertTrue(needsRow.vanishes(within: 2))
        XCTAssertEqual(needsHeader.stringValue, "1, collapsed")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(section.vanishes(within: 2))
        element("sidebar.agents").click()
        XCTAssertTrue(needsHeader.has(\.stringValue, "1, collapsed", within: 2))
        XCTAssertFalse(needsRow.exists)
        needsHeader.click()
        XCTAssertTrue(needsRow.exists(within: 2))

        step("Clear All is on Done only and clears every done agent")
        let all = section.descendants(matching: .any).matching(identifier: "agents.clearAll")
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.firstMatch.frame.midY, header.frame.midY, accuracy: 2)
        all.firstMatch.click()
        XCTAssertTrue(header.vanishes(within: 2))
        XCTAssertTrue(needsRow.exists)
        XCTAssertEqual(element("agents.summary").stringValue, "1 needs you · 11 idle")
        keepScreenshot("agents section, cleared")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(section.vanishes(within: 2))
        element("sidebar.agents").hover()
        let tip = element("tooltip")
        XCTAssertTrue(tip.has(\.stringValue, "1 needs you · 11 idle", within: 3), tip.stringValue)
    }
}
