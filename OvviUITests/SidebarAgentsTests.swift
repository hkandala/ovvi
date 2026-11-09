import XCTest

/// The sidebar's agents (ui/window#sidebar): under each space, unfolded at first, one line each, newest change first,
/// held still under the pointer, folded by the space's chevron; an untitled session's first prompt; Archived Sessions
/// and the page dots under the pages. Every status comes from `pane.report_agent` on a throwaway tab, closed after the
/// test (its agent goes with it).
extension OvviUITests {
    func testAWorkspaceUnfoldsToItsAgentsByTheirNewestChange() async throws {
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
        try await expectOrder([element("workspace.w1"), rows[2], rows[3], element("workspace.w2"), rows[0], rows[1]],
                              "newest change first, under each workspace")
        try await expect("the pane's name as the title") { rows[2].label.hasPrefix("fixer, alpha · ") }
        XCTAssertTrue(rows[3].label.hasPrefix("Untitled, alpha · "), rows[3].label)
        // One line, 28 pt; the tile on the names' edge (8 pt into the row).
        XCTAssertEqual(rows[0].frame.height, 28, accuracy: 0.5)
        XCTAssertEqual(rows[0].frame.minX - 4, element("workspace.w2").frame.minX, accuracy: 0.5)
        keepScreenshot("unfolded workspaces")

        // A change while the pointer rests on the rows: the box at once, the row stays; it moves once the pointer
        // leaves.
        rows[3].hover()
        try await report(idle, "working", agent: "pi")
        try await waitForValue("agent.\(idle)", containing: "Working")
        XCTAssertFalse(until(1.5) { rows[3].frame.minY < rows[2].frame.minY }, "moved under the pointer")
        element("sidebar.header").hover()
        try await expectOrder([rows[3], rows[2]], "the newest on top once the pointer left")

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
