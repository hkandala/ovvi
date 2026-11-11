import XCTest

/// Each window's space order (ui/window#sidebar, Sort Spaces) and pinned spaces: on top in herdr's order, a line under
/// them when others follow, pinned from a row's menu, the palette or a drag; Recent never moves them.
extension OvviUITests {
    /// A window's sort is its own; a new one takes Settings' (`spaceOrder`).
    func testEachWindowKeepsItsOwnSpaceOrder() throws {
        let (first, second) = try newWindow()
        let mine = element("sidebar.sort", in: first), other = element("sidebar.sort", in: second)
        XCTAssertTrue(other.exists(within: connect))
        XCTAssertEqual(other.value as? String, "Manual")
        raise(first)
        mine.click()
        mine.menuItems["Recent"].click()
        XCTAssertTrue(mine.has(\.stringValue, "Recent", within: 2))
        XCTAssertFalse(until(1) { other.value as? String != "Manual" }, "the other window's order changed")
        relaunch(one, ["-spaceOrder", "recent"])
        XCTAssertTrue(element("sidebar.sort").has(\.stringValue, "Recent", within: connect))
    }

    /// Pinned from the row's menu and the palette; on top in herdr's order, the line only while unpinned ones follow;
    /// Recent leaves them; unpinned again from both.
    func testPinnedSpacesStayOnTopAboveALine() async throws {
        pinsOfTheirOwn("a")
        let gamma = try await workspace(of: createWorkspace("pin-c").tab)
        let alpha = element("workspace.w1"), beta = element("workspace.w2"), third = element("workspace.\(gamma)")
        let line = element("sidebar.pinned-line")
        XCTAssertTrue(third.exists(within: 3))
        XCTAssertFalse(line.exists)
        third.rightClick()
        app.menuItems["Pin Space"].click()
        try await expectTops([third, alpha, beta], "the pinned space on top")
        XCTAssertTrue(line.exists)
        XCTAssertEqual(line.frame.midY, (third.frame.maxY + alpha.frame.minY) / 2, accuracy: 1)

        beta.click()
        openPalette().typeText("pin space")
        XCTAssertTrue(element("palette.command.Pin Space").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        try await expectTops([beta, third, alpha], "pinned ones in herdr's order")

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
        try await expectTops([alpha, third, beta], "beta under the pinned ones")
        XCTAssertTrue(line.exists(within: 2))
        keepScreenshot("pinned spaces")
        for row in [alpha, third] {
            row.rightClick()
            app.menuItems["Unpin Space"].click()
        }
        XCTAssertTrue(line.vanishes(within: 2))
    }

    /// A drag above the line pins, under it unpins; with nothing pinned a line stands at the top while a space is
    /// dragged.
    func testDraggingASpaceAboveTheLinePinsIt() async throws {
        pinsOfTheirOwn("b")
        let gamma = try await workspace(of: createWorkspace("pin-d").tab)
        let alpha = element("workspace.w1"), third = element("workspace.\(gamma)")
        XCTAssertTrue(third.exists(within: 3))
        // Grabbed by its name, dropped at the list's top, under the line that stands there while nothing is pinned.
        during(third.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15)),
               to: alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        // At once: no frame of the old order after the drop.
        XCTAssertLessThan(third.frame.minY, alpha.frame.minY, "the old order showed after the drop")
        try await expectTops([third, alpha], "dropped on the top line, pinned")
        XCTAssertTrue(element("sidebar.pinned-line").exists(within: 2))
        let ids = try await workspaceIDs()
        during(third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertLessThan(alpha.frame.minY, third.frame.minY, "the old order showed after the drop")
        XCTAssertTrue(element("sidebar.pinned-line").vanishes(within: 2), "dropped under the line, still pinned")
        try await expectTops([alpha, third], "after alpha, as dropped")
        let moved = try await workspaceIDs()
        XCTAssertNotEqual(moved, ids)
    }

    /// A config folder of their own: a failure's pins on w1 and w2 stay out of the shard's other tests.
    private func pinsOfTheirOwn(_ name: String) {
        relaunch(one, ["-configFolder", "/tmp/ovvi-e2e-pins-\(name)"])
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
    }

    private func expectTops(_ rows: [XCUIElement], _ what: String) async throws {
        try await expect(what) {
            guard rows.allSatisfy(\.exists) else { return false }
            let tops = rows.map(\.frame.minY)
            return tops == tops.sorted() && Set(tops).count == tops.count
        }
    }
}
