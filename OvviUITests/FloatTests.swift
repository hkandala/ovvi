import XCTest

extension OvviUITests {
    func testFloatingAPaneOpensItsWindowAndDetachPutsItBack() async throws {
        step("Float: the window opens large and centered, with the main window's title row")
        let (tab, first) = try await newTab("float")
        let second = try await split(first)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
        let main = app.windows.containing(.any, identifier: "tab.\(tab)").firstMatch.frame
        let window = float(second)
        largeWithTheTitleRow(window, second, over: main)

        step("Float: the pane shows in the window and stays in herdr's tab")
        XCTAssertTrue(element("terminal.\(second)", in: window).exists(within: 3))
        XCTAssertTrue(element("pane.\(second).show").exists(within: 3))
        try await expect("both panes in herdr's tab") { try await order(tab) == [first, second] }
        XCTAssertTrue(element("float.\(second).place").has(\.stringValue, "\(one) › beta › float", within: 3))

        step("Main window: the card's Show Window and Bring Back Here, keys stay in the main window")
        element("tab.\(tab)").click()
        let (show, back) = placeholder(second)
        keepScreen("floating window over the main window")
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))
        XCTAssertTrue(window.exists)

        step("Show Window: the keys go to the floating window")
        show.click()
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
        XCTAssertTrue(hasKeyboard("terminal.\(second)", in: window))
        app.typeText("echo float-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor(second) { $0.contains("\nfloat-42") }

        step("Bring Back Here: the window closes, the pane is back with the keys")
        element("tab.\(tab)").click()
        back.click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(show.vanishes(within: 3))
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
    }

    private func largeWithTheTitleRow(_ window: XCUIElement, _ second: String, over main: CGRect) {
        let frame = window.frame, frames = "\(frame) over \(main)"
        XCTAssertEqual(frame.width, max(720, main.width * 0.6), accuracy: 2, frames)
        XCTAssertEqual(frame.height, max(460, main.height * 0.75), accuracy: 2, frames)
        XCTAssertEqual(frame.midX, main.midX, accuracy: 2, frames)
        XCTAssertEqual(frame.midY, main.midY, accuracy: 2, frames)

        let lights = [XCUIIdentifierCloseWindow, XCUIIdentifierMinimizeWindow, XCUIIdentifierFullScreenWindow]
            .map { window.buttons[$0] }
        XCTAssertTrue(until(2) {
            lights.enumerated().allSatisfy { index, light in
                abs(light.frame.minX - frame.minX - (15 + CGFloat(index) * 23)) < 1
                    && abs(light.frame.minY - frame.minY - 15) < 1
            }
        }, "\(lights.map(\.frame)) in \(frame)")
        for button in ["pin", "close", "detach"] {
            let button = element("float.\(second).\(button)").frame
            XCTAssertEqual(button.height, 28, accuracy: 0.5, "\(button)")
            XCTAssertEqual(button.midY - frame.minY, 23, accuracy: 1, "\(button) in \(frame)")
        }

        let info = element("float.\(second).info", in: window)
        XCTAssertTrue(info.stringValue.hasSuffix("tmp"), info.debugDescription)
        let place = element("float.\(second).place", in: window).frame
        XCTAssertEqual(place.minX - info.frame.maxX, 2 * 8 + 1, accuracy: 1, "\(place) after \(info.frame)")
    }

    private func placeholder(_ second: String) -> (show: XCUIElement, back: XCUIElement) {
        let show = element("pane.\(second).show"), back = element("pane.\(second).back")
        let card = element("pane.\(second)").frame
        XCTAssertTrue(show.exists(within: 3))
        XCTAssertEqual(show.label, "Show Window")
        XCTAssertEqual(back.label, "Bring Back Here")
        XCTAssertEqual(element("pane.\(second).floating").stringValue, "This pane is open in a floating window.")
        let buttons = show.frame.union(back.frame), both = "\(show.frame), \(back.frame) in \(card)"
        XCTAssertEqual(buttons.midX, card.midX, accuracy: 1, both)
        XCTAssertEqual(show.frame.midY, back.frame.midY, accuracy: 1, both)
        XCTAssertEqual(back.frame.minX - show.frame.maxX, 8, accuracy: 1, both)
        XCTAssertLessThan(show.frame.width, card.width / 2, both)
        return (show, back)
    }

    func testFloatingWindowsHaveTheirOwnCommandsAndComeBackAfterRelaunch() async throws {
        try await forgetWindows()
        relaunch(windows: .saved)
        let (tab, first) = try await newTab("float-keep")
        let second = try await split(first), third = try await split(second)
        element("tab.\(tab)").click()
        element("terminal.\(third)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(third)"))
        openPalette().typeText("float pane")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("float.\(third)").exists(within: 5))
        element("tab.\(tab)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
        openPalette().typeText("float pane")
        app.typeKey(.return, modifierFlags: [])
        let pinned = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(pinned.exists(within: 5))

        XCTAssertTrue(hasKeyboard("terminal.\(second)", in: pinned))
        openPalette()
        XCTAssertTrue(element("palette.command.Detach Pane", in: pinned).exists(within: 2))
        XCTAssertTrue(element("palette.command.Detach Pane", in: pinned).has(\.isSelected, true, within: 2))
        XCTAssertFalse(element("palette.command.New Tab", in: pinned).exists)
        XCTAssertFalse(element("palette.tab.\(tab)", in: pinned).exists)
        app.typeText("stay on top")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 2))
        XCTAssertTrue(element("float.\(third).pin").has(\.stringValue, "off", within: 2))
        keepScreen("two floating windows, one on top")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        relaunch(windows: .restored)
        let back = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(back.exists(within: connect))
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 3))
        XCTAssertTrue(element("float.\(third).pin").has(\.stringValue, "off", within: 3))
        XCTAssertTrue(element("pane.\(second).show").exists(within: 3))
        XCTAssertTrue(element("pane.\(third).show").exists)

        try await Self.call(one, "pane.close", ["pane_id": second])
        XCTAssertTrue(back.vanishes(within: 5))
        XCTAssertTrue(element("float.\(third)").exists)
        // ⌘W in a floating window detaches. Show Window is under the floating window until the main one is in front.
        element("tab.\(tab)").click()
        element("pane.\(third).show").click()
        XCTAssertTrue(hasKeyboard("terminal.\(third)", in: app.windows.containing(.any, identifier:
            "float.\(third)").firstMatch))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("float.\(third)").vanishes(within: 3))
        XCTAssertTrue(element("pane.\(third).show").vanishes(within: 3))
    }

    func testALinkInAFloatingCardOpensInAFloatingWindow() async throws {
        let (tab, pane) = try await newTab("float-link")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(pane)").exists(within: 3))
        let window = float(pane)
        let terminal = element("terminal.\(pane)", in: window)
        XCTAssertTrue(terminal.exists(within: 3))
        let address = "https://example.com/ovvi-float"
        try await waitForPrompt(pane)
        try await send("clear; echo \(address)\r", to: pane)
        try await waitFor(pane) { $0.hasPrefix("\(address)\n") }
        let grid = try XCTUnwrap(terminal.value as? String).split(separator: " ").compactMap { Double($0) }
        let cell = CGSize(width: terminal.frame.width / grid[1], height: terminal.frame.height / grid[0])
        let link = terminal.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: cell.width * 5.5, dy: cell.height * 0.5))
        let before = try await tabIDs()
        link.hover()
        // ⌥: to the side in a main window, here in a floating window too.
        XCUIElement.perform(withKeyModifiers: .option) { link.click() }
        let made = try await newTabID(after: before)
        closeAfter("tab", made)
        let browser = try await self.pane(of: made)
        XCTAssertTrue(app.windows.containing(.any, identifier: "float.\(browser)").firstMatch.exists(within: 5))
        let panes = try await order(tab)
        XCTAssertEqual(panes, [pane])
        element("float.\(pane).detach", in: window).click()
        XCTAssertTrue(window.vanishes(within: 3))
    }

    func testClosingAFloatedPaneAsksInItsWindow() async throws {
        let (other, shell) = try await newTab("float-close-other")
        // A startup program still running would make its close ask.
        try await waitForPrompt(shell)
        let (tab, first) = try await newTab("float-close")
        let second = try await split(first)
        try await runSleep(second)
        element("tab.\(tab)").click()
        let window = float(second)
        XCTAssertTrue(hasKeyboard("terminal.\(second)", in: window))
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(window.sheets.buttons["Close Pane"].exists(within: 5))
        // A close in the main window that asks nothing leaves this question up.
        element("tab.\(other)").click()
        element("tab.\(other)").hover()
        element("tab.\(other).close").click()
        try await expect("the other tab closed in herdr") { try await !tabIDs().contains(other) }
        XCTAssertTrue(window.sheets.buttons["Close Pane"].exists)
        // The main window covers the float window now.
        element("pane.\(second).show").click()
        window.sheets.buttons["Cancel"].click()
        XCTAssertTrue(window.sheets.buttons["Close Pane"].vanishes(within: 3))
        element("float.\(second).close").click()
        let confirm = window.sheets.buttons["Close Pane"]
        XCTAssertTrue(confirm.exists(within: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(window.vanishes(within: 5))
        try await expect("the pane closed in herdr") { try await order(tab) == [first] }

        let alone = float(first)
        element("tab.\(tab)").click()
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["Close Window"].click()
        XCTAssertTrue(alone.vanishes(within: 5))
    }

    func testFloatingWindowInEachLook() async throws {
        let (tab, first) = try await newTab("float-look")
        let second = try await split(first)
        element("tab.\(tab)").click()
        let window = float(second)
        element("float.\(second).pin").click()
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 2))
        element("tab.\(tab)").click()
        addTeardownBlock { @MainActor [self] in
            pick("Interface Style", "Glass")
            pick("Appearance", "Dark")
        }
        for (menu, item, look) in [("Interface Style", "Glass", "glass dark"), ("Appearance", "Light", "glass light"),
                                   ("Interface Style", "Classic", "classic light"),
                                   ("Appearance", "Dark", "classic dark")]
        {
            pick(menu, item)
            XCTAssertTrue(element("window.look").has(\.stringValue, look, within: 3))
            XCTAssertTrue(window.isHittable)
            keepScreen("floating window, \(look)")
        }
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
    }

    func testOvviURLFloatsAPaneOfASessionWithNoPage() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let pane = "w1:p1"
        let window = try await floatByURL(two, pane)
        XCTAssertTrue(until(3) { element("float.\(pane).place", in: window).stringValue.hasPrefix("\(two) › gamma › ")
        })
        XCTAssertFalse(pageList().contains(two))
        app.typeText("echo url-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await expect("the keys in two's pane") { try await read(pane, in: two).contains("\nurl-42") }

        element("workspace.w1").click()
        let workspaces = try await workspaceIDs()
        try await openFloatURL("session=\(two)&pane=\(pane)", path: "/")
        XCTAssertTrue(hasKeyboard("terminal.\(pane)", in: window))
        XCTAssertEqual(app.windows.containing(.any, identifier: "float.\(pane)").count, 1)

        element("workspace.w1").click()
        try await openFloatURL("session=\(two)&pane=w9:p9")
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts["Can't float pane w9:p9 of \(two): no such pane."].exists(within: 5))
        XCTAssertFalse(element("float.w9:p9").exists)
        try await openFloatURL("session=ovvi-e2e-none&pane=\(pane)")
        let none = NSPredicate(format: "value BEGINSWITH %@", "Can't float pane \(pane) of ovvi-e2e-none: ")
        XCTAssertTrue(notice.staticTexts.matching(none).firstMatch.exists(within: connect))
        XCTAssertFalse(pageList().contains("ovvi-e2e-none"))
        let after = try await workspaceIDs()
        XCTAssertEqual(after, workspaces)

        // The URL brings the window forward first: a click on a window behind the main one lands in the main one.
        _ = try await floatByURL(two, pane)
        element("float.\(pane).detach", in: window).click()
        XCTAssertTrue(window.vanishes(within: 3))
        try await expect("two's herdr runs end") { try await runs(two).isEmpty }

        let (tab, other) = try await newTab("float-url")
        element("workspace.w1").click()
        XCTAssertTrue(element("tab.\(tab)").vanishes(within: 3))
        _ = try await floatByURL(one, other)
    }

    func testOvviURLFloatGoesWithItsWindowAndOpensOne() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let pane = "w1:p1"
        let window = try await floatByURL(two, pane)
        element("workspace.w1").click()
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["Close Window"].click()
        XCTAssertTrue(window.vanishes(within: 5))
        try await expect("two's herdr runs end") { try await runs(two).isEmpty }

        _ = try await floatByURL(two, pane)
        XCTAssertTrue(element("workspace.w1").exists(within: connect))

        element("workspace.w1").click()
        openSessionPanel()
        app.typeText(two)
        element("open-session.session.\(two)").click()
        XCTAssertTrue(until(3) { pageList().contains(two) })
        XCTAssertTrue(window.exists)
        _ = try await floatByURL(two, pane)
        element("float.\(pane).detach", in: window).click()
        XCTAssertTrue(window.vanishes(within: 3))
        let left = try await runs(two)
        XCTAssertFalse(left.isEmpty)
    }

    func testShownPanesAreMarkedAndOvviFloatFloats() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        try await markAndFloat()
        XCTAssertFalse(pageList().contains(two))
        // Within the 1 s the quit waits, not the mark's 30 s.
        try await expectShown(one, "w1:p1")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        try await expectShown(one, "w1:p1", false)
    }

    func markAndFloat() async throws {
        let (tab, pane) = try await newTab("float-request")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        try await expectShown(one, pane)
        try await waitForPrompt(pane)
        try await run("\(Self.ovviCommand) float \(two)/w1:p1", in: pane, "float", 0, "floating: true")
        let window = app.windows.containing(.any, identifier: "float.w1:p1").firstMatch
        XCTAssertTrue(window.exists(within: connect))
        XCTAssertTrue(until(3) { element("float.w1:p1.place", in: window).stringValue.hasPrefix("\(two) › gamma › ") })
        try await expectShown(two, "w1:p1")
        element("float.w1:p1.detach", in: window).click()
        XCTAssertTrue(window.vanishes(within: 3))
        try await expectShown(two, "w1:p1", false)
        element("workspace.w1").click()
        try await expectShown(one, pane, false)
    }

    func expectShown(_ session: String, _ pane: String, _ shown: Bool = true) async throws {
        try await expect("\(session)'s \(pane) \(shown ? "" : "not ")marked shown") {
            let info = try await Self.call(session, "pane.get", ["pane_id": pane])["pane"] as? [String: Any]
            return ((info?["tokens"] as? [String: String])?["ovvi-shown"] != nil) == shown
        }
    }

    /// Through the helper: XCUIApplication.open(_:) leaves the app not foreground for XCUITest, on CI.
    func floatByURL(_ session: String, _ pane: String) async throws -> XCUIElement {
        try await openFloatURL("session=\(session)&pane=\(pane)")
        let window = app.windows.containing(.any, identifier: "float.\(pane)").firstMatch
        XCTAssertTrue(window.exists(within: connect))
        XCTAssertTrue(hasKeyboard("terminal.\(pane)", in: window))
        return window
    }

    func openFloatURL(_ query: String, path: String = "") async throws {
        let ovvi = Self.devApp
        _ = try await Self.post("\(one)/open-url", Data("\(ovvi)\novvi://float\(path)?\(query)".utf8))
    }

    func float(_ pane: String) -> XCUIElement {
        hoverHeader(pane)
        element("pane.\(pane).float").click()
        let window = app.windows.containing(.any, identifier: "float.\(pane)").firstMatch
        XCTAssertTrue(window.exists(within: 5))
        return window
    }

    func floatAndBack(_ pane: String) {
        let window = float(pane)
        XCTAssertTrue(window.webViews.staticTexts.matching(NSPredicate(format: "value == 'ovvi-page-two'")).firstMatch
            .exists(within: 3))
        keepScreenshot("floated browser", of: window)
        let surface = element("float.\(pane)", in: window).frame
        let back = element("browser.\(pane).back", in: window).frame, page = window.webViews.firstMatch.frame
        XCTAssertEqual(back.minY - surface.minY, back.minX - surface.minX, accuracy: 0.5, "\(back) in \(surface)")
        // 1 pt: on a 1x screen the card's frame rounds to a whole point.
        XCTAssertEqual(page.minY - back.maxY, back.minY - surface.minY, accuracy: 1, "\(back) over \(page)")
        XCTAssertFalse(element("float.\(pane).place", in: window).exists)
        element("float.\(pane).detach").click()
        XCTAssertTrue(window.vanishes(within: 3))
    }

    func keepScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
