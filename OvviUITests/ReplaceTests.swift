import XCTest

extension OvviUITests {
    /// With motion: CI has Reduce Motion on.
    func testReplacingAShellPaneTakesItsPlaceAndFolder() async throws {
        relaunch(one, ["-recordMotion", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("replace")
        let right = try await split(left)
        let below = try await split(right, "down")
        try await settle([tab])
        try await send("cd /usr/bin\r", to: right)
        try await expect("the pane in /usr/bin") { try await pane(right)["cwd"] as? String == "/usr/bin" }
        element("tab.\(tab)").click()
        let card = element("pane.\(right)"), page = element("page.\(tab)")
        func place(_ card: XCUIElement) -> CGRect {
            card.frame.offsetBy(dx: -page.frame.minX, dy: -page.frame.minY)
        }
        let frame = try XCTUnwrap(steady(3) { card.exists ? place(card) : nil })
        element("terminal.\(right)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(right)"))
        let cards = element("cards.\(tab)"), came = cards.stringValue

        app.typeKey("r", modifierFlags: [.command, .shift])
        let new = try await replaced(right, in: tab, besides: [left, below])
        XCTAssertTrue(card.vanishes(within: 3))
        let replaced = element("pane.\(new)")
        XCTAssertTrue(replaced.exists(within: 3))
        XCTAssertFalse(until(1) { cards.stringValue != came }, "cards came, went: \(came), then \(cards.stringValue)")
        XCTAssertTrue(until(3) {
            guard replaced.exists else { return false }
            let now = place(replaced)
            return [now.minX - frame.minX, now.minY - frame.minY, now.width - frame.width, now.height - frame.height]
                .allSatisfy { abs($0) <= 1 }
        }, "\(place(replaced)) is not \(frame)")
        try await expect("the new pane in the old one's folder") {
            try await pane(new)["cwd"] as? String == "/usr/bin"
        }
        try await waitForPrompt(new)
        try await typeAndRead(new)
    }

    func testReplacingKeepsTheZoomAndTheFloatingWindow() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("replace zoom")
        let right = try await split(left)
        try await settle([tab])
        element("tab.\(tab)").click()
        hoverHeader(right)
        element("pane.\(right).zoom").click()
        XCTAssertTrue(element("pane.\(left)").vanishes(within: 2))
        element("terminal.\(right)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(right)"))
        app.typeKey("r", modifierFlags: [.command, .shift])
        let zoomed = try await replaced(right, in: tab, besides: [left])
        XCTAssertTrue(element("pane.\(zoomed)").exists(within: 3))
        XCTAssertFalse(element("pane.\(left)").exists)
        XCTAssertEqual(element("pane.\(zoomed)").frame.width, element("page.\(tab)").frame.width, accuracy: 2)
        try await waitForPrompt(zoomed)
        try await typeAndRead(zoomed)

        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.\(left)").exists(within: 2))

        let window = float(zoomed)
        element("float.\(zoomed).pin").click()
        XCTAssertTrue(hasKeyboard("terminal.\(zoomed)", in: window))
        let frame = window.frame
        app.typeKey("r", modifierFlags: [.command, .shift])
        let floated = try await replaced(zoomed, in: tab, besides: [left])
        XCTAssertTrue(window.vanishes(within: 3))
        let next = app.windows.containing(.any, identifier: "float.\(floated)").firstMatch
        XCTAssertTrue(next.exists(within: 3))
        XCTAssertEqual(next.frame, frame)
        XCTAssertEqual(element("float.\(floated).pin").stringValue, "on")
        try await waitForPrompt(floated)
        try await typeAndRead(floated)
    }

    func replaced(_ old: String, in tab: String, besides others: [String]) async throws -> String {
        try await poll("a new pane in \(old)'s place") { () async throws -> String? in
            let panes = try await (snapshot()["panes"] as? [[String: Any]] ?? [])
                .filter { $0["tab_id"] as? String == tab }.compactMap { $0["pane_id"] as? String }
            let new = panes.filter { !others.contains($0) }
            return Set(others).isSubset(of: panes) && new.count == 1 && new[0] != old ? new[0] : nil
        }
    }

    func testReplacingAPaneRunningAProgramAsks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("replace ask")
        let pane = try await split(left)
        try await settle([tab])
        try await runSleep(pane)
        element("tab.\(tab)").click()
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))

        app.typeKey("r", modifierFlags: [.command, .shift])
        let confirm = app.sheets.buttons["Replace Pane"]
        XCTAssertTrue(confirm.exists(within: 3))
        XCTAssertTrue(until(2) { isRed(confirm) })
        XCTAssertTrue(sheetText("Replace “/private/tmp”?").exists)
        XCTAssertTrue(sheetText("sleep is running in it and will end, here and in every herdr client. "
                + "This cannot be undone.").exists)
        keepScreenshot("replace pane dialog")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(confirm.vanishes(within: 2))
        XCTAssertFalse(element("pane.\(pane)").vanishes(within: 1))
        let running = try await foreground(pane)
        XCTAssertTrue(running.contains("sleep"))

        openPalette()
        app.typeText("replace pane")
        XCTAssertTrue(element("palette.command.Replace Pane").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(confirm.exists(within: 3))
        app.typeKey(.return, modifierFlags: [])
        let new = try await replaced(pane, in: tab, besides: [left])
        XCTAssertTrue(element("pane.\(pane)").vanishes(within: 3))
        XCTAssertTrue(element("pane.\(new)").exists(within: 3))
        try await waitForPrompt(new)
        try await typeAndRead(new)
    }
}

extension OvviUITests {
    func testRedrawTerminalMakesTheProgramRepaint() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("nudge")
        try await settle([tab])
        element("tab.\(tab)").click()
        try await expectPTYSize(pane)
        let grid = try XCTUnwrap(element("terminal.\(pane)").value as? String)
        let size = grid.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(size.count, 2, grid)
        let redraw = ["resized \(size[0]) \(size[1] - 1)", "resized \(grid)"]
        func heard(_ screen: String) -> [String] {
            screen.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("resized") }
        }
        // `clear` wipes the typed line: an answer only the shell prints says the trap is set. Each size on a line of
        // its own: after a long prompt (CI's) it wraps.
        try await send("trap 'echo; echo resized $(stty size)' WINCH; clear; echo armed-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("armed-42") }
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))

        app.typeKey("r", modifierFlags: [.command, .option])
        try await waitFor(pane) { heard($0) == redraw }
        openPalette()
        app.typeText("redraw")
        XCTAssertTrue(element("palette.command.Redraw Terminal").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        try await waitFor(pane) { heard($0) == redraw + redraw }
    }
}
