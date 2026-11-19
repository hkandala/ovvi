import XCTest

extension OvviUITests {
    /// The agents section's rows and header have menus, and its header a close button on the right column.
    func testTheAgentsSectionsMenusAndCloseButton() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let done = try await createTab(in: "w2", label: "menu-done"), work = try await createTab(
            in: "w2",
            label: "menu-work",
        )
        closeAfter("tab", done.tab)
        closeAfter("tab", work.tab)
        try await report(done.pane, "working")
        try await report(work.pane, "working")
        try await waitForValue("agent.\(done.pane)", containing: "Working")
        try await report(done.pane, "idle")
        openAgents()
        let section = element("agents.section"), close = element("agents.close"),
            menu = app.windows.firstMatch.menuItems

        step("The close button ends on the right column, the archive button beside it")
        XCTAssertEqual(close.frame.maxX, section.frame.maxX - 6, accuracy: 0.5, "\(close.frame) in \(section.frame)")
        XCTAssertEqual(element("agents.archive").frame.maxX, close.frame.minX, accuracy: 0.5)
        XCTAssertEqual(close.label, "Close")

        step("A done row's menu marks it read")
        let doneRow = element("agents.row.\(one).\(done.pane)")
        XCTAssertTrue(doneRow.exists(within: 5))
        doneRow.rightClick()
        XCTAssertTrue(menu["Open in Floating Window"].exists(within: 2))
        menu["Mark as Read"].click()
        XCTAssertTrue(doneRow.vanishes(within: 2))
        XCTAssertFalse(element("agents.group.Done").exists)

        step("A working row's menu floats its pane alone, with the keys")
        let workRow = element("agents.row.\(one).\(work.pane)")
        workRow.rightClick()
        XCTAssertTrue(menu["Open in Floating Window"].exists(within: 2))
        XCTAssertFalse(menu["Mark as Read"].exists, "Mark as Read on a row that is not done")
        menu["Open in Floating Window"].click()
        let window = app.windows.containing(.any, identifier: "float.\(work.pane)").firstMatch
        XCTAssertTrue(window.exists(within: 5))
        XCTAssertTrue(hasKeyboard("terminal.\(work.pane)", in: window))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.vanishes(within: 3))
        headerMenuAndCloseButton()
    }

    private func headerMenuAndCloseButton() {
        let section = element("agents.section"), close = element("agents.close"),
            menu = app.windows.firstMatch.menuItems
        step("The header's menu switches the view and closes the section")
        let header = element("agents.header")
        header.rightClick()
        menu["Show Archived Sessions"].click()
        XCTAssertTrue(element("agents.back").exists(within: 2))
        element("agents.back").rightClick()
        XCTAssertTrue(menu["Close"].exists(within: 2))
        menu["Show Agents"].click()
        XCTAssertTrue(header.exists(within: 2))
        header.rightClick()
        menu["Close"].click()
        XCTAssertTrue(section.vanishes(within: 2))

        step("The close button closes it too")
        element("sidebar.agents").click()
        XCTAssertTrue(close.exists(within: 2))
        close.click()
        XCTAssertTrue(section.vanishes(within: 2))
    }
}
