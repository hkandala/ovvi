import XCTest

/// A session's space order (ui/window#sidebar, Sort Spaces) and pinned spaces: on top in herdr's order, a line under
/// them when others follow, pinned from a row's menu, the palette or a drop on the pin region; Recent never moves them;
/// Show Only Pinned Spaces hides the others and their alerts.
extension OvviUITests {
    /// Both windows of a session follow its Sort Spaces; another session takes Settings' (`spaceOrder`); a relaunch
    /// keeps it.
    func testEachSessionKeepsItsOwnSpaceOrder() throws {
        pinsOfTheirOwn("a")
        let (first, second) = try newWindow()
        let mine = element("sidebar.sort", in: first), other = element("sidebar.sort", in: second)
        XCTAssertTrue(other.exists(within: connect))
        XCTAssertEqual(other.value as? String, "Manual")
        raise(first)
        mine.click()
        mine.menuItems["Recent"].click()
        XCTAssertTrue(mine.has(\.stringValue, "Recent", within: 2))
        XCTAssertTrue(other.has(\.stringValue, "Recent", within: 2), "the session's other window kept its own order")
        relaunch(two, ["-configFolder", Self.pins("a"), "-spaceOrder", "recent"])
        XCTAssertTrue(element("sidebar.sort").has(\.stringValue, "Recent", within: connect), "not Settings' order")
        relaunch(one, ["-configFolder", Self.pins("a")])
        XCTAssertTrue(element("sidebar.sort").has(\.stringValue, "Recent", within: connect), "not kept")
    }

    /// Pinned from the row's menu and the palette; on top in herdr's order, the line only while unpinned ones follow;
    /// Recent leaves them; unpinned again from both.
    func testPinnedSpacesStayOnTopAboveALine() async throws {
        pinsOfTheirOwn("b")
        let gamma = try await newSpace("pin-c")
        let alpha = element("workspace.w1"), beta = element("workspace.w2"), third = element("workspace.\(gamma)")
        let line = element("sidebar.pinned-line")
        XCTAssertTrue(third.exists(within: 3))
        XCTAssertFalse(line.exists)
        third.rightClick()
        app.menuItems["Pin Space"].click()
        try await expectOrder([third, alpha, beta], "the pinned space on top")
        XCTAssertTrue(line.exists)
        XCTAssertEqual(line.frame.midY, (third.frame.maxY + alpha.frame.minY) / 2, accuracy: 1)

        beta.click()
        openPalette().typeText("pin space")
        XCTAssertTrue(element("palette.command.Pin Space").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        try await expectOrder([beta, third, alpha], "pinned ones in herdr's order")

        // Recent: alpha's agent changes last, and stays under the pinned ones.
        let pane = try await newTab("pin-agent", in: "w1").pane
        let sort = element("sidebar.sort")
        sort.click()
        sort.menuItems["Recent"].click()
        try await report(pane, "working", agent: "pi")
        try await waitForValue("agent.\(pane)", containing: "Working")
        element("sidebar.header").hover()
        XCTAssertFalse(until(2) { alpha.frame.minY < third.frame.minY }, "Recent moved a pinned space")
        sort.click()
        sort.menuItems["Manual"].click()

        alpha.rightClick()
        app.menuItems["Pin Space"].click()
        XCTAssertTrue(line.vanishes(within: 2), "a line with nothing under it")
        beta.click()
        openPalette().typeText("unpin space")
        XCTAssertTrue(element("palette.command.Unpin Space").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        try await expectOrder([alpha, third, beta], "beta under the pinned ones")
        XCTAssertTrue(line.exists(within: 2))
        keepScreenshot("pinned spaces")
        for row in [alpha, third] {
            row.rightClick()
            app.menuItems["Unpin Space"].click()
        }
        XCTAssertTrue(line.vanishes(within: 2))
    }

    /// While a space is dragged the pin region stands under the pinned ones (on top with none), lit under the pointer
    /// on every drag; a drop there pins last of them, among them places exactly, under it unpins.
    func testDroppingASpaceOnThePinRegionPinsIt() async throws {
        pinsOfTheirOwn("c")
        let gamma = try await newSpace("pin-d")
        let alpha = element("workspace.w1"), beta = element("workspace.w2"), third = element("workspace.\(gamma)")
        let region = element("sidebar.pin-region")
        XCTAssertTrue(third.exists(within: 3))
        XCTAssertFalse(region.exists)
        // The region opens at the first row's place.
        try await press(third, at: alpha.frame.minY + 15)
        XCTAssertTrue(region.has(\.stringValue, "lit", within: 2), "no lit pin region on the first drag")
        keepScreenshot("pin region lit")
        try await release()
        try await expectOrder([third, alpha, beta], "dropped on the pin region, pinned")
        XCTAssertTrue(element("sidebar.pinned-line").exists(within: 2))
        XCTAssertFalse(region.exists)

        // A row with an agent, held by its name: the region lights under the pointer, not under the row's middle.
        let agent = try await newTab("pin-agent", in: "w2").pane
        try await report(agent, "working", agent: "pi")
        XCTAssertTrue(element("agent.\(agent)").exists(within: 3))
        try await press(beta, at: alpha.frame.minY + 15)
        XCTAssertTrue(region.has(\.stringValue, "lit", within: 2), "no lit pin region on the next drag")
        XCTAssertGreaterThan(region.frame.minY, third.frame.maxY, "the region not under the pinned one")
        try await release()
        try await expectOrder([third, beta, alpha], "pinned last of the pinned ones")

        during(beta.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        try await expectOrder([beta, third, alpha], "placed among the pinned ones")
        try await expect("herdr's order") {
            let ids = try await workspaceIDs()
            return ids.firstIndex(of: "w2") ?? 0 < ids.firstIndex(of: gamma) ?? 0
        }
        // Under the region (which takes the line's place and pushes alpha down while beta is dragged).
        during(beta.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 40)))
        try await expectOrder([third, alpha, beta], "dropped under the region, unpinned")
        XCTAssertLessThan(element("sidebar.pinned-line").frame.midY, alpha.frame.minY)
    }

    /// Recent orders the unpinned spaces itself: a drag among them is refused, but one pins onto the region, the pinned
    /// ones reorder, and one dragged out unpins.
    func testInRecentOnlyThePinnedSpacesReorder() async throws {
        pinsOfTheirOwn("d")
        let gamma = try await newSpace("pin-e")
        let delta = try await newSpace("pin-f")
        let alpha = element("workspace.w1"), third = element("workspace.\(gamma)"),
            fourth = element("workspace.\(delta)")
        XCTAssertTrue(fourth.exists(within: 3))
        let sort = element("sidebar.sort")
        sort.click()
        sort.menuItems["Recent"].click()
        XCTAssertTrue(sort.has(\.stringValue, "Recent", within: 2))
        alpha.rightClick()
        app.menuItems["Pin Space"].click()
        XCTAssertTrue(element("sidebar.pinned-line").exists(within: 2))
        let beta = element("workspace.w2")
        let first = [beta, third, fourth].min { $0.frame.minY < $1.frame.minY }
        try await press(third, at: (first?.frame.minY ?? 0) + 15)
        XCTAssertTrue(element("sidebar.pin-region").has(\.stringValue, "lit", within: 2))
        try await release()
        let unpinned = { [beta, fourth].sorted { $0.frame.minY < $1.frame.minY } }
        try await expectOrder([alpha, third, unpinned()[0]], "pinned onto the region, in herdr's order")

        during(third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        try await expectOrder([third, alpha], "the pinned ones reordered in Recent")
        try await expect("herdr's order") {
            let ids = try await workspaceIDs()
            return ids.firstIndex(of: gamma) ?? 0 < ids.firstIndex(of: "w1") ?? 0
        }

        // Anywhere under the region (it takes the line's place and pushes the unpinned ones down while one is dragged).
        let ids = try await workspaceIDs(), rows = unpinned()
        during(rows[1].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: rows[0].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(
                   dx: 0,
                   dy: 10,
               )))
        XCTAssertFalse(until(1) { rows[1].frame.minY < rows[0].frame.minY }, "Recent's unpinned ones reordered")
        let after = try await workspaceIDs()
        XCTAssertEqual(after, ids)

        during(third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: unpinned()[1].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(
                   CGVector(dx: 0, dy: 40),
               ))
        try await expect("unpinned, under the line") {
            element("sidebar.pinned-line").frame.midY < third.frame.minY && alpha.frame.minY < third.frame.minY
        }
    }

    /// Hides the unpinned spaces but the one in view, and their states: no Dock badge, no notification; Show All Spaces
    /// brings them back; unpinning the last pinned one ends it.
    func testShowOnlyPinnedSpacesHidesTheOthersAndTheirAlerts() async throws {
        pinsOfTheirOwn("e")
        let (_, pane) = try await newTab("pin-hidden", in: "w2")
        let alpha = element("workspace.w1"), beta = element("workspace.w2"), badge = element("app.badge")
        try await waitForPrompt(pane)
        try await report(pane, "blocked", agent: "claude")
        XCTAssertTrue(badge.has(\.stringValue, "1", within: 3))
        element("sidebar.header").rightClick()
        XCTAssertFalse(app.menuItems["Show Only Pinned Spaces"].isEnabled, "on with nothing pinned")
        app.typeKey(.escape, modifierFlags: [])
        alpha.rightClick()
        app.menuItems["Pin Space"].click()
        element("sidebar.header").rightClick()
        app.menuItems["Show Only Pinned Spaces"].click()
        XCTAssertFalse(until(1) { !beta.exists }, "the space in view hid")
        XCTAssertFalse(element("sidebar.pinned-line").exists)
        XCTAssertEqual(badge.stringValue, "1")

        alpha.click()
        XCTAssertTrue(beta.vanishes(within: 2))
        XCTAssertTrue(badge.has(\.stringValue, "0", within: 2), "a hidden space's agent counts")
        try await run("\(Self.ovviCommand) notify Hidden", in: pane, "hidden", 0, "notified: false")
        keepScreenshot("only pinned")

        openPalette().typeText("show all spaces")
        XCTAssertTrue(element("palette.command.Show All Spaces").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(beta.exists(within: 2))
        XCTAssertTrue(badge.has(\.stringValue, "1", within: 2))

        element("sidebar.header").rightClick()
        app.menuItems["Show Only Pinned Spaces"].click()
        XCTAssertTrue(beta.vanishes(within: 2))
        alpha.rightClick()
        app.menuItems["Unpin Space"].click()
        XCTAssertTrue(beta.exists(within: 2), "still on with nothing pinned")
    }

    /// Move Down, a sort, herdr's order in Recent, a pin and Show Only Pinned Spaces each move the rows in the one
    /// motion (`sidebar.moves`: the order's changes with a motion, and without).
    func testEveryReorderOfTheSpacesMoves() async throws {
        relaunch(one, ["-configFolder", Self.pins("f"), "-recordMotion", "YES", "-forceMotion", "YES"])
        let alpha = element("workspace.w1"), beta = element("workspace.w2"), moves = element("sidebar.moves")
        XCTAssertTrue(beta.exists(within: connect))
        let counts = { moves.stringValue.split(separator: " ").compactMap { Int($0) } }
        var seen = counts()
        func moved(_ what: String) async throws {
            try await expect("\(what) moved the rows in a motion") {
                let now = counts()
                return now.count == 2 && now[0] > seen[0] && now[1] == seen[1]
            }
            seen = counts()
        }
        XCTAssertEqual(seen.count, 2, moves.stringValue)
        addTeardownBlock { [one] in
            _ = try? await Self.call(
                one,
                "workspace.move_block",
                ["workspace_ids": ["w1"], "before_workspace_id": "w2"],
            )
        }
        alpha.rightClick()
        app.menuItems["Move Down"].click()
        try await moved("Move Down")

        let agent = try await newTab("pin-move", in: "w1").pane
        try await report(agent, "working", agent: "pi")
        try await waitForValue("workspace.w1", containing: "working")
        let sort = element("sidebar.sort")
        sort.click()
        sort.menuItems["Recent"].click()
        try await moved("Recent")
        XCTAssertTrue(until(3) { alpha.frame.minY < beta.frame.minY }, "Recent put alpha first")
        // Off the rows: Recent holds them still under the pointer, which the menu left there.
        element("sidebar.header").hover()

        // Not selected: a click leaves the pointer over the rows, and Recent holds them still under it.
        let (tab, other) = try await createTab(in: "w2")
        closeAfter("tab", tab)
        try await report(other, "working", agent: "pi")
        try await moved("herdr's order in Recent")

        beta.rightClick()
        app.menuItems["Pin Space"].click()
        try await moved("Pin Space")
        beta.click()
        element("sidebar.header").rightClick()
        app.menuItems["Show Only Pinned Spaces"].click()
        XCTAssertTrue(alpha.vanishes(within: 2))
        try await moved("Show Only Pinned Spaces")
    }

    /// The pointer lights the row under it, headers and agent lines, after pins and drags move the rows
    /// (`sidebar.lit`: the target the pointer found).
    func testThePointerLightsTheRowUnderItAfterPins() async throws {
        relaunch(one, ["-configFolder", Self.pins("g"), "-recordMotion", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        addTeardownBlock { [one] in
            _ = try? await Self.call(
                one,
                "workspace.move_block",
                ["workspace_ids": ["w1"], "before_workspace_id": "w2"],
            )
        }
        let gamma = try await newSpace("pin-g")
        let alpha = element("workspace.w1"), beta = element("workspace.w2"), third = element("workspace.\(gamma)")
        let rows = try await [("w1", alpha), ("w2", beta), (gamma, third)] + agents(in: ["w1", "w2", gamma])
        XCTAssertTrue(rows.allSatisfy { $0.1.exists(within: 3) })
        let lightsEach = { (after: String) in self.lightsEach(rows, after) }
        lightsEach("the start")
        try await press(third, at: alpha.frame.minY + 15)
        XCTAssertTrue(element("sidebar.pin-region").has(\.stringValue, "lit", within: 2))
        try await release()
        try await expectOrder([third, alpha, beta], "dropped on the pin region")
        lightsEach("a drop on the pin region")
        beta.rightClick()
        app.menuItems["Pin Space"].click()
        try await expectOrder([beta, third, alpha], "pinned from the menu")
        lightsEach("a pin from the menu")
        // Onto third's last agent line: past the middle of its block, the header and its agents.
        during(beta.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
               to: rows[rows.count - 1].1.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await expectOrder([third, beta, alpha], "reordered among the pinned ones")
        lightsEach("a drag among the pinned ones")
        beta.rightClick()
        app.menuItems["Move Up"].click()
        try await expectOrder([beta, third, alpha], "moved up")
        lightsEach("Move Up")
        beta.rightClick()
        app.menuItems["Unpin Space"].click()
        try await expect("unpinned") { element("sidebar.pinned-line").frame.midY < beta.frame.minY }
        lightsEach("an unpin")
    }

    /// Two agent lines in each space.
    private func agents(in spaces: [String]) async throws -> [(String, XCUIElement)] {
        var agents: [(String, XCUIElement)] = []
        for space in spaces {
            for name in ["builder", "author"] {
                let (tab, pane) = try await createTab(in: space, label: "hover-\(name)")
                closeAfter("tab", tab)
                try await report(pane, "working", agent: "pi")
                agents.append((pane, element("agent.\(pane)")))
            }
        }
        return agents
    }

    /// The pointer over each row in turn lights that row.
    private func lightsEach(_ rows: [(String, XCUIElement)], _ after: String) {
        let lit = element("sidebar.lit")
        for (id, row) in rows {
            // Again until it lights: one hover in the rows' 0.2 s motion can land on the row's last place.
            XCTAssertTrue(until(2) { row.hover(); return lit.stringValue == id },
                          "after \(after): over \(id) at \(row.frame.minY)...\(row.frame.maxY), lit \(lit.stringValue)")
        }
        element("sidebar.header").hover()
    }

    /// Its id from herdr's list: after the shard's earlier tests the new tab's id did not name its space.
    private func newSpace(_ label: String) async throws -> String {
        let before = try await workspaceIDs()
        _ = try await createWorkspace(label)
        return try await poll("\(label)'s id") { try await workspaceIDs().first { !before.contains($0) } }
    }

    static func pins(_ name: String) -> String {
        "/tmp/ovvi-e2e-pins-\(name)"
    }

    /// A config folder of their own: a failure's pins on w1 and w2 stay out of the shard's other tests.
    private func pinsOfTheirOwn(_ name: String) {
        relaunch(one, ["-configFolder", Self.pins(name)])
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
    }

    /// Holds `row`, grabbed by its middle, dragged to `pointY` (screen points) until `release()`.
    private func press(_ row: XCUIElement, at pointY: CGFloat) async throws {
        let from = row.frame
        try await Self.post("\(one)/press", Data("\(from.midX) \(from.midY) \(from.midX) \(pointY)".utf8))
    }
}
