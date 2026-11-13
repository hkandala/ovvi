import XCTest

extension OvviUITests {
    func testDropOnACardsCenterSwapsAndOnItsEdgePlacesBeside() async throws {
        let (tabs, first) = try await newWorkspace("swap")
        let tab = tabs[0]
        let second = try await split(first), third = try await split(second)
        restoreHerdrFocusAfter()
        let over = try await createTab(in: workspace(of: tab), label: "over").tab
        XCTAssertTrue(element("tab.\(over)").has(\.isHittable, true, within: 5))
        element("tab.\(over)").click()
        XCTAssertTrue(element("page.\(over)").exists(within: 5))
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(third)").exists(within: 3))

        drag(first, to: card(second, 0.5, 0.6))
        try await expect("the two swapped") { try await order(tab) == [second, first, third] }
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        // Writes go one at a time, so the drop below checks that nothing moved.
        let before = try await tabIDs()
        drag(third, to: element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertFalse(element("detail.notice").exists(within: 1))

        drag(third, to: card(second, 0.1, 0.6))
        try await expect("the pane left of its neighbor") { try await order(tab) == [third, second, first] }
        let after = try await tabIDs()
        XCTAssertEqual(after, before)
        XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected })
        XCTAssertTrue(hasKeyboard("terminal.\(third)"))
        try await expectWidths(tab, [third: 1 / 3, second: 1 / 3, first: 1 / 3])
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testHoldingOverACapsuleSpringLoadsItsTabAndADropSplitsRight() async throws {
        let (tabs, first) = try await newWorkspace("spring")
        let tab = tabs[0]
        let second = try await split(first)
        let (other, third) = try await createTab(in: workspace(of: tab), label: "other")
        let capsule = element("tab.\(other)")
        XCTAssertTrue(capsule.exists(within: 3))
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))

        // A herdr TUI zoomed that tab: herdr refuses the move (`zoomed_tab`), so only the spring-load selects it.
        // herdr zooms only a tab with two panes or more, and its zoom moves its focus, as a swap does.
        let fourth = try await split(third)
        restoreHerdrFocusAfter()
        try await Self.call(one, "pane.zoom", ["pane_id": third, "mode": "on"])
        try await press(second, over: capsule)
        // Released ahead of any assertion that stops the test.
        let sprung = capsule.has(\.isSelected, true, within: 2)
            && element("pane.\(third)").has(\.isHittable, true, within: 2)
        try await release()
        XCTAssertTrue(sprung)
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts["The tab is zoomed in herdr"].exists(within: 3))
        XCTAssertEqual(notice.images["notice.symbol"].label, "Error")
        keepScreenshot("notice")
        notice.buttons["notice.close"].click()
        XCTAssertTrue(notice.vanishes(within: 2))
        let still = try await order(tab)
        XCTAssertEqual(still, [first, second])

        XCTAssertTrue(element("pane.\(third)").exists(within: 3))
        let betaTab = try await tabIDs().first { workspace(of: $0) == "w2" } ?? "none"
        try await press(third, over: element("workspace.w2"))
        let opened = element("workspace.w2").has(\.isSelected, true, within: 2)
            && element("tab.\(betaTab)").exists(within: 2)
        try await release()
        XCTAssertTrue(opened)
        XCTAssertTrue(notice.staticTexts["The tab is zoomed in herdr"].exists(within: 3))
        notice.buttons["notice.close"].click()
        XCTAssertTrue(notice.vanishes(within: 2))
        let unmoved = try await order(other)
        XCTAssertEqual(unmoved, [third, fourth])

        try await Self.call(one, "pane.zoom", ["pane_id": third, "mode": "off"])
        element("workspace.\(workspace(of: tab))").click()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))
        drag(second, to: capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await expect("the pane split right in that tab") { try await order(other) == [third, fourth, second] }
        XCTAssertTrue(capsule.has(\.isSelected, true, within: 2))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testDropsOnTheTrackEndARowTheSidebarAndItsPlusMoveThePane() async throws {
        let (tabs, first) = try await newWorkspace("moves")
        let tab = tabs[0]
        let second = try await split(first)
        let terminal = try await terminalID(second)
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))

        let end = element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 80, dy: 0))
        drag(second, to: end)
        let moved = try await poll("the pane in a new tab") { () async throws -> String? in
            let place = try await place(of: terminal)
            return place.map { $0.tab != tab && workspace(of: $0.tab) == workspace(of: tab) } == true ? place?.tab : nil
        }
        XCTAssertTrue(element("tab.\(moved)").has(\.isSelected, true, within: 3))

        let betaTabs = try await tabIDs().filter { $0.hasPrefix("w2:") }
        try await closeNew("tab", besides: tabIDs())
        drag(second, to: element("workspace.w2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
             hold: 0.3)
        let inBeta = try await poll("the pane in a new tab of beta") { () async throws -> String? in
            let place = try await place(of: terminal)
            return place.map { $0.tab.hasPrefix("w2:") && !betaTabs.contains($0.tab) } == true ? place?.pane : nil
        }
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        let workspaces = try await workspaceIDs()
        closeNew("workspace", besides: workspaces)
        XCTAssertTrue(element("pane.\(inBeta)").exists(within: 3))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.w'"))
        let bottom = rows.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0
        let sidebar = element("sidebar")
        drag(inBeta, to: sidebar.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: sidebar.frame.width / 2, dy: bottom + 40 - sidebar.frame.minY)))
        let away = try await poll("the pane in a new workspace") { () async throws -> String? in
            let place = try await place(of: terminal)
            return place.map { !workspaces.contains(workspace(of: $0.tab)) } == true ? place?.pane : nil
        }
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        let before = try await workspaceIDs()
        XCTAssertTrue(element("pane.\(away)").exists(within: 3))
        drag(away, to: element("sidebar.new-workspace").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await expect("the pane in another new workspace") {
            let place = try await place(of: terminal)
            return place.map { !before.contains(workspace(of: $0.tab)) } == true
        }
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testDropsOnTopAndBottomEdgesStackThePanesAndOnThePlusMakeATab() async throws {
        let (tabs, first) = try await newWorkspace("edges")
        let tab = tabs[0], second = try await split(first)
        restoreHerdrFocusAfter()
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))
        drag(first, to: card(second, 0.5, 0.9))
        try await expectStack(tab, [second, first])
        drag(first, to: card(second, 0.5, 0.15))
        try await expectStack(tab, [first, second])

        let terminal = try await terminalID(second)
        drag(second, to: element("titlebar.new-tab").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await expect("the pane in a new tab of its workspace") {
            try await place(of: terminal).map { $0.tab != tab && workspace(of: $0.tab) == workspace(of: tab) } == true
        }
    }

    func testDraggingTheThirdCapsuleFirstReordersHerdrsTabs() async throws {
        relaunch(one, ["-forceMotion", "YES"]) // the drop's glide too (CI has Reduce Motion on)
        let tabs = try await newWorkspace("tabs", tabs: 3).tabs
        let third = element("tab.\(tabs[2])")
        let from = third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = element("tab.\(tabs[0])").coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        during(from, to: target)
        try await expect("herdr's tab order") {
            try await tabIDs().filter { $0.hasPrefix("\(workspace(of: tabs[0])):") } == [tabs[2], tabs[0], tabs[1]]
        }
        during(element("tab.\(tabs[2])").coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
               to: element("tab.\(tabs[0])").coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertFalse(element("tab.\(tabs[2]).close").exists, "the dropped tab kept the hover")
        XCTAssertTrue(element("tab.\(tabs[1]).close").exists(within: 1))
        try await expect("herdr's tab order") {
            try await tabIDs().filter { $0.hasPrefix("\(workspace(of: tabs[0])):") } == [tabs[0], tabs[1], tabs[2]]
        }
    }

    func testDraggingATabOntoAWorkspaceRowOrMenuRowMovesItWithItsLayout() async throws {
        step("A tab onto its own space's row stays, onto another space's row moves")
        let (tab, terminal) = try await movingTab(), layout = try await terminalLayout(tab)
        let home = workspace(of: tab)
        let capsule = element("tab.\(tab)")
        XCTAssertTrue(capsule.has(\.isHittable, true, within: 3))

        during(capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: element("workspace.\(home)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertFalse(element("detail.notice").exists(within: 1))
        let stayed = try await place(of: terminal)?.tab
        XCTAssertEqual(stayed, tab)
        during(capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: element("workspace.w2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let moved = try await movedTab(of: terminal, layout) { $0 == "w2" }
        let after = try await tabIDs()
        XCTAssertFalse(after.contains(tab))
        XCTAssertTrue(element("tab.\(moved)").has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 3))
        let inBeta = try await place(of: terminal)
        let keyboard = try XCTUnwrap(inBeta).pane
        XCTAssertTrue(hasKeyboard("terminal.\(keyboard)"))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        step("With the sidebar hidden: onto a space in the workspace menu")
        element("titlebar.sidebar").click()
        let row = try await dragThroughWorkspaceMenu(moved, onto: "workspaces.\(one).\(home)")
        let back = try await movedTab(of: terminal, layout) { $0 == home }
        XCTAssertTrue(row.vanishes(within: 2))
        XCTAssertTrue(element("tab.\(back)").has(\.isSelected, true, within: 3))
        let arrived = try await place(of: terminal)
        XCTAssertTrue(try hasKeyboard("terminal.\(XCTUnwrap(arrived).pane)"))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        try await toNewWorkspaces(back, terminal, layout)
    }

    /// Through the workspace menu with the sidebar hidden, then onto the empty sidebar under the rows.
    private func toNewWorkspaces(_ back: String, _ terminal: String, _ layout: String) async throws {
        step("With the sidebar hidden: onto the workspace menu's New Workspace")
        let workspaces = try await workspaceIDs()
        closeNew("workspace", besides: workspaces)
        XCTAssertTrue(element("tab.\(back)").has(\.isHittable, true, within: 3))
        let newRow = try await dragThroughWorkspaceMenu(back, onto: "workspaces.new")
        let away = try await movedTab(of: terminal, layout) { !workspaces.contains($0) }
        XCTAssertTrue(newRow.vanishes(within: 2))
        XCTAssertTrue(element("tab.\(away)").has(\.isSelected, true, within: 3))
        let landed = try await place(of: terminal)
        XCTAssertTrue(try hasKeyboard("terminal.\(XCTUnwrap(landed).pane)"))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        step("Onto the empty sidebar under the rows: a new space")
        element("titlebar.sidebar").click()
        let made = workspace(of: away)
        XCTAssertTrue(element("workspace.\(made)").exists(within: 3))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.w'"))
        let bottom = rows.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0
        let sidebar = element("sidebar")
        during(element("tab.\(away)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: sidebar.coordinate(withNormalizedOffset: .zero)
                   .withOffset(CGVector(dx: sidebar.frame.width / 2, dy: bottom + 40 - sidebar.frame.minY)))
        let last = try await movedTab(of: terminal, layout) { !workspaces.contains($0) && $0 != made }
        XCTAssertTrue(element("tab.\(last)").has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("workspace.\(made)").vanishes(within: 3))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testDraggingWorkspaceRowsReordersThemAndAWorktreeMovesWithItsRepository() async throws {
        let (tabs, pane) = try await newWorkspace("first")
        let first = workspace(of: tabs[0]), second = try await workspace(of: createWorkspace("second").tab)
        let firstRow = element("workspace.\(first)"), secondRow = element("workspace.\(second)")
        XCTAssertTrue(secondRow.exists(within: 3))

        // Past the last row: the pin region pushes the rows down by 40 pt while a space is dragged.
        during(firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(
                   dx: 0,
                   dy: 45,
               )))
        try await expect("first below second") { try await workspaceIDs().suffix(2) == [second, first] }

        let root = "/tmp/ovvi-e2e-drag-\(Int.random(in: 10000 ... 99999))"
        try await send("(mkdir -p \(root) && cd \(root) && git init -q -b main repo && cd repo && "
            + "git -c user.name=e2e -c user.email=e2e@ovvi commit -q --allow-empty -m one && "
            + "git worktree add -q ../tree -b feature) && echo built-$((6*7))\r", to: pane)
        // Teardowns run last first: this one runs ahead of the workspace's close.
        sendAfter("rm -rf \(root)\r", to: pane)
        try await waitFor(pane) { $0.contains("\nbuilt-42") }
        let repo = try await workspace(of: createWorkspace("repo", cwd: "\(root)/repo").tab)
        let tree = try await id(Self.call(one, "worktree.open", ["workspace_id": repo, "path": "\(root)/tree",
                                                                 "focus": false]), "workspace")
        closeAfter("workspace", tree)
        let repoRow = element("workspace.\(repo)")
        XCTAssertTrue(element("workspace.\(tree)").exists(within: 3))
        // Above second's middle once the pin region pushed it 40 pt down.
        during(repoRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(
                   dx: 0,
                   dy: 20,
               )))
        try await expect("the repository and its worktree before second") {
            try await workspaceIDs().suffix(4) == [repo, tree, second, first]
        }
    }

    func place(of terminal: String) async throws -> (pane: String, tab: String)? {
        let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
        return panes.first { $0["terminal_id"] as? String == terminal }.flatMap { pane in
            guard let id = pane["pane_id"] as? String, let tab = pane["tab_id"] as? String else { return nil }
            return (id, tab)
        }
    }

    /// By terminal: a move to another workspace gives the panes new ids.
    private func terminalLayout(_ tab: String) async throws -> String {
        let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
        func text(_ node: [String: Any]) -> String {
            if let id = node["pane_id"] as? String {
                return panes.first { $0["pane_id"] as? String == id }?["terminal_id"] as? String ?? id
            }
            let ratio = (node["ratio"] as? Double).map { String(format: "%.2f", $0) } ?? "?"
            return "\(node["direction"] ?? "?") \(ratio) (\(text(node["first"] as? [String: Any] ?? [:])), "
                + "\(text(node["second"] as? [String: Any] ?? [:])))"
        }
        return try await text(root(tab))
    }

    private func movingTab() async throws -> (tab: String, terminal: String) {
        let (tabs, first) = try await newWorkspace("tabs", tabs: 2)
        let tab = tabs[0], second = try await split(first), third = try await split(second, "down")
        // The app evens another client's new pane once a snapshot shows it, the ratios set by then too.
        XCTAssertTrue(element("pane.\(third)").exists(within: 5))
        try await Self.call(one, "layout.set_split_ratio", ["tab_id": tab, "path": [Bool](), "ratio": 0.3])
        try await Self.call(one, "layout.set_split_ratio", ["tab_id": tab, "path": [true], "ratio": 0.7])
        try await Self.call(one, "tab.rename", ["tab_id": tab, "label": "moving"])
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        return try await (tab, terminalID(first))
    }

    private func movedTab(of terminal: String, _ layout: String, in found: (String) -> Bool) async throws -> String {
        try await poll("the tab moved as it was") { () async throws -> String? in
            guard let tab = try await place(of: terminal)?.tab, found(self.workspace(of: tab)) else { return nil }
            let tabs = try await snapshot()["tabs"] as? [[String: Any]] ?? []
            let same = try await terminalLayout(tab) == layout
            return same && tabs.first { $0["tab_id"] as? String == tab }?["label"] as? String == "moving" ? tab : nil
        }
    }

    private func dragThroughWorkspaceMenu(_ tab: String, onto id: String) async throws -> XCUIElement {
        let button = element("titlebar.workspace")
        XCTAssertTrue(button.has(\.isHittable, true, within: 3))
        button.click()
        let row = element(id)
        XCTAssertTrue(row.exists(within: 2))
        let target = row.frame
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(row.vanishes(within: 2))
        let from = element("tab.\(tab)").frame, over = button.frame
        try await Self.post("\(one)/drag", Data("\(from.midX) \(from.midY) \(over.midX) \(over.midY) 1.2 "
                .appending("\(target.midX) \(target.midY) 0.5").utf8))
        return row
    }

    private func expectStack(_ tab: String, _ panes: [String]) async throws {
        try await expect("\(panes) stacked") {
            let root = try await root(tab), order = try await order(tab)
            return root["direction"] as? String == "down" && order == panes
        }
    }

    func card(_ pane: String, _ across: CGFloat, _ down: CGFloat) -> XCUICoordinate {
        element("pane.\(pane)").coordinate(withNormalizedOffset: CGVector(dx: across, dy: down))
    }

    /// By its title (30.5 pt in): on CI a quarter-wide card's shown buttons start at 52 pt, and take it.
    func drag(_ pane: String, to target: XCUICoordinate, hold: TimeInterval = 0.6) {
        during(card(pane, 0, 0).withOffset(CGVector(dx: 32, dy: 17)), to: target, hold: hold)
    }

    /// A timed hold fails both ways on CI: XCUITest plays a drag on a timetable from its start (late moves cut a 1.2 s
    /// hold to 0.4 s in the app), and drag.swift's release 0.5 s after a spring-load can leave a drag session that
    /// never ends.
    func press(_ pane: String, over target: XCUIElement) async throws {
        let from = element("pane.\(pane)").frame, over = target.frame
        try await Self.post("\(one)/press", Data("\(from.minX + 60) \(from.minY + 17) \(over.midX) \(over.midY)".utf8))
    }

    func release() async throws {
        try await Self.post("\(one)/release")
    }

    /// XCUITest runs nothing else while it drags (not even the main queue), so a drag in progress shows only in the
    /// run's screen recording.
    func during(_ from: XCUICoordinate, to target: XCUICoordinate, hold: TimeInterval = 0.6) {
        from.click(forDuration: 0.3, thenDragTo: target, withVelocity: .default, thenHoldForDuration: hold)
    }
}
