import XCTest

/// Settings ▸ Shortcuts saves to the tests' config folder: each test resets what it records.
extension OvviUITests {
    func testARecordedKeyShowsEverywhereAndASwapMovesTheOther() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openSettings("shortcuts")
        // Last in the sidebar.
        XCTAssertGreaterThan(element("settings.page.shortcuts", in: settingsWindow).frame.minY,
                             element("settings.page.privacy", in: settingsWindow).frame.maxY - 1)
        addTeardownBlock { @MainActor [self] in
            openSettings("shortcuts")
            let reset = element("keys.reset-all", in: settingsWindow)
            reset.click()
            XCTAssertTrue(reset.has(\.isEnabled, false, within: 2))
        }
        escapeDeleteAndPlugins()
        recordAndSwap()

        // The menu bar, the palette, the ⌘/ panel and a tooltip read the new keys.
        XCTAssertTrue(element("titlebar.new-tab").label.hasSuffix("⌃⌘T"), element("titlebar.new-tab").label)
        openPalette()
        app.typeText("new tab")
        let row = element("palette.command.New Tab")
        XCTAssertTrue(row.exists(within: 2))
        XCTAssertTrue(row.label.hasSuffix("⌃⌘T"), row.label)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(element("shortcuts.New Tab").has(\.stringValue, "⌃⌘T", within: 2))
        XCTAssertEqual(element("shortcuts.New Space").stringValue, "⌥⌘Y")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("shortcuts").vanishes(within: 2))

        let tabs = try await Self.ids("tab", in: one), spaces = try await Self.ids("workspace", in: one)
        closeNew("tab", besides: tabs)
        element("terminal.w1:p1").click()
        app.typeKey("t", modifierFlags: [.command, .control])
        _ = try await newTabID(after: tabs)
        let after = try await Self.ids("workspace", in: one)
        XCTAssertEqual(after, spaces)
    }

    /// New Tab gets ⌥⌘Y, then gives it to New Space for New Space's ⌃⌘T.
    private func recordAndSwap() {
        let newTab = element("keys.tab.new", in: settingsWindow)
        let newSpace = element("keys.space.new", in: settingsWindow)
        newTab.click()
        XCTAssertTrue(newTab.has(\.stringValue, "Type shortcut…", within: 2))
        // ⌘W records: it closes no window.
        settingsWindow.typeKey("w", modifierFlags: .command)
        let question = settingsWindow.sheets.staticTexts["⌘W is Close Pane’s key."]
        XCTAssertTrue(question.exists(within: 2))
        XCTAssertEqual(newTab.stringValue, "⌘W")
        // The field showed the key it asked about: Cancel gives the saved one back.
        settingsWindow.sheets.buttons["Cancel"].click()
        XCTAssertTrue(question.vanishes(within: 2))
        XCTAssertEqual(newTab.stringValue, "⌘T")
        newTab.click()
        settingsWindow.typeKey("y", modifierFlags: [.command, .option])
        XCTAssertTrue(newTab.has(\.stringValue, "⌥⌘Y", within: 2))
        XCTAssertTrue(element("keys.tab.new.reset", in: settingsWindow).isEnabled)

        // A key another action has asks first; Swap gives that one the key given up.
        newSpace.click()
        settingsWindow.typeKey("y", modifierFlags: [.command, .option])
        let swap = settingsWindow.sheets.buttons["Swap"]
        XCTAssertTrue(swap.exists(within: 2))
        XCTAssertTrue(settingsWindow.sheets.staticTexts["New Tab gets ⌃⌘T in its place."].exists)
        XCTAssertEqual(newSpace.stringValue, "⌥⌘Y")
        XCTAssertEqual(newTab.stringValue, "⌥⌘Y")
        swap.click()
        XCTAssertTrue(swap.vanishes(within: 2))
        XCTAssertTrue(newSpace.has(\.stringValue, "⌥⌘Y", within: 2))
        XCTAssertTrue(newTab.has(\.stringValue, "⌃⌘T", within: 2))

        let search = element("keys.search", in: settingsWindow)
        search.click()
        search.typeText("new space")
        XCTAssertTrue(element("keys.tab.new", in: settingsWindow).vanishes(within: 2))
        XCTAssertTrue(newSpace.exists)
        // The page keeps its search while the window is closed.
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))
    }

    /// Esc keeps the keys, Delete clears them and Reset gives the default back; a plugin's commands are a group.
    private func escapeDeleteAndPlugins() {
        let newTab = element("keys.tab.new", in: settingsWindow)
        XCTAssertTrue(newTab.has(\.stringValue, "⌘T", within: 3))
        // One key: ⌘= runs ⌘+ without showing (testSecondShortcuts).
        XCTAssertTrue(element("keys.app.bigger", in: settingsWindow).has(\.stringValue, "⌘+", within: 2))
        newTab.click()
        XCTAssertTrue(newTab.has(\.stringValue, "Type shortcut…", within: 2))
        settingsWindow.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(newTab.has(\.stringValue, "⌘T", within: 2))
        let split = element("keys.pane.split-right", in: settingsWindow)
        split.click()
        settingsWindow.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(split.has(\.stringValue, "None", within: 2))
        element("keys.pane.split-right.reset", in: settingsWindow).click()
        XCTAssertTrue(split.has(\.stringValue, "⌘D", within: 2))
        // A Form builds only the rows in view: File Explorer's group is at the end.
        let search = element("keys.search", in: settingsWindow)
        search.click()
        search.typeText("lock editing")
        XCTAssertTrue(element("keys.plugin.explorer.lock-editing", in: settingsWindow).has(\.stringValue, "⌘E",
                                                                                           within: 2))
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(newTab.exists(within: 2))
    }

    /// ⊕ stacks a second key under the first, which runs a plugin's command too; Use Here takes another action's
    /// key; the × of a recording field removes its key.
    func testAddedKeysStackAndRunAPluginCommand() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("added keys")
        let folder = "/tmp/ovvi-e2e-added-keys"
        try await waitForPrompt(shell)
        try await send("rm -rf \(folder) && mkdir -p \(folder) && printf '# Keys\\n' >\(folder)/notes.md && clear "
            + "&& echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let (_, card) = try await newCard("ovvi:explorer#e2eakc \(folder)/notes.md")
        let read = element("pane.\(card).lock.read"), edit = element("pane.\(card).lock.edit")
        XCTAssertTrue(read.has(\.isSelected, true, within: 10))

        openSettings("shortcuts")
        addTeardownBlock { @MainActor [self] in
            openSettings("shortcuts")
            let reset = element("keys.reset-all", in: settingsWindow)
            reset.click()
            XCTAssertTrue(reset.has(\.isEnabled, false, within: 2))
        }
        let search = element("keys.search", in: settingsWindow)
        search.click()
        search.typeText("lock editing")
        let id = "keys.plugin.explorer.lock-editing", first = element(id, in: settingsWindow)
        let second = element("\(id).1", in: settingsWindow)
        XCTAssertTrue(first.has(\.stringValue, "⌘E", within: 2))
        let add = element("\(id).add", in: settingsWindow)
        first.hover()
        XCTAssertTrue(add.exists(within: 2))
        add.click()
        XCTAssertTrue(second.has(\.stringValue, "Type shortcut…", within: 2))
        settingsWindow.typeKey("y", modifierFlags: [.command, .option])
        XCTAssertTrue(second.has(\.stringValue, "⌥⌘Y", within: 2))
        XCTAssertEqual(first.stringValue, "⌘E")

        useHere(id)

        // The second key runs the command over its card.
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))
        element("markdown.\(card).page").click()
        app.typeKey("y", modifierFlags: [.command, .option])
        XCTAssertTrue(edit.has(\.isSelected, true, within: 3))
        app.typeKey("y", modifierFlags: [.command, .option])
        XCTAssertTrue(read.has(\.isSelected, true, within: 3))

        removeTheSecondKey(id)
    }

    /// An added key that another action has: Cancel drops the new field, Use Here takes the key.
    private func useHere(_ id: String) {
        let second = element("\(id).1", in: settingsWindow), third = element("\(id).2", in: settingsWindow)
        let add = element("\(id).add", in: settingsWindow), search = element("keys.search", in: settingsWindow)
        second.hover()
        add.click()
        XCTAssertTrue(third.has(\.stringValue, "Type shortcut…", within: 2))
        settingsWindow.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.sheets.staticTexts["⌘T is New Tab’s key."].exists(within: 2))
        XCTAssertTrue(settingsWindow.sheets.buttons["Use Here"].exists)
        XCTAssertEqual(third.stringValue, "⌘T")
        settingsWindow.sheets.buttons["Cancel"].click()
        XCTAssertTrue(third.vanishes(within: 2))
        XCTAssertEqual(second.stringValue, "⌥⌘Y")
        second.hover()
        add.click()
        settingsWindow.typeKey("t", modifierFlags: .command)
        settingsWindow.sheets.buttons["Use Here"].click()
        XCTAssertTrue(third.has(\.stringValue, "⌘T", within: 2))
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeText("new tab")
        XCTAssertTrue(element("keys.tab.new", in: settingsWindow).has(\.stringValue, "None", within: 2))
        search.typeKey("a", modifierFlags: .command)
        search.typeText("lock editing")
        XCTAssertTrue(third.has(\.stringValue, "⌘T", within: 2))
    }

    /// A click on a field records into it; its × removes that key only.
    private func removeTheSecondKey(_ id: String) {
        let first = element(id, in: settingsWindow), second = element("\(id).1", in: settingsWindow)
        openSettings("shortcuts")
        XCTAssertTrue(second.has(\.stringValue, "⌥⌘Y", within: 3))
        second.click()
        let remove = element("\(id).remove", in: settingsWindow)
        XCTAssertTrue(remove.exists(within: 2))
        remove.click()
        XCTAssertTrue(element("\(id).2", in: settingsWindow).vanishes(within: 2))
        XCTAssertEqual(second.stringValue, "⌘T")
        XCTAssertEqual(first.stringValue, "⌘E")
        let search = element("keys.search", in: settingsWindow)
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
    }
}
