import XCTest

extension OvviUITests {
    /// "Worked" ends every turn the agent ended, a reply alone too, and stays under it after later turns, while the
    /// next one works and in a history read again.
    func testEveryEndedTurnKeepsItsWorked() async throws {
        let (tab, pane) = try await startChat()
        step("The empty chat: the glyph, the phrase under it, the reply box under them, all in the middle")
        let empty = element("chat.\(pane).empty"), composer = element("chat.\(pane).composer")
        XCTAssertTrue(empty.exists(within: 3))
        let card = element("pane.\(pane)").frame
        XCTAssertGreaterThan(empty.frame.height, 90, "the phrase sits beside the glyph: \(empty.frame)")
        XCTAssertEqual(empty.frame.midX, composer.frame.midX, accuracy: 2)
        XCTAssertTrue(empty.frame.maxY < composer.frame.minY, "\(empty.frame) \(composer.frame) in \(card)")
        // The box from its padding (13 pt over the text, 11 under Send), in the card under its two header rows.
        let box = (composer.frame.minY - 13 + element("chat.\(pane).send").frame.maxY + 11) / 2
        XCTAssertEqual(box, (card.minY + 68 + card.maxY) / 2, accuracy: 3, "the box is not centered")
        let placeholders = ["What's on your mind?": "Ask or tell me anything",
                            "What are we building?": "Describe the feature",
                            "Where should we start?": "Name a file, a bug or a goal",
                            "What can I help with?": "Ask a question or give a task",
                            "Ready when you are.": "Type your first message"]
        XCTAssertEqual(composer.placeholderValue, placeholders[empty.stringValue], empty.stringValue)

        let worked = app.descendants(matching: .any).matching(identifier: "chat.\(pane).worked")
        step("A turn of a reply alone")
        try await say("wait", in: pane)
        XCTAssertTrue(element("chat.\(pane).drawer").exists(within: 5))
        app.typeText("1")
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))
        XCTAssertTrue(until(3) { worked.count == 1 }, "\(worked.count)")
        XCTAssertEqual(composer.placeholderValue, "Ask Anything")
        step("Turns with tool calls; the earlier Worked stay")
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await say("steps", in: pane)
        XCTAssertTrue(row(pane, "reply", "Done.").exists(within: 5))
        XCTAssertTrue(until(3) { worked.count == 3 }, "\(worked.count)")
        XCTAssertTrue(worked.allElementsBoundByIndex.allSatisfy { $0.stringValue.hasPrefix("Worked ") })
        step("While the next turn works, and after it is interrupted (its note ends it)")
        try await say("slow", in: pane)
        XCTAssertTrue(element("chat.\(pane).stop").exists(within: 5))
        XCTAssertEqual(worked.count, 3)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
        XCTAssertEqual(worked.count, 3)

        step("Read again after a relaunch: a loader, never the empty chat, then every Worked")
        relaunch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(pane).view.tui").has(\.isSelected, true, within: 10))
        element("pane.\(pane).view.chat").click()
        try expectNoEmptyChat(pane, until: row(pane, "reply", "Done."))
        XCTAssertTrue(until(3) { worked.count == 3 }, "\(worked.count)")
    }

    /// Relaunch with Chat of a session that has a history: the agent runs its SessionStart hooks 6 s after it shows,
    /// and meanwhile the chat shows a loader, not the empty chat of a new conversation.
    func testAResumedChatShowsALoaderUntilItsHistoryIsIn() async throws {
        let pane = try await startChat(environment: "OVVI_STAND_IN_SLOW_START=6 ", chat: false, plain: true).pane
        let enable = element("pane.\(pane).enable-chat")
        XCTAssertTrue(enable.exists(within: 10))
        try await send("hello\r", to: pane)
        try await waitFor(pane) { $0.contains("Echo: **hello**") }
        enable.click()
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 30))
        let loading = element("chat.\(pane).loading")
        XCTAssertTrue(loading.exists(within: 2), "no loader")
        keepScreenshot("resume loader")
        try expectNoEmptyChat(pane, until: row(pane, "reply", "Echo: **hello**"))
        XCTAssertTrue(element("chat.\(pane).worked").exists)
    }

    /// A table wider than the reply scrolls sideways in its own box, and the chat still scrolls up and down over it.
    func testAWideTableScrollsSideways() async throws {
        let pane = try await startChat().pane
        try await say("many 6", in: pane)
        XCTAssertTrue(row(pane, "reply", "Last.").exists(within: 8))
        try await say("table", in: pane)
        let table = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND value BEGINSWITH '| Column 1'", "chat.\(pane).reply"))
            .firstMatch
        XCTAssertTrue(table.exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).worked").exists(within: 3))
        keepScreenshot("wide table")
        let before = table.screenshot().pngRepresentation
        XCTAssertTrue([-300.0, 300].contains { step in
            table.scroll(byDeltaX: step, deltaY: 0)
            return until(2) { table.screenshot().pngRepresentation != before }
        }, "the table did not scroll sideways")
        let top = table.frame.minY
        table.scroll(byDeltaX: 0, deltaY: 300)
        XCTAssertTrue(until(2) { table.frame.minY > top + 50 }, "the chat did not scroll over the table: \(top)")
    }

    /// Each look is one snapshot: none until `shown` holds the empty chat's header.
    private func expectNoEmptyChat(_ pane: String, until shown: XCUIElement) throws {
        let window = mainWindows.firstMatch
        XCTAssertTrue(until(10) {
            let nodes = (try? nodes(of: window)) ?? []
            XCTAssertFalse(nodes.contains { $0.identifier == "chat.\(pane).empty" }, "the empty chat showed")
            return shown.exists
        })
    }
}
