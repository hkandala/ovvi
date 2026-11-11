import XCTest

extension OvviUITests {
    func testACodexChatSendsStopsAndShowsTheTerminalWhileItWaits() async throws {
        let (tab, pane) = try await startChat(agent: 1)
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        XCTAssertEqual(element("chat.\(pane).stack").label, "Ran 1 command")

        try await say("slow", in: pane)
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists(within: 5))
        stop.click()
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))

        // A picker: herdr says idle, the screen has no input box: the terminal, with the keyboard, until Esc.
        try await say("model", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        XCTAssertFalse(element("chat.\(pane).composer").exists)
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 3))

        // An approval: herdr says blocked.
        try await say("wait", in: pane)
        XCTAssertTrue(drawer.exists(within: 5))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))

        relaunch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(pane).view.tui").has(\.isSelected, true, within: 10))
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))

        try await say("new", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **new**").exists(within: 5))
        XCTAssertFalse(row(pane, "reply", "Allowed.").exists)
    }

    func testACodexChatOnARemoteMachine() async throws {
        try await skipWithoutSSH()
        relaunch(one, Self.onKeyHost)
        let pane = try await startChat(agent: 1).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await say("model", in: pane)
        XCTAssertTrue(element("chat.\(pane).drawer").exists(within: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("chat.\(pane).drawer").vanishes(within: 5))
    }
}
