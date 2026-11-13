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
        let question = element("keys.tab.new.question", in: settingsWindow)
        XCTAssertTrue(question.exists(within: 2))
        XCTAssertEqual(newTab.stringValue, "⌘W")
        // The field showed the key it asked about: Cancel gives the saved one back.
        element("keys.tab.new.cancel", in: settingsWindow).click()
        XCTAssertTrue(question.vanishes(within: 2))
        XCTAssertEqual(newTab.stringValue, "⌘T")
        newTab.click()
        settingsWindow.typeKey("y", modifierFlags: [.command, .option])
        XCTAssertTrue(newTab.has(\.stringValue, "⌥⌘Y", within: 2))
        XCTAssertTrue(element("keys.tab.new.reset", in: settingsWindow).isEnabled)

        // A key another action has asks first; Swap gives that one the key given up.
        newSpace.click()
        settingsWindow.typeKey("y", modifierFlags: [.command, .option])
        let swap = element("keys.space.new.swap", in: settingsWindow)
        XCTAssertTrue(swap.exists(within: 2))
        XCTAssertEqual(newSpace.stringValue, "⌥⌘Y")
        XCTAssertEqual(newTab.stringValue, "⌥⌘Y")
        swap.click()
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
        XCTAssertEqual(element("keys.app.bigger", in: settingsWindow).stringValue, "⌘+")
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
}
