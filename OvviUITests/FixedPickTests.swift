import XCTest

/// Settings ▸ General ▸ New panes open (ui/new-pane#a-fixed-pick): a new pane makes the set pick with no chooser; ⌥
/// brings the chooser back.
extension OvviUITests {
    /// Settings ▸ General ▸ New panes open Browser (ui/new-pane#a-fixed-pick): ⌘D's stand-in shows the browser's
    /// loader, never the chooser, also while herdr has not answered, and the pane becomes a browser; a split button's
    /// ⌥-click shows the chooser.
    func testAFixedPickSkipsTheChooserAndOptionShowsIt() async throws {
        relaunch(one, ["-newPaneOpens", "browser"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("fixed pick")
        element("tab.\(tab)").click()
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/resume") }
        let standIn = { (kind: String) in
            self.app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH 'pane.new.' AND identifier ENDSWITH %@", kind,
            )).firstMatch
        }
        _ = try await Self.post("\(one)/pause")
        app.typeKey("d", modifierFlags: .command)
        let loading = standIn(".loader").exists(within: 3), asked = standIn(".chooser.terminal").exists
        keepScreenshot("fixed pick loader")
        _ = try await Self.post("\(one)/resume")
        XCTAssertTrue(loading)
        XCTAssertFalse(asked, "the chooser showed")
        let browser = try await poll("a browser pane") { () async throws -> String? in
            // The chooser's pane closes as the browser's takes its place: read again then.
            let new = try await self.replaced(left, in: tab, besides: [left])
            return try? await self.paneLabel(new).hasPrefix("ovvi:browser#") == true ? new : nil
        }
        XCTAssertTrue(hasKeyboard(element("browser.\(browser).address")))
        keepScreenshot("fixed pick browser")

        // ⌥ held: the chooser.
        let split = element("pane.\(browser).split-right")
        XCTAssertTrue(split.exists(within: 2))
        XCUIElement.perform(withKeyModifiers: .option) { split.click() }
        let chooser = try await replaced(browser, in: tab, besides: [left, browser])
        let terminal = element("pane.\(chooser).chooser.terminal")
        XCTAssertTrue(terminal.has(\.isSelected, true, within: 3))
        keepScreenshot("fixed pick option chooser")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(terminal.vanishes(within: 2))
    }

    /// New panes open Terminal: ⌘T and ⌘D give a shell at once, with no chooser. Keys typed before herdr made the pane
    /// go to the new shell in the order typed (text, then ← ×3, then text), none to the old one.
    func testAFixedTerminalTakesTheKeysTypedBeforeItsPane() async throws {
        relaunch(one, ["-newPaneOpens", "terminal"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("pane.w2:p1").has(\.isHittable, true, within: 2))
        let tabs = try await tabIDs()
        closeNew("tab", besides: tabs)
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/resume") }
        _ = try await Self.post("\(one)/pause")
        app.typeKey("t", modifierFlags: .command)
        app.typeText("echo ovvi-early-$((6*7))\r")
        _ = try await Self.post("\(one)/resume")
        let tab = try await newTabID(after: tabs), shell = try await pane(of: tab)
        XCTAssertTrue(element("terminal.\(shell)").exists(within: 3))
        XCTAssertFalse(element("pane.\(shell).chooser.terminal").exists)
        try await waitFor(shell) { $0.contains("\novvi-early-42") }
        let old = try await read("w2:p1")
        XCTAssertFalse(old.contains("ovvi-early"), old)
        XCTAssertTrue(hasKeyboard("terminal.\(shell)"))

        _ = try await Self.post("\(one)/pause")
        app.typeKey("d", modifierFlags: .command)
        app.typeText("echo ovvi-earl-$((6*7))")
        for _ in 0 ..< 9 {
            app.typeKey(.leftArrow, modifierFlags: [])
        }
        app.typeText("y\r")
        _ = try await Self.post("\(one)/resume")
        let split = try await replaced(shell, in: tab, besides: [shell])
        try await waitFor(split) { $0.contains("\novvi-early-42") }
        let before = try await read(shell)
        XCTAssertFalse(before.contains("ovvi-earl-"), before)
        XCTAssertTrue(hasKeyboard("terminal.\(split)"))
    }

    /// With a fixed pick, View ▸ Pane's splits have ⌥ items that show the chooser. Settings shows the pick and offers
    /// every kind.
    func testAFixedPicksMenuItemsAndSetting() async throws {
        relaunch(one, ["-newPaneOpens", "terminal"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("fixed menu")
        element("tab.\(tab)").click()
        element("terminal.\(shell)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(shell)"))
        app.menuBars.menuBarItems["View"].click()
        let submenu = app.menuBars.menuItems["Pane"]
        submenu.hover()
        let alternate = submenu.menuItems["Split Right and Choose…"]
        XCTAssertTrue(alternate.exists(within: 2))
        let main = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'")).firstMatch
        XCUIElement.perform(withKeyModifiers: .option) {
            let shot = XCTAttachment(screenshot: main.screenshot())
            (shot.name, shot.lifetime) = ("split alternate", .keepAlways)
            add(shot)
            alternate.click()
        }
        let chooser = try await replaced(shell, in: tab, besides: [shell])
        XCTAssertTrue(element("pane.\(chooser).chooser.terminal").has(\.isSelected, true, within: 3))
        app.typeKey(.escape, modifierFlags: [])

        openSettings("general")
        let picker = element("settings.general.new-pane", in: settingsWindow)
        XCTAssertTrue(picker.has(\.stringValue, "Terminal", within: 3), picker.debugDescription)
        keepScreenshot("settings new panes open", of: settingsWindow)
        picker.click()
        XCTAssertTrue(picker.menuItems["File Explorer"].exists(within: 2))
        let menu = XCTAttachment(screenshot: settingsWindow.screenshot())
        (menu.name, menu.lifetime) = ("settings new panes open menu", .keepAlways)
        add(menu)
        app.typeKey(.escape, modifierFlags: [])
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))
    }
}
