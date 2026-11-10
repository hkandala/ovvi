import XCTest

extension OvviUITests {
    func testRightClickInATerminalOpensThePaneMenu() async throws {
        let (tab, first) = try await newTab("menu")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").has(\.isHittable, true, within: 3))
        try await waitForPrompt(first)

        element("terminal.\(first)").rightClick()
        let menu = app.windows.firstMatch.menuItems
        for item in ["Copy", "Select All", "Split Right", "Close Pane"] {
            XCTAssertTrue(menu[item].exists(within: 2), item)
        }
        keepScreenshot("terminal menu")
        menu["Split Right"].click()
        let second = try await sidePane(in: tab, besides: [first])
        try await waitForPrompt(second)

        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let (pane, other) = focused.evaluate(with: element("terminal.\(first)")) ? (second, first) : (first, second)
        let terminal = element("terminal.\(pane)")
        let command = "echo ovvi-$((6*4))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        terminal.rightClick()
        XCTAssertTrue(menu["Paste"].exists(within: 2))
        menu["Paste"].click()
        // pane.read wraps lines at the pane's width.
        try await waitFor(pane, toShow: command)
        let elsewhere = try await read(other)
        XCTAssertFalse(elsewhere.replacing("\n", with: "").contains(command))

        // A program that reads clicks (SGR mouse mode) sees the ⌥-right click as a plain right press: button 2, not
        // 10 (Alt adds 8). Without ⌥ the menu opens over it.
        try await send("\u{15}clear; printf '\\033[?1000h\\033[?1006h'; cat -v\r", to: pane)
        try await expect("cat to run") { try await foreground(pane).contains("cat") }
        XCUIElement.perform(withKeyModifiers: .option) { terminal.rightClick() }
        try await waitFor(pane) { $0.contains("[<2;") }
        XCTAssertFalse(menu["Copy"].exists)
        terminal.rightClick()
        XCTAssertTrue(menu["Copy"].exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// The drag comes from a window of the helper's: from Finder, at times no drag starts on CI.
    func testDroppingAFilePastesItsPath() async throws {
        let (tab, pane) = try await newTab("drop")
        let (other, _) = try await createTab(in: workspace(of: tab), label: "over")
        closeAfter("tab", other)
        XCTAssertTrue(element("tab.\(other)").has(\.isHittable, true, within: 5))
        element("tab.\(other)").click()
        XCTAssertTrue(element("page.\(other)").exists(within: 5))
        element("tab.\(tab)").click()
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.has(\.isHittable, true, within: 3))
        try await waitForPrompt(pane)

        let from = element("sidebar").frame, card = terminal.frame
        let points = "\(from.midX) \(from.midY) \(card.midX) \(card.midY)"
        try await send("cat ", to: pane)
        let path = try await String(decoding: Self.post("\(one)/file-drag", Data(points.utf8)), as: UTF8.self)
        let folder = URL(filePath: path).deletingLastPathComponent().lastPathComponent
        let name = #"drop\ me\'s\ \(1\).txt"#
        try await waitFor(pane, toShow: "\(folder)/\(name)")

        try await send(" ", to: pane)
        let temporary = try await String(
            decoding: Self.post("\(one)/temporary-file-drag", Data(points.utf8)),
            as: UTF8.self,
        )
        let line = try await poll("the copy's path") { () async throws -> String? in
            let text = try await read(pane).replacing("\n", with: "")
            return text.components(separatedBy: "\(folder)/\(name) ").last.flatMap { $0.contains(name) ? $0 : nil }
        }
        XCTAssertFalse(line.contains("TemporaryItems"), "pasted \(line) for \(temporary)")
        XCTAssertTrue(line.contains("/ovvi-"), "pasted \(line) for \(temporary)")
        try await Self.call(one, "pane.send_keys", ["pane_id": pane, "keys": ["enter"]])
        try await waitFor(pane) { $0.components(separatedBy: "ovvi-e2e-dropped").count == 3 }

        _ = try await Self.post("\(one)/text-drag", Data("\(points) echo ovvi-e2e-$((6*7))".utf8))
        try await waitFor(pane, toShow: "echo ovvi-e2e-$((6*7))")
        try await Self.call(one, "pane.send_keys", ["pane_id": pane, "keys": ["enter"]])
        try await waitFor(pane) { $0.contains("ovvi-e2e-42") }
    }

    func testAClickBeforeACardDrewKeepsTheKeyboard() async throws {
        let (tab, first) = try await newTab("early click")
        let second = try await split(first)
        try await waitForPrompt(second)
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/resume") }
        _ = try await Self.post("\(one)/pause")
        element("tab.\(tab)").click()
        let card = element("terminal.\(second)")
        XCTAssertTrue(card.has(\.isHittable, true, within: 5))
        XCTAssertEqual(element("pane.\(second)").stringValue, "loading")
        card.click()
        _ = try await Self.post("\(one)/resume")
        XCTAssertTrue(drawn(first, within: 10) && drawn(second, within: 10))
        XCTAssertTrue(hasKeyboard(card), "the keyboard is on \(keyboardOwner())")
        XCTAssertFalse(until(1) { !NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: card) })
    }
}
