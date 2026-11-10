import XCTest

extension OvviUITests {
    func testAnOpenCodeChatAnswersPermissionsAndQuestions() async throws {
        let pane = try await startChat(agent: 3).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))

        try await say("allow", in: pane)
        let allow = element("chat.\(pane).option.Allow once")
        XCTAssertTrue(allow.exists(within: 5))
        keepScreenshot("opencode-permission")
        allow.click()
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))
        XCTAssertTrue(allow.vanishes(within: 3))

        try await say("ask", in: pane)
        let blue = element("chat.\(pane).option.Blue")
        XCTAssertTrue(blue.exists(within: 5))
        blue.click()
        XCTAssertTrue(row(pane, "reply", "You chose Blue.").exists(within: 5))

        try await say("pick", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Picked.").exists(within: 5))

        try await say("slow", in: pane)
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists(within: 5))
        stop.click()
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
    }

    func testAnOpenCodeThatRefusesTheFlagsStartsPlain() async throws {
        let pane = try await startChat(agent: 3, environment: "OVVI_STAND_IN_REFUSE=1 ", chat: false).pane
        try await waitFor(pane, times: 100) { $0.contains("OpenCode stand-in plain") }
        let text = try await read(pane)
        XCTAssertTrue(text.contains("Unrecognized flag: --port"), text)
        XCTAssertTrue(element("pane.\(pane).loader").vanishes(within: 5))
        XCTAssertFalse(element("pane.\(pane).view.chat").exists(within: 1))
    }

    func testAnOpenCodeChatOnARemoteMachine() async throws {
        try await skipWithoutSSH()
        let pane = try await startChat(Self.onKeyHost, agent: 3).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await say("allow", in: pane)
        let allow = element("chat.\(pane).option.Allow once")
        XCTAssertTrue(allow.exists(within: 5))
        allow.click()
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))
    }
}
