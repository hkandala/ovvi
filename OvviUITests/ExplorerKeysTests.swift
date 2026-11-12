import XCTest

extension OvviUITests {
    func testExplorerSwitchesTheKeyboardAndOpensInTheMacsApps() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("files keys")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-keys", root = "/private/tmp/ovvi-e2e-keys"
        try await makeTreeRepo(repo, in: shell)
        let card = try await newCard("ovvi:explorer#e2ekey \(root)/a.txt", cwd: repo).pane
        let file = element("file.\(card).page"), toggle = element("pane.\(card).tree")
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        if toggle.isSelected {
            toggle.click()
        }
        XCTAssertTrue(toggle.has(\.isSelected, false, within: 3))

        step("⇧⌘E shows the hidden tree and gives the file's row the keyboard; again, back to the file")
        XCTAssertTrue(app.menuBars.menuBarItems["View"].menuItems["Switch Between Tree and File"].exists)
        file.textViews.firstMatch.click()
        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertTrue(toggle.has(\.isSelected, true, within: 3))
        XCTAssertTrue(row("a.txt", in: file).exists(within: 10))
        XCTAssertTrue(hasKeyboard(row("a.txt", in: file)))
        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertTrue(hasKeyboard(file.textViews.firstMatch))
        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertTrue(hasKeyboard(row("a.txt", in: file)))

        step("⌘⌥-click on a folder shows it in the Finder, outside Ovvi")
        let tabs = try await tabIDs().count
        XCUIElement.perform(withKeyModifiers: [.command, .option]) { row("build", in: file).click() }
        finder("build")

        step("⌘⌥-click on a Git change row shows its folder in the Finder")
        try await send("mkdir -p \(repo)/fresh && touch \(repo)/fresh/x\r", to: shell)
        let git = try await split(card)
        try await Self.call(one, "pane.rename", ["pane_id": git, "label": "ovvi:git#e2ekgt \(root)/"])
        let fresh = element("git.\(git).page").buttons["Untracked: fresh"]
        XCTAssertTrue(fresh.exists(within: 10))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) { fresh.click() }
        finder("fresh")
        let now = try await tabIDs()
        XCTAssertEqual(now.count, tabs, "\(now)")
        try await show(tab)
        try await send("rm -rf \(repo)\r", to: shell)
    }

    private func finder(_ folder: String) {
        let window = XCUIApplication(bundleIdentifier: "com.apple.finder").windows[folder]
        XCTAssertTrue(window.exists(within: 5), folder)
        window.buttons[XCUIIdentifierCloseWindow].click()
        app.activate()
    }
}
