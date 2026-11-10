import XCTest

/// The size persists in the app's own defaults, so the test puts it back.
extension OvviUITests {
    /// No ⌘=: on CI's 1x display a 1 pt step after ⌘+ keeps the grid.
    func testFontSizeKeys() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        addTeardownBlock { @MainActor [self] in app.typeKey("0", modifierFlags: .command) }
        app.typeKey("0", modifierFlags: .command)
        try await expectPTYSize("w1:p1")
        let actual = try XCTUnwrap(terminal.value as? String)
        let stream = try await pid(of: "w1:p1")

        app.typeKey("+", modifierFlags: .command)
        let bigger = try await expectGrid(terminal, <=, actual)
        try await expectPTYSize("w1:p1")
        app.typeKey("0", modifierFlags: .command)
        try await expectGrid(terminal, actual)
        app.typeKey("+", modifierFlags: .command)
        try await expectGrid(terminal, bigger)
        app.typeKey("-", modifierFlags: .command)
        try await expectGrid(terminal, actual)
        try await expectPTYSize("w1:p1")
        app.typeKey("-", modifierFlags: .command)
        try await expectGrid(terminal, >=, actual)
        let after = try await pid(of: "w1:p1")
        XCTAssertEqual(after, stream, "the stream was not opened again")
    }

    /// libghostty sends Alt by default on CI's keyboard layout.
    func testOptionTypesCharacters() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p1")
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_keys", ["pane_id": "w1:p1", "keys": ["ctrl+c"]])
        }
        try await send("clear; cat -v\r", to: "w1:p1")
        try await expect("cat to run") { try await foreground("w1:p1").contains("cat") }
        terminal.click()
        XCTAssertTrue(hasKeyboard(terminal))
        // Not ⌥⇧ chords or ⌥.: launchers (Raycast) take some as global keys.
        app.typeKey("b", modifierFlags: .option)
        app.typeKey("1", modifierFlags: .option)
        app.typeKey(.return, modifierFlags: [])
        // The tty's echo of the typed line (cat -v prints its own escaped copy under it).
        try await waitFor("w1:p1") { $0.split(separator: "\n").contains("∫¡") }
    }

    /// On a 1x display a 1 pt step can keep the cell width (CI: 14 and 15 pt both 48 columns), so one side may stay.
    @discardableResult
    private func expectGrid(_ terminal: XCUIElement, _ order: (Int, Int) -> Bool,
                            _ grid: String) async throws -> String
    {
        let size = { (grid: String) in grid.split(separator: " ").compactMap { Int($0) } }
        return try await poll("the grid to change from \(grid)") { () -> String? in
            guard let now = terminal.value as? String, size(now).count == 2, now != grid else { return nil }
            return order(size(now)[0], size(grid)[0]) && order(size(now)[1], size(grid)[1]) ? now : nil
        }
    }

    private func expectGrid(_ terminal: XCUIElement, _ grid: String) async throws {
        try await expect("the grid \(grid)") { terminal.value as? String == grid }
    }

    private func pid(of pane: String) async throws -> String {
        let terminal = try await terminalID(pane)
        let line = try await streams(one).first { $0.contains(terminal) }
        return try String(XCTUnwrap(line?.split(separator: " ").first))
    }
}
