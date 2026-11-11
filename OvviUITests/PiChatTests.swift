import XCTest

extension OvviUITests {
    func testPiChatSendsWaitsStopsAndFollowsTheTree() async throws {
        let pane = try await startChat(agent: 2).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))

        try await say("wait", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        XCTAssertFalse(element("chat.\(pane).composer").exists)
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))

        try await say("slow", in: pane)
        app.typeText("later\r")
        XCTAssertFalse(element("chat.\(pane).not-sent").exists(within: 7))
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists)
        stop.click()
        XCTAssertTrue(row(pane, "user", "later").exists(within: 5))
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))

        app.typeText("/tree\r")
        XCTAssertTrue(element("chat.\(pane).composer").vanishes(within: 3))
        // The app types /tree in a task after the composer hides: an earlier Enter reaches pi first.
        try await waitFor(pane) { $0.contains("/tree") }
        try await send("\r", to: pane)
        try await waitFor(pane) { $0.contains("Navigated to selected point") }
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(row(pane, "user", "later").vanishes(within: 5))
        XCTAssertTrue(row(pane, "user", "slow").exists)
        try await say("again", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **again**").exists(within: 5))
        XCTAssertFalse(row(pane, "user", "later").exists)
    }

    /// Its process lists no arguments, as npm's pi, whose process title overwrites them.
    func testAPiRunListsEveryKindOfTool() async throws {
        let (tab, pane) = try await startChat(agent: 2, environment: "OVVI_STAND_IN_TITLE=1 ")
        try await say("tools", in: pane)
        XCTAssertTrue(row(pane, "reply", "All tools.").exists(within: 5))
        let stack = element("chat.\(pane).stack")
        XCTAssertEqual(stack.label, "Read 2 files, searched 2 patterns, ran 2 commands, +4 more")
        stack.click()
        let tools = app.descendants(matching: .any).matching(identifier: "chat.\(pane).tool")
        XCTAssertTrue(until(2) { tools.count == 10 }, "\(tools.count)")
        keepScreenshot("every tool")
        XCTAssertEqual(tools.allElementsBoundByIndex.map(\.label), [
            "read, a.txt, 1 line", "write, b.txt, ok", "edit, b.txt, +1 -1", "grep, needle, ok", "find, *.txt, ok",
            "ls, ., ok", "bash, echo hi, ok", "codemode, await tools.read({path: 'c.txt'}), ok", "read, c.txt",
            "agent_start, helper, ok",
        ])
        relaunch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        element("tab.\(tab)").click()
        let chat = element("pane.\(pane).view.chat")
        XCTAssertTrue(chat.exists(within: 10))
        chat.click()
        XCTAssertTrue(row(pane, "reply", "All tools.").exists(within: 5))
    }
}
