import XCTest

extension OvviUITests {
    func testAChatSendsStopsAndFoldsItsToolCalls() async throws {
        let pane = try await startChat().pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await waitFor(pane) { $0.contains("Echo: **hello**") }

        XCTAssertTrue(twoRows(pane, above: "pane.\(pane).view.chat"))
        let stacks = app.descendants(matching: .any).matching(identifier: "chat.\(pane).stack")
        XCTAssertTrue(stacks.element(boundBy: 0).has(\.stringValue, "closed", within: 2))
        XCTAssertEqual(stacks.element(boundBy: 0).label, "Ran 1 command")
        XCTAssertTrue(element("chat.\(pane).worked").stringValue.hasPrefix("Worked "))
        keepScreenshot("chat")

        try await say("steps", in: pane)
        XCTAssertTrue(row(pane, "reply", "Done.").exists(within: 5))
        XCTAssertTrue(row(pane, "reply", "First, a look.").exists)
        XCTAssertTrue(row(pane, "reply", "Then two more.").exists)
        XCTAssertEqual(stacks.count, 3)
        let run = stacks.element(boundBy: 2)
        XCTAssertEqual(run.label, "Ran 2 commands")
        XCTAssertEqual(run.stringValue, "closed")
        let tools = app.descendants(matching: .any).matching(identifier: "chat.\(pane).tool")
        XCTAssertEqual(tools.count, 0)
        run.click()
        XCTAssertTrue(run.has(\.stringValue, "open", within: 2))
        XCTAssertTrue(until(2) { tools.count == 2 }, "\(tools.count)")
        keepScreenshot("open run")
        run.click()
        XCTAssertTrue(tools.firstMatch.vanishes(within: 2))

        try await say("slow", in: pane)
        XCTAssertTrue(element("chat.\(pane).stop").exists(within: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))

        try await say("mute", in: pane)
        app.typeText("lost\r")
        XCTAssertTrue(element("chat.\(pane).not-sent").exists(within: 8))
        XCTAssertEqual(element("chat.\(pane).composer").stringValue, "lost")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])

        app.typeText("/help\r")
        XCTAssertTrue(element("chat.\(pane).composer").vanishes(within: 3))
        try await waitFor(pane) { $0.contains("/help") }
        XCTAssertTrue(element("pane.\(pane).view.tui").isSelected)
        XCTAssertTrue(findEnabled())
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 3))
        // Its bar would scroll the TUI under the chat, with nothing to highlight.
        XCTAssertFalse(findEnabled())
    }

    private func findEnabled() -> Bool {
        let edit = app.menuBars.menuBarItems["Edit"]
        edit.click()
        defer { app.typeKey(.escape, modifierFlags: []) }
        return edit.menuItems["Find…"].isEnabled
    }

    func testAToolOutputScrollsInsideItsBox() async throws {
        let pane = try await startChat().pane
        let empty = element("chat.\(pane).empty"), composer = element("chat.\(pane).composer")
        let card = element("pane.\(pane)").frame
        XCTAssertTrue(empty.exists(within: 3) && !empty.stringValue.isEmpty, empty.stringValue)
        XCTAssertTrue(empty.frame.maxY < composer.frame.minY && card.maxY - composer.frame.maxY > card.height / 4,
                      "\(empty.frame) \(composer.frame) in \(card)")
        keepScreenshot("empty chat")
        try await say("long", in: pane)
        let user = row(pane, "user", "long"), stack = element("chat.\(pane).stack")
        XCTAssertTrue(
            until(2) { !empty.exists && card.maxY - composer.frame.maxY < 60 && user.frame.minY < card.minY + 120 },
            "\(user.frame) \(composer.frame) in \(card)",
        )
        XCTAssertTrue(row(pane, "reply", "Counted.").exists(within: 5))
        XCTAssertGreaterThanOrEqual(stack.frame.minY - user.frame.maxY, 16, "\(user.frame) \(stack.frame)")
        stack.click()
        let tool = element("chat.\(pane).tool")
        tool.click()
        let output = element("chat.\(pane).tool.output")
        XCTAssertTrue(output.exists(within: 2))
        keepScreenshot("tool output")
        let place = { output.frame.minY - tool.frame.minY }, start = place()
        let point = "\(output.frame.minX + 40) \(output.frame.minY + 82)"
        for step in [-10, 10] {
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(step) 14 100 1".utf8))
            if until(3, { place() < start - 50 }) {
                break
            }
        }
        XCTAssertLessThan(place(), start - 50)
    }

    func testAFloatingWindowShowsTheChat() async throws {
        let pane = try await startChat().pane
        let window = float(pane)
        let composer = element("chat.\(pane).composer", in: window)
        XCTAssertTrue(composer.exists(within: 5))
        XCTAssertTrue(hasKeyboard(composer))
        try await say("hello", in: pane)
        let reply = row(pane, "reply", "Echo: **hello**")
        XCTAssertTrue(reply.exists(within: 5))
        XCTAssertEqual(composer.placeholderValue, "Ask Anything")
        XCTAssertEqual(composer.frame.minX, reply.frame.minX, accuracy: 1)
        for _ in 1 ... 4 {
            app.typeKey(.return, modifierFlags: .shift)
        }
        XCTAssertTrue(
            until(2) { composer.frame.height > 75 && reply.frame.maxY <= composer.frame.minY },
            "\(reply.frame)",
        )
        keepScreenshot("floating chat", of: window)
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        element("pane.\(pane).view.tui", in: window).click()
        XCTAssertTrue(composer.vanishes(within: 3))
        XCTAssertTrue(hasKeyboard("terminal.\(pane)", in: window))
        element("pane.\(pane).view.chat", in: window).click()
        XCTAssertTrue(hasKeyboard(composer))
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let corner = origin.withOffset(CGVector(dx: window.frame.width - 2, dy: window.frame.height - 2))
        corner.click(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: 200, dy: 200)))
        let detach = element("float.\(pane).detach")
        XCTAssertLessThanOrEqual(detach.frame.maxX, window.frame.maxX, "\(detach.frame) \(window.frame)")
        detach.click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 3))
    }

    /// Turns that end while the card shows the TUI are in the chat's first frame when Chat is picked again, at the
    /// bottom: not the old rows, then a jump. A chat made again (floated) shows too.
    func testAChatShownAgainOpensOnTheTurnsItMissed() async throws {
        let pane = try await startChat().pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        element("pane.\(pane).view.tui").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        // 150 turns: enough lines that reading them takes a while.
        app.typeText("many\r")
        try await waitFor(pane) { $0.contains("Last.") }
        element("pane.\(pane).view.chat").click()
        // Each look is one snapshot: the first that holds the chat must hold the last reply, in view.
        var seen: [XCUIElementSnapshot] = []
        XCTAssertTrue(until(5) {
            seen = (try? nodes(of: mainWindows.firstMatch)) ?? []
            return seen.contains { $0.identifier == "chat.\(pane)" }
        })
        let chat = seen.first { $0.identifier == "chat.\(pane)" }?.frame ?? .zero
        let last = seen.first { $0.identifier == "chat.\(pane).reply" && $0.value as? String == "Last." }?.frame
        XCTAssertNotNil(last, "the chat showed the rows from before the turns")
        XCTAssertTrue(
            last.map { chat.contains(CGPoint(x: $0.midX, y: $0.midY)) } == true,
            "\(String(describing: last)) \(chat)",
        )
        let window = float(pane)
        XCTAssertTrue(element("chat.\(pane).composer", in: window).exists(within: 5))
    }

    func testAChatTakesTheKeyboardOnAnyClickAndItsBoxGrows() async throws {
        let (tab, pane) = try await startChat()
        try await say("hello", in: pane)
        let reply = row(pane, "reply", "Echo: **hello**")
        XCTAssertTrue(reply.exists(within: 5))
        element("chat.\(pane).stack").click()
        let tool = element("chat.\(pane).tool")
        XCTAssertTrue(tool.has(\.stringValue, "closed", within: 2))
        tool.click()
        XCTAssertTrue(tool.has(\.stringValue, "open", within: 2))
        XCTAssertTrue(row(pane, "tool.input", "command: echo hello").exists(within: 2))
        XCTAssertTrue(row(pane, "tool.output", "hello").exists)
        let composer = element("chat.\(pane).composer")
        let one = composer.frame.height
        var heights: [Int: CGFloat] = [:]
        app.typeText("1")
        for line in 2 ... 7 {
            app.typeKey(.return, modifierFlags: line.isMultiple(of: 2) ? .shift : .option)
            app.typeText("\(line)")
            XCTAssertTrue(until(2) { composer.stringValue.hasSuffix("\n\(line)") })
            heights[line] = composer.frame.height
        }
        XCTAssertGreaterThan(heights[3] ?? 0, one * 2.5, "\(one) \(heights)")
        XCTAssertGreaterThan(heights[5] ?? 0, heights[4] ?? 0, "\(heights)")
        XCTAssertEqual(heights[7], heights[5], "\(heights)")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])

        app.typeKey("d", modifierFlags: .command)
        let chooser = try await replaced(pane, in: tab, besides: [pane])
        XCTAssertTrue(element("pane.\(chooser).chooser.terminal").exists(within: 3))
        let unfocused = NSPredicate(format: "hasKeyboardFocus == false")
        XCTAssertTrue(until(2) { unfocused.evaluate(with: composer) })
        let word = reply.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 12, dy: 0))
        word.click()
        XCTAssertTrue(hasKeyboard(composer))
        NSPasteboard.general.clearContents()
        word.doubleClick()
        XCTAssertTrue(until(2) { unfocused.evaluate(with: composer) })
        app.typeKey("c", modifierFlags: .command)
        composer.click()
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(until(2) { composer.stringValue == "Echo" }, composer.stringValue)
        element("pane.\(chooser).chooser.terminal").click()
        XCTAssertTrue(until(2) { unfocused.evaluate(with: composer) })
        element("chat.\(pane)").coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.2)).click()
        XCTAssertTrue(hasKeyboard(composer))
    }

    func testAChatShowsTheTerminalWhileItWaitsAndAnswersQuestions() async throws {
        let (tab, pane) = try await startChat()
        try await say("wait", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        XCTAssertFalse(element("chat.\(pane).composer").exists)
        let state = element("pane.\(pane).state")
        XCTAssertEqual(state.stringValue, "Needs you")
        XCTAssertGreaterThanOrEqual(state.frame.minY, element("pane.\(pane).title").frame.maxY)
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))

        try await say("ask", in: pane)
        let pear = element("chat.\(pane).option.Pear")
        XCTAssertTrue(pear.exists(within: 5))
        keepScreenshot("question")
        pear.click()
        XCTAssertTrue(row(pane, "reply", "You chose Pear.").exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).question").vanishes(within: 5))
        try await say("big", in: pane)
        XCTAssertTrue(row(pane, "reply", "Big.").exists(within: 5))

        relaunch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(pane).view.tui").has(\.isSelected, true, within: 10))
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(row(pane, "reply", "Big.").exists(within: 5))
        XCTAssertTrue(row(pane, "user", "wait").exists)
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists)
    }

    func testAChatOnARemoteMachine() async throws {
        step("A Claude Code chat on a remote machine")
        try await skipWithoutSSH()
        relaunch(one, Self.onKeyHost)
        let pane = try await startChat().pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await say("ask", in: pane)
        let pear = element("chat.\(pane).option.Pear")
        XCTAssertTrue(pear.exists(within: 5))
        pear.click()
        XCTAssertTrue(row(pane, "reply", "You chose Pear.").exists(within: 5))

        step("A pi chat on a remote machine")
        let piChat = try await startChat(agent: 2).pane
        try await say("hello", in: piChat)
        XCTAssertTrue(row(piChat, "reply", "Echo: **hello**").exists(within: 5))
        try await say("wait", in: piChat)
        let drawer = element("chat.\(piChat).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(piChat, "reply", "Allowed.").exists(within: 5))

        step("An OpenCode chat on a remote machine")
        let openCode = try await startChat(agent: 3).pane
        try await say("hello", in: openCode)
        XCTAssertTrue(row(openCode, "reply", "Echo: **hello**").exists(within: 5))
        try await say("allow", in: openCode)
        let allow = element("chat.\(openCode).option.Allow once")
        XCTAssertTrue(allow.exists(within: 5))
        allow.click()
        XCTAssertTrue(row(openCode, "reply", "Allowed.").exists(within: 5))
    }

    /// The stand-in quits 12 s after `/exit`, as Claude Code with slow SessionEnd hooks: the wait for it is longer than
    /// that.
    func testEnableChatStartsAnAgentAgainInItsSession() async throws {
        let (tab, pane) = try await startChat(["-appearance", "dark"], environment: "OVVI_STAND_IN_EXIT_HOOKS=12 ",
                                              chat: false, plain: true)
        let enable = element("pane.\(pane).enable-chat")
        XCTAssertTrue(enable.exists(within: 10))
        XCTAssertEqual(enable.label, "Relaunch with Chat")
        XCTAssertTrue(until(3) { self.twoRows(pane, title: "Untitled", above: "pane.\(pane).enable-chat") })
        let label = { self.element("tab.\(tab)").label }
        XCTAssertTrue(until(3) { label().contains("Claude Code Untitled") }, label())
        try await send("hello\r", to: pane)
        try await waitFor(pane) { $0.contains("Echo: **hello**") }
        keepScreenshot("enable-chat")
        enable.click()
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 35))
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        XCTAssertEqual(element("chat.\(pane).model").stringValue, "claude-stand-in · high")
        XCTAssertFalse(enable.exists)
    }

    /// A floating pane's title row has the same agent control: Relaunch with Chat there brings its chat into the float.
    func testRelaunchWithChatFromAFloatingPane() async throws {
        let pane = try await startChat(chat: false, plain: true).pane
        XCTAssertTrue(element("pane.\(pane).enable-chat").exists(within: 10))
        let window = float(pane)
        XCTAssertTrue(element("float.\(pane).info", in: window).exists(within: 5))
        keepScreenshot("float relaunch", of: window)
        let enable = element("pane.\(pane).enable-chat", in: window)
        XCTAssertTrue(enable.exists(within: 5))
        enable.click()
        XCTAssertTrue(element("pane.\(pane).loader", in: window).exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).composer", in: window).exists(within: 30))
        XCTAssertTrue(element("pane.\(pane).view.chat", in: window).exists)
        keepScreenshot("float chat", of: window)
        element("float.\(pane).detach", in: window).click()
        XCTAssertTrue(window.vanishes(within: 3))
    }

    /// The retry's agent lists no arguments, as npm's pi whose process title overwrites them.
    func testRelaunchSaysWhyAndRetriesWithoutArguments() async throws {
        let failed = NSTemporaryDirectory() + "ovvi-fail-resume-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: failed) }
        let environment = "OVVI_STAND_IN_TITLE=1 OVVI_STAND_IN_FAIL_RESUME=\(failed) "
        let pane = try await startChat(environment: environment, chat: false, plain: true).pane
        let enable = element("pane.\(pane).enable-chat")
        XCTAssertTrue(enable.exists(within: 10))
        try await send("hello\r", to: pane)
        try await waitFor(pane) { $0.contains("Echo: **hello**") }
        enable.click()
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts.matching(NSPredicate(format: "value == 'Claude Code did not start again'"))
            .firstMatch.exists(within: 20))
        notice.hover()
        keepScreenshot("relaunch failed")
        notice.buttons["notice.retry"].click()
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 20))
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        XCTAssertFalse(enable.exists)
    }

    func startChat(_ arguments: [String] = [], agent: Int = 0, environment: String = "", chat: Bool = true,
                   plain: Bool = false) async throws -> (tab: String, pane: String)
    {
        if !arguments.isEmpty {
            relaunch(one, arguments)
        }
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        let tabs = try await tabIDs()
        closeNew("tab", besides: tabs)
        app.typeKey("t", modifierFlags: .command)
        let tab = try await newTabID(after: tabs)
        let pane = try await pane(of: tab)
        XCTAssertTrue(element("pane.\(pane).chooser.terminal").exists(within: 3))
        try await waitForPrompt(pane)
        // `function`: a user's own alias of the command does not expand in it.
        let command = ["claude", "codex", "pi", "opencode"][agent]
        let standIn = Self.scripts.appending(path: "\(command)-stand-in.py").path
        try await send("function \(command) { \(environment)python3 '\(standIn)' \"$@\"; }\r", to: pane)
        if plain {
            app.typeKey(.escape, modifierFlags: [])
            try await send("\(command)\r", to: pane)
            return (tab, pane)
        }
        app.typeKey("2", modifierFlags: [])
        app.typeKey("\(agent + 1)", modifierFlags: [])
        guard chat else { return (tab, pane) }
        let tui = element("pane.\(pane).view.tui")
        XCTAssertTrue(tui.exists(within: 15))
        XCTAssertTrue(tui.isSelected)
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        element("pane.\(pane).view.chat").click()
        let composer = element("chat.\(pane).composer")
        XCTAssertTrue(composer.exists(within: 3))
        XCTAssertTrue(hasKeyboard(composer))
        return (tab, pane)
    }

    func say(_ text: String, in pane: String) async throws {
        app.typeText(text + "\r")
        XCTAssertTrue(row(pane, "user", text).exists(within: 5))
    }

    func row(_ pane: String, _ kind: String, _ value: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "chat.\(pane).\(kind)", value)).firstMatch
    }
}
