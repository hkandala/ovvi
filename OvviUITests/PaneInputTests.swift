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

        // A left click reaches it as a press and a release, and so does a drag, which also selects in the card. The
        // ⌥-right click after the drag bounds the wait. Reports wrap.
        func reports(_ button: Int, _ text: String) -> Int {
            text.replacing("\n", with: "").components(separatedBy: "[<\(button);").count - 1
        }
        terminal.click()
        try await waitFor(pane) { reports(0, $0) == 2 }
        let rights = try await reports(2, read(pane))
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02))
            .click(forDuration: 0.2, thenDragTo: terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.02)))
        NSPasteboard.general.clearContents()
        app.typeKey("c", modifierFlags: .command)
        try await expect("⌘C to copy the card's selection") {
            NSPasteboard.general.string(forType: .string)?.contains("[<") == true
        }
        XCUIElement.perform(withKeyModifiers: .option) { terminal.rightClick() }
        try await waitFor(pane) { reports(2, $0) > rights }
        let text = try await read(pane)
        XCTAssertEqual(reports(0, text), 4, text)
    }

    /// A program that reads the mouse (as pi does) gets the drag and selects from the press's cell to the pointer's in
    /// reverse video, which herdr draws black on white. The card's selection covers it, ends included: no white cell.
    /// The program's white mark after a release shows that its frame has drawn.
    func testADragSelectsInTheProgramAndInTheCard() async throws {
        relaunch(one, ["-appearance", "dark"])
        let (tab, pane) = try await newTab("select")
        element("tab.\(tab)").click()
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.has(\.isHittable, true, within: 3))
        try await waitForPrompt(pane)
        try await send("clear; '\(Self.fixtures)/mouse-select'\r", to: pane)
        try await waitFor(pane, toShow: "drags 0 releases 0")
        let grid = (terminal.value as? String ?? "").split(separator: " ").compactMap { Int($0) }
        let rows = try XCTUnwrap(grid.first), columns = try XCTUnwrap(grid.last), card = terminal.frame
        func spot(_ column: Double) -> String {
            "\(card.minX + column * card.width / Double(columns)) \(card.minY + 1.5 * card.height / Double(rows))"
        }
        // Each end inside its cell on the side where libghostty's own rule leaves the cell out; the second drag goes
        // forward first, then back past its press.
        for (releases, drag) in [(1, "\(spot(2.8)) \(spot(8.3)) 0.3"),
                                 (2, "\(spot(5.3)) \(spot(10.8)) 0.3 \(spot(1.8)) 0.3")]
        {
            _ = try await Self.post("\(one)/drag", Data(drag.utf8))
            try await waitFor(pane) { $0.contains("releases \(releases)") && !$0.contains("drags 0 ") }
            let image = try await poll("the program's frame after release \(releases)") { () -> NSImage? in
                let image = terminal.screenshot().image
                return band(image, row: 0, of: rows).contains { $0.allSatisfy { $0 >= 250 } } ? image : nil
            }
            add(XCTAttachment(image: image))
            let selected = band(image, row: 1, of: rows)
            XCTAssertFalse(selected.contains { $0.allSatisfy { $0 >= 250 } }, "a white cell beside the selection")
            XCTAssertTrue(selected.contains { $0[2] > $0[0] + 30 }, "the card's selection")
        }
    }

    /// The middle half of a row of cells, as red, green and blue.
    private func band(_ image: NSImage, row: Int, of rows: Int) -> [[Int]] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let pixels = Self.pixels(image), width = cgImage.width, height = Double(cgImage.height) / Double(rows)
        return (Int((Double(row) + 0.25) * height) ..< Int((Double(row) + 0.75) * height)).flatMap { line in
            (0 ..< width).map { across in (0 ..< 3).map { Int(pixels[(line * width + across) * 4 + $0]) } }
        }
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

    func testAClickOnACardsHeaderGivesItTheKeyboard() async throws {
        let (tab, first) = try await newTab("header click")
        let second = try await split(first)
        element("tab.\(tab)").click()
        try await waitForPrompt(first)
        try await waitForPrompt(second)
        element("terminal.\(second)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(second)"), "the keyboard is on \(keyboardOwner())")
        // The title row's middle: the title passes clicks through, and the buttons sit at its end.
        element("pane.\(first)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 17)).click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)"), "the keyboard is on \(keyboardOwner())")
        try await typeAndRead(first)
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
        XCTAssertFalse(until(0.5) { !NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: card) })
    }
}
