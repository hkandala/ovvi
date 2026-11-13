import XCTest

extension OvviUITests {
    func testWorkspaceAndSessionKeysStepAndJump() async throws {
        let alpha = element("workspace.w1"), beta = element("workspace.w2")
        XCTAssertTrue(beta.exists(within: connect))
        XCTAssertTrue(alpha.isSelected)
        app.typeKey("]", modifierFlags: [.command, .control])
        XCTAssertTrue(beta.has(\.isSelected, true, within: 2))
        app.typeKey("[", modifierFlags: [.command, .control])
        XCTAssertTrue(alpha.has(\.isSelected, true, within: 2))
        app.typeKey("[", modifierFlags: [.command, .control])
        XCTAssertTrue(beta.has(\.isSelected, true, within: 2))
        app.typeKey("1", modifierFlags: [.command, .control])
        XCTAssertTrue(alpha.has(\.isSelected, true, within: 2))
        app.typeKey("2", modifierFlags: [.command, .control])
        XCTAssertTrue(beta.has(\.isSelected, true, within: 2))

        let before = try await Self.ids("workspace", in: one)
        closeNew("workspace", besides: before)
        app.typeKey("t", modifierFlags: [.command, .control])
        let made = try await poll("the new workspace") {
            try await Self.ids("workspace", in: one).first { !before.contains($0) }
        }
        XCTAssertTrue(element("workspace.\(made)").has(\.isSelected, true, within: 3))
        let tabs = try await snapshot()["panes"] as? [[String: Any]] ?? []
        try await settle(tabs.filter { $0["workspace_id"] as? String == made }.compactMap { $0["tab_id"] as? String })
        app.typeKey("w", modifierFlags: [.command, .control])
        XCTAssertTrue(element("workspace.\(made)").vanishes(within: 3))

        openSessionPanel()
        element("open-session.session.\(two)").click()
        let header = element("sidebar.header")
        XCTAssertTrue(header.has(\.stringValue, two, within: 3))
        app.typeKey("[", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        app.typeKey("]", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, two, within: 3))
        app.typeKey("1", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        app.typeKey("2", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, two, within: 3))
        app.typeKey("w", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        XCTAssertTrue(until(2) { !pageList().contains(two) })
    }

    func testEachFloatingWindowsKeysActOnItsOwnPane() async throws {
        let (tab, first) = try await newTab("float-keys")
        let second = try await split(first)
        element("tab.\(tab)").click()
        let firstWindow = float(first)
        let secondWindow = float(second)
        // Show Window sits in the card's middle, under the floating windows: the main window comes forward first.
        element("tab.\(tab)").click()
        element("pane.\(second).show").click()
        XCTAssertTrue(hasKeyboard("terminal.\(second)", in: secondWindow))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(secondWindow.vanishes(within: 3))
        XCTAssertTrue(firstWindow.exists)
        element("tab.\(tab)").click()
        element("pane.\(first).show").click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)", in: firstWindow))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(firstWindow.vanishes(within: 3))
    }

    /// Never the panes: AppKit's key view loop steps the terminals.
    func testControlTabStepsTabsNeverPanes() async throws {
        let first = element("tab.w1:t1"), second = element("tab.w1:t2")
        XCTAssertTrue(first.has(\.isSelected, true, within: connect))
        let card = element("terminal.w1:p2")
        card.click()
        XCTAssertTrue(hasKeyboard(card))
        for _ in 0 ..< 3 {
            app.typeKey(.tab, modifierFlags: .control)
            XCTAssertTrue(second.has(\.isSelected, true, within: 2))
            app.typeKey(.tab, modifierFlags: [.control, .shift])
            XCTAssertTrue(first.has(\.isSelected, true, within: 2))
            XCTAssertTrue(hasKeyboard(card))
        }
        let (tab, pane) = try await createWorkspace("one-tab")
        let other = try await split(pane)
        element("workspace.\(workspace(of: tab))").click()
        XCTAssertTrue(element("terminal.\(other)").exists(within: 3))
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        for flags: XCUIElement.KeyModifierFlags in [.control, [.control, .shift]] {
            app.typeKey(.tab, modifierFlags: flags)
            XCTAssertFalse(hasKeyboard("terminal.\(other)"))
            XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        }
    }

    func testControlTabStepsFromChatAndBrowserCards() async throws {
        let (chatTab, chat) = try await startChat()
        let (browserTab, left) = try await newTab("ctrl-tab")
        try await waitForPrompt(left)
        element("tab.\(browserTab)").click()
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        _ = try await chooseBrowser(besides: left, in: browserTab)
        let tabs = try await (Self.call(one, "tab.list", ["workspace_id": "w2"])["tabs"] as? [[String: Any]] ?? [])
            .compactMap { $0["tab_id"] as? String }
        guard var index = tabs.firstIndex(of: browserTab) else { return XCTFail("\(browserTab) not in \(tabs)") }
        for (flags, offset) in [(XCUIElement.KeyModifierFlags.control, 1), ([.control, .shift], -1)] {
            for _ in tabs.indices {
                app.typeKey(.tab, modifierFlags: flags)
                index = (index + offset + tabs.count) % tabs.count
                XCTAssertTrue(element("tab.\(tabs[index])").has(\.isSelected, true, within: 2), "\(tabs[index])")
                if tabs[index] == chatTab {
                    XCTAssertTrue(hasKeyboard("chat.\(chat).composer"))
                }
            }
        }
    }

    func testCommandDSplitsInTheKeyWindowOnly() async throws {
        let (first, second) = try newWindow()
        var tabs: [String] = []
        for (window, label) in [(first, "key-first"), (second, "key-second")] {
            let tab = try await createTab(in: "w2", label: label).tab
            closeAfter("tab", tab)
            raise(window)
            element("workspace.w2", in: window).click()
            element("tab.\(tab)", in: window).click()
            XCTAssertTrue(element("tab.\(tab)", in: window).has(\.isSelected, true, within: 3))
            tabs.append(tab)
        }
        func count(_ tab: String) async throws -> Int {
            try await (snapshot()["panes"] as? [[String: Any]] ?? []).count { $0["tab_id"] as? String == tab }
        }
        var counts = [1, 1]
        for round in 0 ..< 4 {
            for (index, window) in [first, second].enumerated() {
                if round < 2 {
                    raise(window)
                } else {
                    app.typeKey("`", modifierFlags: .command)
                }
                app.typeKey("d", modifierFlags: .command)
                counts[index] += 1
                try await expect("round \(round): \(tabs[index]) split, the other not") {
                    try await [count(tabs[0]), count(tabs[1])] == counts
                }
            }
        }
    }

    func testKeyboardShortcutsPanelListsTheCommandsKeys() {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let panel = element("shortcuts")
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(panel.exists(within: 2))
        for section in ["Panes", "Tabs", "Spaces", "Sessions", "App", "Edit"] {
            XCTAssertTrue(element("shortcuts.section.\(section)").exists, section)
        }
        XCTAssertFalse(element("shortcuts.section.Plugins").exists)
        let rows = [
            "Split Right": "⌘D", "Select Pane": "⌥⌘←→↑↓", "Show Tab 1–9": "⌘1–9", "New Space": "⌃⌘T",
            "Show Space 1–9": "⌃⌘1–9", "Show Session 1–9": "⌥⌘1–9", "Show Previous Tab": "⇧⌘[ or ⌃⇧⇥",
            "Show Next Tab": "⇧⌘] or ⌃⇥",
            "Command Palette": "⌘K or ⇧⌘P", "Find": "⌘F", "Reset Font Size": "⌘0", "Open Session": "⌥⌘T",
            "Close Tab": "⇧⌘W", "Close Space": "⌃⌘W", "Detach Session": "⌥⌘W", "Balance Splits": "⌥⌘=",
            "Zoom Pane": "⇧⌘↩", "Move Tab Left": "⇧⌘←", "Move Tab Right": "⇧⌘→",
        ]
        for (title, keys) in rows {
            XCTAssertEqual(element("shortcuts.\(title)").value as? String, keys, title)
        }
        XCTAssertFalse(element("shortcuts.Resize Pane").exists)
        XCTAssertFalse(element("shortcuts.Close Window").exists)
        // Only the important keys: Settings has the rest.
        XCTAssertFalse(element("shortcuts.Insert Path").exists)
        XCTAssertTrue(element("shortcuts.customize").exists)
        XCTAssertGreaterThan(element("shortcuts.section.Sessions").frame.minX,
                             element("shortcuts.section.Panes").frame.maxX)
        keepScreenshot("keyboard shortcuts")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.vanishes(within: 2))
        XCTAssertTrue(hasKeyboard("terminal.w1:p1"))

        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Keyboard Shortcuts"].click()
        XCTAssertTrue(panel.exists(within: 2))
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(panel.vanishes(within: 2))

        openPalette()
        app.typeText("keyboard shortcuts")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(panel.exists(within: 2))
        // Beside it: in CI's short window it reaches the bottom.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.6)).click()
        XCTAssertTrue(panel.vanishes(within: 2))
    }
}
