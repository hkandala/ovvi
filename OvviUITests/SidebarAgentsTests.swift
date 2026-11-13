import XCTest

extension OvviUITests {
    func testAWorkspaceUnfoldsToItsAgentsByTabAndPlace() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let idle = try await newTab("review", in: "w1").pane
        try await report(idle, "idle", agent: "pi")
        // A split, not a fourth tab in w1: 220 pt tabs, and only 3 fit on CI's window.
        let working = try await split(idle)
        try await report(working, "working")
        try await Self.call(one, "pane.rename", ["pane_id": working, "label": "fixer"])
        let blocked = try await newTab("deploy").pane
        try await report(blocked, "blocked", agent: "claude")
        let docs = try await newTab("docs")
        try await report(docs.pane, "working")
        try await waitForValue("tab.\(docs.tab)", containing: "working")
        try await report(docs.pane, "idle")
        let done = docs.pane

        let rows = [done, blocked, working, idle].map { element("agent.\($0)") }
        XCTAssertTrue(element("fold.w2").exists(within: 3))
        XCTAssertEqual(element("fold.w2").value as? String, "expanded")
        XCTAssertEqual(element("fold.w1").value as? String, "expanded")
        try await expect("each row's state") {
            rows.map { $0.value as? String } == ["Done", "Needs you", "Working", "Idle"]
        }
        try await expectOrder([element("workspace.w1"), rows[3], rows[2], element("workspace.w2"), rows[1], rows[0]],
                              "by tab, then left to right, under each workspace")
        try await expect("the pane's name as the title") { rows[2].label.hasPrefix("fixer, alpha · ") }
        XCTAssertTrue(rows[3].label.hasPrefix("Untitled, alpha · "), rows[3].label)
        XCTAssertEqual(rows[0].frame.height, 28, accuracy: 0.5)
        XCTAssertEqual(rows[0].frame.minX - 4, element("workspace.w2").frame.minX, accuracy: 0.5)
        keepScreenshot("unfolded workspaces")

        try await report(working, "idle")
        try await waitForValue("agent.\(working)", containing: "Done")
        XCTAssertFalse(until(1) { rows[2].frame.minY < rows[3].frame.minY }, "the changed agent moved up")

        filter("beta", keeps: rows, [true, true, false, false])
        filter("fixer", keeps: rows, [false, false, true, false])
        fold("w1")
        XCTAssertTrue(rows[2].vanishes(within: 2))
        XCTAssertTrue(rows[0].exists)
        relaunch()
        XCTAssertTrue(rows[0].exists(within: connect))
        XCTAssertEqual(element("fold.w1").value as? String, "collapsed")
        XCTAssertFalse(rows[2].exists)
    }

    func testRecentPutsTheSpaceWhoseAgentChangedLastFirst() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let alpha = try await newTab("recent-a", in: "w1").pane, beta = try await newTab("recent-b", in: "w2").pane
        try await report(alpha, "working", agent: "pi")
        try await report(beta, "working", agent: "pi")
        let alphaRow = element("workspace.w1"), betaRow = element("workspace.w2"), sort = element("sidebar.sort")
        try await waitForValue("agent.\(beta)", containing: "Working")
        XCTAssertEqual(sort.value as? String, "Manual")
        let plus = element("sidebar.new-workspace").frame
        XCTAssertEqual(sort.frame.size, plus.size)
        XCTAssertEqual(sort.frame.maxX, plus.minX, accuracy: 0.5)
        XCTAssertEqual(sort.frame.midY, plus.midY, accuracy: 0.5)
        addTeardownBlock { @MainActor in
            if sort.value as? String == "Recent" {
                sort.click()
                sort.menuItems["Manual"].click()
            }
        }
        // In Manual the pointer over the list holds that order; the menu's Recent item puts it back there.
        betaRow.hover()
        sort.click()
        keepScreenshot("sort menu")
        sort.menuItems["Recent"].click()
        try await expectOrder([betaRow, alphaRow], "beta's agent changed last")

        betaRow.hover()
        try await report(alpha, "idle", agent: "pi")
        try await waitForValue("agent.\(alpha)", containing: "Done")
        XCTAssertFalse(until(1) { alphaRow.frame.minY < betaRow.frame.minY }, "moved under the pointer")
        element("sidebar.header").hover()
        try await expectOrder([alphaRow, betaRow], "alpha's finish on top once the pointer left")

        try await report(beta, "blocked", agent: "pi")
        try await expectOrder([betaRow, alphaRow], "beta needs you")
        element("agent.\(alpha)").click()
        betaRow.click()
        try await waitForValue("agent.\(alpha)", containing: "Idle")
        element("sidebar.header").hover()
        XCTAssertFalse(until(2.5) { alphaRow.frame.minY < betaRow.frame.minY }, "a look moved alpha's space up")
        try await dragsOnlyInManual(alphaRow, betaRow, sort)
    }

    func testSpaceKeysFollowTheSidebarsRecentOrder() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let alpha = try await newTab("keys-a", in: "w1").pane, beta = try await newTab("keys-b", in: "w2").pane
        let created = try await createWorkspace("keys-c")
        // Recent: gamma, beta, alpha; herdr's order: alpha, beta, gamma.
        for pane in [alpha, beta, created.pane] {
            try await report(pane, "working", agent: "pi")
        }
        let alphaRow = element("workspace.w1"), betaRow = element("workspace.w2")
        let gammaRow = element("workspace.\(workspace(of: created.tab))"), sort = element("sidebar.sort")
        try await waitForValue("agent.\(created.pane)", containing: "Working")
        addTeardownBlock { @MainActor in
            if sort.value as? String == "Recent" {
                sort.click()
                sort.menuItems["Manual"].click()
            }
        }
        sort.click()
        sort.menuItems["Recent"].click()
        element("sidebar.header").hover()
        try await expectOrder([gammaRow, betaRow, alphaRow], "gamma's agent changed last")
        alphaRow.click()
        XCTAssertTrue(alphaRow.has(\.isSelected, true, within: 2))
        for (key, row) in [("]", gammaRow), ("]", betaRow), ("[", gammaRow), ("[", alphaRow), ("1", gammaRow)] {
            app.typeKey(key, modifierFlags: [.command, .control])
            XCTAssertTrue(row.has(\.isSelected, true, within: 2), "⌃⌘\(key) to \(row.identifier)")
        }

        // Held under the pointer, the keys keep the order shown.
        betaRow.hover()
        try await report(alpha, "idle", agent: "pi")
        try await waitForValue("agent.\(alpha)", containing: "Done")
        app.typeKey("3", modifierFlags: [.command, .control])
        XCTAssertTrue(alphaRow.has(\.isSelected, true, within: 2), "⌃⌘3 during the hold")
        XCTAssertLessThan(betaRow.frame.minY, alphaRow.frame.minY, "moved under the pointer")
        element("sidebar.header").hover()
        try await expectOrder([alphaRow, gammaRow, betaRow], "alpha's finish on top once the pointer left")
        app.typeKey("2", modifierFlags: [.command, .control])
        XCTAssertTrue(gammaRow.has(\.isSelected, true, within: 2), "⌃⌘2 after the hold")
    }

    private func dragsOnlyInManual(_ alphaRow: XCUIElement, _ betaRow: XCUIElement,
                                   _ sort: XCUIElement) async throws
    {
        let gamma = try await workspace(of: createWorkspace("recent-c").tab), gammaRow = element("workspace.\(gamma)")
        try await expectOrder([betaRow, alphaRow, gammaRow], "the space with no agent last")
        // Among the unpinned ones, clear of the pin region on top.
        let before = try await workspaceIDs()
        during(gammaRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: alphaRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await Task.sleep(for: .seconds(1))
        let after = try await workspaceIDs()
        XCTAssertEqual(after, before, "a drag reordered in Recent")
        alphaRow.rightClick()
        XCTAssertFalse(app.menuItems["Move Up"].isEnabled)
        XCTAssertFalse(app.menuItems["Move Down"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        sort.click()
        sort.menuItems["Manual"].click()
        try await expectOrder([alphaRow, betaRow], "herdr's order")
        XCTAssertEqual(sort.value as? String, "Manual")
        // Above beta's middle once the pin region pushed it 40 pt down.
        during(gammaRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: betaRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(
                   dx: 0,
                   dy: 20,
               )))
        try await expect("the space with no agent before beta's in Manual") {
            try await workspaceIDs().suffix(2) == [gamma, "w2"]
        }
    }

    func testArchivedSessionsAndTheDotsStayUnderThePages() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let shelf = element("agents.shelf.Archived Sessions")
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        openPage(two)
        let dots = [one, two].map { element("sidebar.dot.\($0)") }
        XCTAssertTrue(dots[1].has(\.isSelected, true, within: 2))
        XCTAssertLessThan(dots[1].frame.maxY, shelf.frame.minY)
        // A failed run may have left it open.
        if shelf.value as? String == "expanded" {
            shelf.click()
        }
        XCTAssertTrue(shelf.has(\.stringValue, "collapsed", within: 2))
        let place = shelf.frame
        shelf.click()
        addTeardownBlock { @MainActor [self] in
            let shelf = element("agents.shelf.Archived Sessions")
            if shelf.exists, shelf.value as? String == "expanded" {
                shelf.click()
            }
        }
        XCTAssertTrue(element("agents.archived.search").exists(within: 2))
        XCTAssertTrue(element("agents.archived.filter").exists)
        dots[0].click()
        XCTAssertTrue(until(3) { header == one })
        XCTAssertEqual(shelf.value as? String, "expanded")
        XCTAssertTrue(element("agents.archived.search").exists)
        keepScreenshot("dots and Archived Sessions")
        relaunch()
        XCTAssertTrue(shelf.has(\.stringValue, "expanded", within: connect))
        shelf.click()
        XCTAssertTrue(shelf.has(\.stringValue, "collapsed", within: 2))
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        XCTAssertTrue(until(2) { shelf.frame == place }, "\(shelf.frame) \(place)")
    }

    func testAnUntitledAgentShowsItsFirstPrompt() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, pane) = try await newTab("prompt")
        try await waitForPrompt(pane)
        let prompt = "find why the drop indicator lands one slot to the right when a tab comes in from another "
            + "workspace and waits over the gap"
        let id = UUID().uuidString.lowercased(), dir = "\(Self.archivedHome)/.claude/projects/prompt"
        let line = #"{"type":"user","message":{"role":"user","content":"\#(prompt)"},"sessionId":"\#(id)"}"#
        try await send(
            "mkdir -p \(dir) && echo \(Data(line.utf8).base64EncodedString()) | base64 -d >\(dir)/\(id).jsonl "
                + "&& clear && echo ready-$((6*7))\r",
            to: pane,
        )
        try await waitFor(pane) { $0.contains("ready-42") }
        // Teardown blocks run last first: this one runs ahead of the tab's close.
        addTeardownBlock { @MainActor [self] in try? await send("rm -rf \(dir)\r", to: pane) }
        // The state ahead of the session: herdr takes no state report after it.
        try await report(pane, "working", agent: "claude")
        try await Self.call(one, "pane.report_agent_session", ["pane_id": pane, "source": "herdr:claude",
                                                               "agent": "claude", "agent_session_id": id])
        unfold("w2")
        let row = element("agent.\(pane)")
        let cut = "find why the drop indicator lands one slot to the right when a tab comes in from another "
            + "workspace a…"
        try await expect("the first prompt as the title") { row.label.hasPrefix("\(cut), beta · ") }
        keepScreenshot("untitled agent's first prompt")
    }

    /// A fold from a failed run stays in the tests' defaults.
    func unfold(_ workspace: String) {
        let fold = element("fold.\(workspace)")
        XCTAssertTrue(fold.exists(within: 3))
        if fold.value as? String == "collapsed" {
            fold.click()
        }
        XCTAssertTrue(fold.has(\.stringValue, "expanded", within: 2))
    }

    /// Unfolds them again after the test: the tests' defaults keep the folds.
    func fold(_ workspace: String) {
        let fold = element("fold.\(workspace)")
        XCTAssertTrue(fold.exists(within: 3))
        if fold.value as? String == "expanded" {
            fold.click()
        }
        XCTAssertTrue(fold.has(\.stringValue, "collapsed", within: 2))
        addTeardownBlock { @MainActor [self] in
            let fold = element("fold.\(workspace)")
            if fold.exists, fold.value as? String == "collapsed" {
                fold.click()
            }
        }
    }

    func expectOrder(_ rows: [XCUIElement], _ what: String) async throws {
        try await expect(what) {
            guard rows.allSatisfy(\.exists) else { return false }
            let tops = rows.map(\.frame.minY)
            return tops == tops.sorted() && Set(tops).count == tops.count
        }
    }

    private func filter(_ text: String, keeps rows: [XCUIElement], _ kept: [Bool]) {
        element("sidebar.filter").click()
        element("sidebar.filter").typeText(text)
        XCTAssertTrue(until(2) { rows.map(\.exists) == kept }, text)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(until(2) { rows.allSatisfy(\.exists) }, text)
    }
}
