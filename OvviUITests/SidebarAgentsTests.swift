import XCTest

/// The sidebar's agents (ui/window#sidebar): under each space, unfolded at first, one line each, by tab and place in
/// the tab, folded by the space's chevron; the spaces' Recent order, held still under the pointer; an untitled
/// session's first prompt; Archived Sessions
/// and the page dots under the pages. Every status comes from `pane.report_agent` on a throwaway tab, closed after the
/// test (its agent goes with it).
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

        // Unfolded at first: the agent rows under a chevron on each space that runs agents.
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
        // One line, 28 pt; the tile on the names' edge (8 pt into the row).
        XCTAssertEqual(rows[0].frame.height, 28, accuracy: 0.5)
        XCTAssertEqual(rows[0].frame.minX - 4, element("workspace.w2").frame.minX, accuracy: 0.5)
        keepScreenshot("unfolded workspaces")

        // A change never moves an agent.
        try await report(working, "idle")
        try await waitForValue("agent.\(working)", containing: "Done")
        XCTAssertFalse(until(1.5) { rows[2].frame.minY < rows[3].frame.minY }, "the changed agent moved up")

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

    /// Recent: the space whose agent changed state last first (a start, a finish, a need), held still under the
    /// pointer; a look at a finish is no change. No row drags or moves in Recent; Manual is herdr's order again.
    func testRecentPutsTheSpaceWhoseAgentChangedLastFirst() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let alpha = try await newTab("recent-a", in: "w1").pane, beta = try await newTab("recent-b", in: "w2").pane
        try await report(alpha, "working", agent: "pi")
        try await report(beta, "working", agent: "pi")
        let alphaRow = element("workspace.w1"), betaRow = element("workspace.w2"), sort = element("sidebar.sort")
        try await waitForValue("agent.\(beta)", containing: "Working")
        XCTAssertEqual(sort.value as? String, "Manual")
        addTeardownBlock { @MainActor in
            if sort.value as? String == "Recent" {
                sort.click()
                sort.menuItems["Manual"].click()
            }
        }
        sort.click()
        keepScreenshot("sort menu")
        sort.menuItems["Recent"].click()
        try await expectOrder([betaRow, alphaRow], "beta's agent changed last")

        // Under the pointer the rows hold still; they move once it leaves.
        betaRow.hover()
        try await report(alpha, "idle", agent: "pi")
        try await waitForValue("agent.\(alpha)", containing: "Done")
        XCTAssertFalse(until(1.5) { alphaRow.frame.minY < betaRow.frame.minY }, "moved under the pointer")
        element("sidebar.header").hover()
        try await expectOrder([alphaRow, betaRow], "alpha's finish on top once the pointer left")

        // A look at the finish (its Done cleared once left) moves nothing.
        try await report(beta, "blocked", agent: "pi")
        try await expectOrder([betaRow, alphaRow], "beta needs you")
        element("agent.\(alpha)").click()
        betaRow.click()
        try await waitForValue("agent.\(alpha)", containing: "Idle")
        element("sidebar.header").hover()
        XCTAssertFalse(until(2.5) { alphaRow.frame.minY < betaRow.frame.minY }, "a look moved alpha's space up")

        // No reorder: a space with no agent, last, dragged to the top leaves herdr's order; no Move Up or Down.
        let gamma = try await workspace(of: createWorkspace("recent-c").tab), gammaRow = element("workspace.\(gamma)")
        try await expectOrder([betaRow, alphaRow, gammaRow], "the space with no agent last")
        let before = try await workspaceIDs()
        during(gammaRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: betaRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        try await Task.sleep(for: .seconds(1))
        let after = try await workspaceIDs()
        XCTAssertEqual(after, before, "a drag reordered in Recent")
        // Neither end in herdr's order or on screen.
        alphaRow.rightClick()
        XCTAssertFalse(app.menuItems["Move Up"].isEnabled)
        XCTAssertFalse(app.menuItems["Move Down"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        sort.click()
        sort.menuItems["Manual"].click()
        try await expectOrder([alphaRow, betaRow], "herdr's order")
        XCTAssertEqual(sort.value as? String, "Manual")
    }

    /// With two pages, the dots show under them, then Archived Sessions, which keeps its place and its fold (it is the
    /// machine's) as the pages change, and over a relaunch; open, its search field and menu.
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
        // One page now: no dots; the shelf stays on the footer, where it was.
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        XCTAssertTrue(until(2) { shelf.frame == place }, "\(shelf.frame) \(place)")
    }

    /// An untitled Claude Code session (its transcript in the tests' fixture home, `-archivedHome`): its row shows its
    /// first prompt, cut at 100 characters with "…".
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
        // Before the tab closes (teardown blocks run last first).
        addTeardownBlock { @MainActor [self] in try? await send("rm -rf \(dir)\r", to: pane) }
        // The state before the session: herdr takes no state report after it.
        try await report(pane, "working", agent: "claude")
        try await Self.call(one, "pane.report_agent_session", ["pane_id": pane, "source": "herdr:claude",
                                                               "agent": "claude", "agent_session_id": id])
        unfold("w2")
        let row = element("agent.\(pane)")
        let cut = String(prompt.prefix(100)).trimmingCharacters(in: .whitespaces) + "…"
        try await expect("the first prompt as the title") { row.label.hasPrefix("\(cut), beta · ") }
        keepScreenshot("untitled agent's first prompt")
    }

    /// The space's agents shown (spaces start unfolded; a fold from a failed run stays in the tests' defaults).
    func unfold(_ workspace: String) {
        let fold = element("fold.\(workspace)")
        XCTAssertTrue(fold.exists(within: 3))
        if fold.value as? String == "collapsed" {
            fold.click()
        }
        XCTAssertTrue(fold.has(\.stringValue, "expanded", within: 2))
    }

    /// Folds the space's agents; unfolds them again after the test (the tests' defaults keep the folds).
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

    private func expectOrder(_ rows: [XCUIElement], _ what: String) async throws {
        try await expect(what) {
            guard rows.allSatisfy(\.exists) else { return false }
            let tops = rows.map(\.frame.minY)
            return tops == tops.sorted() && Set(tops).count == tops.count
        }
    }
}
