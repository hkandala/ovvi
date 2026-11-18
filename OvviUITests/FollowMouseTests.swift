import XCTest

extension OvviUITests {
    /// Focus follows mouse: the card under the pointer takes the keyboard, a browser's as a plugin's or a terminal's,
    /// also after typing in a web page (a text panel shows), and a field its page focused keeps its focus. A chat's
    /// reply box gives the keys up as a terminal does.
    func testFocusFollowsTheMouseOntoEveryCard() async throws {
        let (tab, shell) = try await newTab("follow")
        try await waitForPrompt(shell)
        let root = "/private/tmp/ovvi-e2e-follow"
        try await send("rm -rf \(root) && mkdir -p \(root) && printf '<input oninput=\"document.title=this.value\" "
            + "aria-label=ovvi-follow-field>' >\(root)/page.html && clear && echo made-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
        sendAfter("rm -rf \(root)\r", to: shell)
        relaunch(one, ["-focusFollowsMouse", "YES", "-recordMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        try await show(tab)
        let browser = try await split(shell), explorer = try await split(browser, "down")
        try await relabel(browser, "ovvi:browser#e2effb file://\(root)/page.html")
        try await relabel(explorer, "ovvi:explorer#e2effe \(root)/")
        try await show(tab)
        let field = element("browser.\(browser).card").textFields["ovvi-follow-field"]
        XCTAssertTrue(field.exists(within: 10))
        XCTAssertTrue(element("pane.\(explorer).title").exists(within: 10))
        let terminal = element("terminal.\(shell)")
        terminal.click()
        XCTAssertTrue(hasKeyboard(terminal), "the keyboard is on \(keyboardOwner())")
        for card in [explorer, browser] {
            element("pane.\(card)").hover()
            XCTAssertTrue(element("pane.\(card).border").exists(within: 2), "\(card) is not lit")
            XCTAssertTrue(lostKeys(terminal), "the keyboard stayed on \(shell) under the pointer on \(card)")
            terminal.hover()
            XCTAssertTrue(hasKeyboard(terminal), "the keyboard is on \(keyboardOwner())")
        }

        field.click()
        app.typeText("a")
        let title = element("pane.\(browser).title")
        XCTAssertTrue(title.has(\.stringValue, "a", within: 3), title.stringValue)
        terminal.hover()
        XCTAssertTrue(hasKeyboard(terminal), "the keyboard is on \(keyboardOwner())")
        element("pane.\(browser)").hover()
        XCTAssertTrue(lostKeys(terminal), "the keyboard stayed on \(shell)")
        app.typeText("b")
        XCTAssertTrue(title.has(\.stringValue, "ab", within: 3), title.stringValue)

        try await chatBesideABrowser(root)
    }

    private func chatBesideABrowser(_ root: String) async throws {
        let chat = try await startChat().pane
        let side = try await split(chat)
        try await relabel(side, "ovvi:browser#e2effc file://\(root)/page.html")
        XCTAssertTrue(element("browser.\(side).card").textFields["ovvi-follow-field"].exists(within: 10))
        let composer = element("chat.\(chat).composer")
        composer.click()
        XCTAssertTrue(hasKeyboard(composer), "the keyboard is on \(keyboardOwner())")
        element("pane.\(side)").hover()
        XCTAssertTrue(element("pane.\(side).border").exists(within: 2), "\(side) is not lit")
        XCTAssertTrue(lostKeys(composer), "the keyboard stayed in the reply box")
        composer.hover()
        XCTAssertTrue(hasKeyboard(composer), "the keyboard is on \(keyboardOwner())")
    }

    private func lostKeys(_ element: XCUIElement) -> Bool {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        return until(2) { !focused.evaluate(with: element) }
    }
}
