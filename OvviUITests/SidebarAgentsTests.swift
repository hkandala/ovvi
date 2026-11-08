import XCTest

/// The sidebar's agents (ui/window#sidebar): a workspace's chevron unfolds them, one line each, newest change first,
/// held still under the pointer; pinned tabs on top; an untitled session's first prompt. Every status comes from
/// `pane.report_agent` on a throwaway tab, closed after the test (its agent goes with it).
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

        // Folded at first: no agent rows, a chevron on each workspace that runs agents.
        let rows = [done, blocked, working, idle].map { element("agent.\($0)") }
        XCTAssertTrue(element("fold.w2").exists(within: 3))
        XCTAssertEqual(element("fold.w2").value as? String, "collapsed")
        XCTAssertFalse(rows[0].exists)
        unfold("w2")
        unfold("w1")
        try await expect("each row's state") {
            rows.map { $0.value as? String } == ["Done", "Needs you", "Working", "Idle"]
        }
        // Each workspace's agents under its row, newest change first.
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
        // The chevron folds them away again.
        element("fold.w1").click()
        XCTAssertTrue(rows[2].vanishes(within: 2))
        XCTAssertTrue(rows[0].exists)
    }

    /// Pin from the tab's hover button or its menu: the tab's row goes on top of the sidebar, stays over a relaunch,
    /// and shows its tab; Unpin from the row's hover button or the tab's menu.
    func testAPinnedTabStaysOnTop() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, _) = try await newTab("deploy")
        let pinned = element("pinned.\(tab)")
        XCTAssertFalse(element("sidebar.pinned").exists)
        element("tab.\(tab)").hover()
        element("tab.\(tab).pin").click()
        XCTAssertTrue(pinned.exists(within: 2))
        XCTAssertLessThan(pinned.frame.maxY, element("workspace.w1").frame.minY)
        XCTAssertEqual(pinned.label, "deploy, beta")
        keepScreenshot("pinned tab")
        relaunch()
        XCTAssertTrue(pinned.exists(within: connect))
        element("workspace.w1").click()
        XCTAssertTrue(element("tab.\(tab)").vanishes(within: 2))
        pinned.click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(pinned.has(\.isSelected, true, within: 2))
        pinned.hover()
        element("pinned.\(tab).unpin").click()
        XCTAssertTrue(pinned.vanishes(within: 2))
        XCTAssertFalse(element("sidebar.pinned").exists)

        element("tab.\(tab)").rightClick()
        app.menus.menuItems["Pin Tab"].firstMatch.click()
        XCTAssertTrue(pinned.exists(within: 2))
        element("tab.\(tab)").rightClick()
        app.menus.menuItems["Unpin Tab"].firstMatch.click()
        XCTAssertTrue(pinned.vanishes(within: 2))
    }

    /// An untitled pi session: its row shows its first prompt, cut at 100 characters with "…"; the hover card has it
    /// whole.
    func testAnUntitledAgentShowsItsFirstPrompt() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, pane) = try await newTab("prompt")
        try await waitForPrompt(pane)
        let prompt = "find why the drop indicator lands one slot to the right when a tab comes in from another "
            + "workspace and waits over the gap"
        // In the tests' config folder, which the next run removes.
        let file = "/tmp/ovvi-e2e-no-config/prompt-\(UUID().uuidString.prefix(8)).jsonl"
        let lines = [#"{"type":"session","version":3,"cwd":"/tmp"}"#,
                     #"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"\#(prompt)"}]}}"#]
        try await send("echo \(Data(lines.joined(separator: "\n").utf8).base64EncodedString()) | base64 -d >\(file) && "
            + "clear && echo ready-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("ready-42") }
        try await report(pane, "idle", agent: "pi")
        try await Self.call(one, "pane.report_agent_session", ["pane_id": pane, "source": "ovvi-e2e", "agent": "pi",
                                                               "agent_session_path": file])
        try await report(pane, "working", agent: "pi")
        unfold("w2")
        let row = element("agent.\(pane)")
        let cut = String(prompt.prefix(100)).trimmingCharacters(in: .whitespaces) + "…"
        try await expect("the first prompt as the title") { row.label.hasPrefix("\(cut), beta · ") }
        keepScreenshot("untitled agent's first prompt")
    }

    /// Unfolds the workspace's agents; folds them back after the test (the tests' defaults keep the folds).
    func unfold(_ workspace: String) {
        let fold = element("fold.\(workspace)")
        XCTAssertTrue(fold.exists(within: 3))
        if fold.value as? String == "collapsed" {
            fold.click()
        }
        XCTAssertTrue(fold.has(\.stringValue, "expanded", within: 2))
        addTeardownBlock { @MainActor [self] in
            let fold = element("fold.\(workspace)")
            if fold.exists, fold.value as? String == "expanded" {
                fold.click()
            }
        }
    }

    /// The rows' tops are in this order.
    private func expectOrder(_ rows: [XCUIElement], _ what: String) async throws {
        try await expect(what) {
            guard rows.allSatisfy(\.exists) else { return false }
            let tops = rows.map(\.frame.minY)
            return tops == tops.sorted() && Set(tops).count == tops.count
        }
    }
}
