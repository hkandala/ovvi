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
        step("A message pi has not taken yet is dimmed, then full")
        let full = bubbleFill(row(pane, "user", "slow")), dimmed = bubbleFill(element("chat.\(pane).sending"))
        XCTAssertGreaterThan(apart(dimmed, full), 0.1, "\(dimmed) \(full)")
        stop.click()
        XCTAssertTrue(row(pane, "user", "later").exists(within: 5))
        XCTAssertLessThan(apart(bubbleFill(row(pane, "user", "later")), full), 0.05)
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

    /// pi's turn ended, but it waits on its agents and a background job (pi-herd, pi-bash-bg), which herdr hears as
    /// working: the chat says so in place of Working, keeps Send, and Esc stops nothing.
    func testAPiChatWaitingOnItsAgentsKeepsSend() async throws {
        let pane = try await startChat(agent: 2).pane
        try await say("agents", in: pane)
        let waiting = element("chat.\(pane).waiting")
        XCTAssertTrue(waiting.has(\.stringValue, "Waiting on 2 agents and 1 background job", within: 5))
        XCTAssertEqual(element("pane.\(pane).state").stringValue, "Working")
        XCTAssertTrue(element("chat.\(pane).send").exists)
        XCTAssertFalse(element("chat.\(pane).stop").exists)
        app.typeKey(.escape, modifierFlags: [])
        try await say("slow", in: pane)
        XCTAssertTrue(waiting.vanishes(within: 5))
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists(within: 5))
        let screen = try await read(pane)
        XCTAssertFalse(screen.contains("Escape pressed"))
        stop.click()
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
    }

    /// Its process lists no arguments, as npm's pi, whose process title overwrites them. Its session comes 8 s late:
    /// the message typed meanwhile waits for it, never "Not sent".
    func testAPiRunListsEveryKindOfTool() async throws {
        let (tab, pane) = try await startChat(agent: 2, environment: "OVVI_STAND_IN_TITLE=1 OVVI_STAND_IN_LATE=8 ")
        app.typeText("tools\r")
        XCTAssertFalse(element("chat.\(pane).not-sent").exists(within: 10))
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
        XCTAssertTrue(element("pane.\(pane).view.chat").has(\.isSelected, true, within: 10))
        XCTAssertTrue(row(pane, "reply", "All tools.").exists(within: 5))
    }

    /// A user bubble's fill, 6 pt left of its text: a dimmed one shows the card through it.
    func bubbleFill(_ text: XCUIElement) -> [CGFloat] {
        let window = mainWindows.firstMatch
        guard let image = window.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        let scale = CGFloat(image.width) / window.frame.width, bitmap = NSBitmapImageRep(cgImage: image)
        let color = bitmap.colorAt(x: Int((text.frame.minX - 6 - window.frame.minX) * scale),
                                   y: Int((text.frame.midY - window.frame.minY) * scale))?.usingColorSpace(.sRGB)
        return color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent] } ?? []
    }

    func apart(_ one: [CGFloat], _ two: [CGFloat]) -> CGFloat {
        one.isEmpty || two.isEmpty ? 0 : zip(one, two).map { abs($0 - $1) }.reduce(0, +)
    }
}
