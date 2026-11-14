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
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder").windows["build"]
        XCTAssertTrue(finder.exists(within: 5))
        finder.buttons[XCUIIdentifierCloseWindow].click()
        app.activate()

        step("⌘⌥-click on a Git change row opens its file in the Mac's app for it")
        let git = try await split(card)
        try await Self.call(one, "pane.rename", ["pane_id": git, "label": "ovvi:git#e2ekgt \(root)/"])
        let changed = element("git.\(git).page").buttons["Modified: a.txt"]
        XCTAssertTrue(changed.exists(within: 10))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) { changed.click() }
        let editor = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        XCTAssertTrue(editor.windows["a.txt"].exists(within: 10))
        editor.terminate()
        app.activate()
        let now = try await tabIDs()
        XCTAssertEqual(now.count, tabs, "\(now)")
        try await show(tab)
        try await send("rm -rf \(repo)\r", to: shell)
    }

    /// ⇧⌘., as Finder's: the dotfiles show, with the eye on, dimmed while the setting says so; again, they go.
    func togglesDotfiles(_ card: String, _ tree: XCUIElement) {
        let eye = element("pane.\(card).hidden-files")
        XCTAssertFalse(row(".gitignore", in: tree).exists || eye.isSelected)
        app.typeKey(".", modifierFlags: [.command, .shift])
        XCTAssertTrue(row(".gitignore", in: tree).exists(within: 5))
        XCTAssertTrue(eye.has(\.isSelected, true, within: 3))
        XCTAssertTrue(dimmed(".gitignore", in: tree).exists(within: 3))
        XCTAssertFalse(dimmed("a.txt", in: tree).exists)
        addTeardownBlock { @MainActor [self] in
            if testRun?.hasSucceeded == false {
                explorerDims(true)
            }
        }
        explorerDims(false)
        XCTAssertTrue(dimmed(".gitignore", in: tree).vanishes(within: 5))
        explorerDims(true)
        XCTAssertTrue(dimmed(".gitignore", in: tree).exists(within: 5))
        app.typeKey(".", modifierFlags: [.command, .shift])
        XCTAssertTrue(row(".gitignore", in: tree).vanishes(within: 5))
        XCTAssertTrue(eye.has(\.isSelected, false, within: 3))
    }

    /// A dimmed row's word for VoiceOver, drawn nowhere.
    private func dimmed(_ name: String, in tree: XCUIElement) -> XCUIElement {
        row(name, in: tree).descendants(matching: .any).matching(NSPredicate(format: "value == 'Hidden'")).firstMatch
    }

    /// Settings ▸ Plugins ▸ File Explorer ▸ Dim ignored and hidden files, through General: Plugins opens on its list.
    private func explorerDims(_ dims: Bool) {
        openSettings("general")
        element("settings.page.plugins").click()
        element("plugins.explorer").click()
        turn("plugins.explorer.setting.dim", dims)
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))
    }
}
