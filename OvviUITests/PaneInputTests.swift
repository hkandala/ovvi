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

        // A program that reads clicks and drags (SGR mouse mode) sees the ⌥-right click as a plain right press: button
        // 2, not 10 (Alt adds 8). Without ⌥ the menu opens over it.
        try await send("\u{15}clear; printf '\\033[?1002h\\033[?1006h'; cat -v\r", to: pane)
        try await expect("cat to run") { try await foreground(pane).contains("cat") }
        XCUIElement.perform(withKeyModifiers: .option) { terminal.rightClick() }
        try await waitFor(pane) { $0.contains("[<2;") }
        XCTAssertFalse(menu["Copy"].exists)
        terminal.rightClick()
        XCTAssertTrue(menu["Copy"].exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])

        // A left click reaches it as a press and a release, and so does a drag, with its moves (pi selects and copies
        // so), which also selects in the card. The ⌥-right click after the drag bounds the wait. Reports wrap.
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
        XCTAssertTrue(reports(0, text) == 4 && reports(32, text) > 0, text)
    }

    /// A program that reads the mouse (as pi does) gets the drag and selects from the press's cell to the pointer's in
    /// reverse video, which herdr draws black on white. The card selects the same cells: no white cell shows, and the
    /// cells past the ends stay unselected (a word selection would reach them). The program's white mark moves with
    /// each release: its frame has drawn.
    func testADragSelectsInTheProgramAndInTheCard() async throws {
        relaunch(one, ["-appearance", "dark"])
        let (tab, pane) = try await newTab("select")
        element("tab.\(tab)").click()
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.has(\.isHittable, true, within: 3))
        // Off the tab: its hover card would cover the program's mark in the screenshots.
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).hover()
        try await waitForPrompt(pane)
        try await send("clear; '\(Self.fixtures)/mouse-select'\r", to: pane)
        try await waitFor(pane, toShow: "drags 0 releases 0")
        let grid = (terminal.value as? String ?? "").split(separator: " ").compactMap { Int($0) }
        let rows = try XCTUnwrap(grid.first)
        // The second mark ends at column 52.
        XCTAssertGreaterThanOrEqual(grid.last ?? 0, 52)
        // The cells in the screenshot's pixels, from the first mark: 6 cells from column 30.
        let first = try await poll("the program's mark") { () -> Shot? in
            Shot(terminal.screenshot().image, rows: rows).flatMap { $0.whites(row: 0).isEmpty ? nil : $0 }
        }
        let marked = first.whites(row: 0), width = try Double(XCTUnwrap(marked.max()) - XCTUnwrap(marked.min()) + 1) / 6
        let origin = try Double(XCTUnwrap(marked.min())) - 30 * width, card = terminal.frame,
            scale = Double(first.width) / card.width
        func spot(_ column: Double) -> String {
            "\(card.minX + (origin + column * width) / scale) \(card.minY + 1.5 * first.height / scale)"
        }
        // Each end inside its cell on the side where libghostty's own rule leaves the cell out; the second drag goes
        // forward first, then back past its press. The program selects 2...8, then 1...5.
        for (releases, drag, ends) in [(1, "\(spot(2.8)) \(spot(8.2)) 0.3", (2, 8)),
                                       (2, "\(spot(5.3)) \(spot(10.8)) 0.3 \(spot(1.8)) 0.3", (1, 5))]
        {
            _ = try await Self.post("\(one)/drag", Data(drag.utf8))
            try await waitFor(pane) { $0.contains("releases \(releases)") && !$0.contains("drags 0 ") }
            let mark = Int(origin + (30 + 8 * Double(releases) + 3) * width)
            let shot = try await poll("the program's frame after release \(releases)") { () -> Shot? in
                Shot(terminal.screenshot().image, rows: rows).flatMap { $0.whites(row: 0).contains(mark) ? $0 : nil }
            }
            let attachment = XCTAttachment(image: shot.image)
            (attachment.name, attachment.lifetime) = ("selection \(releases)", .keepAlways)
            add(attachment)
            func blue(_ column: Int) -> Int {
                shot.blue(Int(origin + Double(column) * width), Int(width), row: 1)
            }
            XCTAssertTrue(shot.whites(row: 1).isEmpty, "a white cell beside the selection")
            for (end, past) in [(ends.0, ends.0 - 1), (ends.1, ends.1 + 1)] {
                XCTAssertGreaterThan(blue(end), blue(past) + 20, "cell \(end) selected, cell \(past) not")
                XCTAssertLessThan(blue(past), blue(40) + 10, "cell \(past) not selected")
            }
        }
    }

    /// A terminal's screenshot: rows of `height` pixels.
    @MainActor private struct Shot {
        let image: NSImage, pixels: [UInt8], width: Int, height: Double

        init?(_ image: NSImage, rows: Int) {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            (self.image, pixels, width) = (image, OvviUITests.pixels(image), cgImage.width)
            height = Double(cgImage.height) / Double(rows)
        }

        /// The middle half of a row's lines.
        private func lines(_ row: Int) -> Range<Int> {
            Int((Double(row) + 0.25) * height) ..< Int((Double(row) + 0.75) * height)
        }

        private func rgb(_ across: Int, _ line: Int) -> [Int] {
            (0 ..< 3).map { Int(pixels[(line * width + across) * 4 + $0]) }
        }

        /// The columns of pure white pixels in a row.
        func whites(row: Int) -> Set<Int> {
            Set(lines(row).flatMap { line in (0 ..< width).filter { rgb($0, line).allSatisfy { $0 >= 250 } } })
        }

        /// Blue over red, on average, in the middle half of a cell `wide` pixels from `left`.
        func blue(_ left: Int, _ wide: Int, row: Int) -> Int {
            let cells = lines(row).flatMap { line in (left + wide / 4 ..< left + wide * 3 / 4).map { rgb($0, line) } }
            return cells.reduce(0) { $0 + $1[2] - $1[0] } / max(cells.count, 1)
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
        // macOS puts U+202F before a screenshot's AM; only the ASCII spaces need escapes.
        let name = #"drop\ me\'s\ \(1\)\ at\ 12.31"# + "\u{202F}AM.txt"
        try await waitFor(pane, toShow: "\(folder)/\(name)")
        try await commandClickOpens(path, at: "cat \(URL(filePath: path).deletingLastPathComponent().path)/\(name)",
                                    in: pane)

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

    /// ⌘-click on the pasted path's last cells, past its escapes and its U+202F, opens the real file.
    private func commandClickOpens(_ path: String, at typed: String, in pane: String) async throws {
        step("A ⌘-click on the pasted path's end opens the file")
        let terminal = element("terminal.\(pane)")
        let grid = try XCTUnwrap(terminal.value as? String).split(separator: " ").compactMap { Double($0) }
        let rows = try await read(pane).split(separator: "\n", omittingEmptySubsequences: false)
        let row = try XCTUnwrap(rows.lastIndex { $0.contains("cat /") }, "\(rows)")
        let start = try XCTUnwrap(rows[row].range(of: "cat /")).lowerBound
        // The line starts at that row and wraps at the grid's width; every character here takes one cell.
        let index = rows[row].distance(from: rows[row].startIndex, to: start) + typed.count - 2
        let cell = CGSize(width: terminal.frame.width / grid[1], height: terminal.frame.height / grid[0])
        let point = terminal.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: cell.width * (Double(index % Int(grid[1])) + 0.5),
            dy: cell.height * (Double(row + index / Int(grid[1])) + 0.5),
        ))
        let before = try await tabIDs()
        point.hover()
        XCUIElement.perform(withKeyModifiers: .command) { point.click() }
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        try await labelEnds(pane(of: opened), " \(path)")
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
