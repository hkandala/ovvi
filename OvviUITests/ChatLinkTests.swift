import XCTest

extension OvviUITests {
    /// A path in the chat is a link, as in the terminal: ⌘-click opens it in a new tab in the background, ⌥-click
    /// to the side, a plain click in a new tab, selected.
    func testALinkInAChatOpensAsInTheTerminal() async throws {
        let folder = "/tmp/ovvi-e2e-chat-links", file = "\(folder)/notes.md"
        // The agent's shell function makes the file first: the tests' runner may not write /tmp.
        let (tab, pane) = try await startChat(environment: "rm -rf \(folder); mkdir \(folder); touch \(file); ")
        // Not at its start: a message that starts with `/` is a command, for the TUI.
        try await say("see \(file):1", in: pane)
        let reply = row(pane, "reply", "Echo: **see \(file):1**")
        XCTAssertTrue(reply.exists(within: 5))
        // The link ends each line: its last characters.
        let end = { (element: XCUIElement) in
            element.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -12, dy: 0))
        }

        step("⌘-click opens it in a new tab, in the background")
        var tabs = try await tabIDs()
        end(reply).hover()
        keepScreenshot("a link under the pointer")
        XCUIElement.perform(withKeyModifiers: .command) { end(reply).click() }
        let opened = try await newTabID(after: tabs)
        closeAfter("tab", opened)
        try await labelEnds(self.pane(of: opened), " \(file)")
        XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected })

        step("A plain click opens it in a new tab, selected")
        tabs = try await tabIDs()
        end(row(pane, "user", "see \(file):1")).click()
        let selected = try await newTabID(after: tabs)
        closeAfter("tab", selected)
        try await labelEnds(self.pane(of: selected), " \(file)")
        XCTAssertTrue(element("tab.\(selected)").has(\.isSelected, true, within: 3))

        step("⌥-click opens it to the side")
        element("tab.\(tab)").click()
        // The reply exists on the hidden page too: the shown page's reply box takes the keys once its page is drawn.
        // Then the click has the green ⌘ step's shape: the pointer on the link before the key goes down.
        XCTAssertTrue(hasKeyboard("chat.\(pane).composer"), "the chat's page did not show again")
        end(reply).hover()
        XCUIElement.perform(withKeyModifiers: .option) { end(reply).click() }
        try await labelEnds(sidePane(in: tab, besides: [pane]), " \(file)")
    }
}
