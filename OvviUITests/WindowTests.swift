import XCTest

extension OvviUITests {
    func testSecondWindowWatchesUntilItsUserTypes() async throws {
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))
        XCTAssertFalse(element("notice.controlled", in: first).exists)
        XCTAssertEqual(element("notice.controlled", in: second).images["notice.symbol"].label, "Information")
        XCTAssertFalse(element("notice.controlled", in: second).buttons["notice.close"].exists)
        let terminal = try await terminalID("w1:p1")
        try await expectStreams(terminal, control: 1, observe: 1)
        XCTAssertFalse(element("pane.w1:p1.take-back", in: second).exists)
        app.typeKey("s", modifierFlags: [.command, .control])
        keepScreenshot("window 1 controls", of: first)
        keepScreenshot("window 2 watches", of: second)

        element("terminal.w1:p1", in: second).click()
        XCTAssertTrue(element("notice.controlled", in: first).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        app.typeText("echo one-$((40+2))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p1") { $0.contains("\none-42") }
        // keepScreenshot raises window 1, which is not input: window 2 keeps control (the PTY size below).
        keepScreenshot("window 1 observes the echo", of: first)
        try await expectStreams(terminal, control: 1, observe: 1)
        try await expectPTYSize("w1:p1", in: second)

        raise(first)
        element("notice.controlled.take-back", in: first).click()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: first).vanishes(within: 3))
        try await expectPTYSize("w1:p1", in: first)

        raise(second)
        element("tab.w1:t2", in: second).click()
        XCTAssertTrue(element("tab.w1:t2", in: second).has(\.isSelected, true, within: 2))
        XCTAssertTrue(element("tab.w1:t1", in: first).isSelected)
        try await expectStreams(terminalID("w1:p4"), control: 0, observe: 1)
        app.typeText("echo two-$((40+3))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p4") { $0.contains("\ntwo-43") }
        XCTAssertTrue(element("notice.controlled", in: first).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        try await expectStreams(terminalID("w1:p4"), control: 1, observe: 0)
    }

    func testClosingTheControllingWindowHandsControlOver() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        try await expect("one bridge run") { try await bridges(one) == 1 }
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))
        try await expect("still one bridge run") { try await bridges(one) == 1 }
        app.typeKey("s", modifierFlags: [.command, .control])

        raise(first)
        first.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(first.vanishes(within: 3))
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        try await expectPTYSize("w1:p1", in: second)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
    }

    func testControllerClosingItsPageHandsControlOver() async throws {
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))
        app.typeKey("s", modifierFlags: [.command, .control])

        raise(first)
        openPage(two, in: first)
        XCTAssertTrue(element("notice.controlled", in: second).exists)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 1)
        closePage(one, in: first)
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
        try await expectPTYSize("w1:p1", in: second)
    }

    func testWindowsOnDifferentSessionsEachControlTheirOwn() async throws {
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))

        openPage(two, in: second)
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        showPage(one, in: second)
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: 3))
        closePage(one, in: second)

        XCTAssertTrue(element("terminal.w1:p1", in: second).exists(within: connect))
        XCTAssertFalse(element("notice.controlled", in: second).exists)
        XCTAssertFalse(element("notice.controlled", in: first).exists)
        try await expectStreams(terminalID("w1:p1", in: two), control: 1, observe: 0, session: two)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
        keepScreenshot("window 1 on session one", of: first)
        keepScreenshot("window 2 on session two", of: second)
    }

    func newWindow() throws -> (XCUIElement, XCUIElement) {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let first = app.windows.firstMatch
        let identifier = first.identifier
        app.typeKey("n", modifierFlags: .command)
        let pick = element("picker.local.\(one)")
        XCTAssertTrue(pick.exists(within: connect))
        pick.click()
        return try (app.windows[identifier], otherWindow(than: identifier))
    }

    func testNewWindowListsTheSessionsToPickFrom() throws {
        step("New window: the picker lists the running and stopped sessions, with no sidebar")
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.element(boundBy: 1).exists(within: 3))
        let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.map(\.identifier).first { $0 != identifier })
            .map { app.windows[$0] }
        let two = element("picker.local.\(two)", in: window)
        XCTAssertTrue(two.exists(within: connect))
        XCTAssertTrue(two.label.contains("Running"), two.label)
        let stopped = element("picker.local.\(three)", in: window).label
        XCTAssertTrue(stopped.contains("Stopped"), stopped)
        XCTAssertFalse(element("picker.local.default", in: window).exists)
        XCTAssertFalse(element("sidebar", in: window).exists)
        XCTAssertFalse(element("titlebar.machine", in: window).exists)
        keepScreenshot("new window", of: window)

        step("New window: a pick opens the session in it, and it fills the screen")
        two.click()
        XCTAssertTrue(element("workspace.w1", in: window).exists(within: connect))
        XCTAssertEqual(element("sidebar.header", in: window).stringValue, self.two)
        XCTAssertTrue(element("terminal.w1:p1", in: app.windows[identifier]).exists)
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame, frame = try XCTUnwrap(window).frame
        XCTAssertEqual(frame.width, screen.width, accuracy: 2, "\(frame) in \(screen)")
        // A window as tall as the screen comes out a few points taller, its bottom under the Dock's top edge: 677 and
        // 679 in 674 on CI, the second window only (the first comes out at 674), from one run to the next.
        XCTAssertTrue((screen.height - 2 ... screen.height + 8).contains(frame.height), "\(frame) in \(screen)")
        XCTAssertEqual(frame.minX, screen.minX, accuracy: 2, "\(frame) in \(screen)")

        step("New window: the next one takes the front window's size and place, once the user changed them")
        // The left half of the screen, with no hit test on an edge.
        let front = try XCTUnwrap(window)
        app.menuBars.menuBarItems["Window"].click()
        app.menuBars.menuItems["Move & Resize"].click()
        app.menuBars.menuItems["Left"].click()
        XCTAssertTrue(until(3) { front.frame.width < frame.width - 100 }, "\(front.frame)")
        let resized = front.frame, ids = app.windows.allElementsBoundByIndex.map(\.identifier)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(until(3) { app.windows.count == ids.count + 1 }, "no new window")
        let third = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { !ids.contains($0.identifier) })
        XCTAssertEqual(third.frame.width, resized.width, accuracy: 2, "\(third.frame) after \(resized)")
        XCTAssertEqual(third.frame.height, resized.height, accuracy: 8, "\(third.frame) after \(resized)")
        // AppKit cascades a window over one of its group at the same place.
        XCTAssertTrue(
            (resized.minX ... resized.minX + 40).contains(third.frame.minX),
            "\(third.frame) after \(resized)",
        )
        third.buttons[XCUIIdentifierCloseWindow].click()
    }

    func testNewWindowRowsResolveWhileAnotherConnectAsks() async throws {
        try await skipWithoutSSH()
        try await Self.post("\(one)/ssh-drop", Data("ovvi-pw".utf8))
        try await Self.post("\(one)/ssh-forget", Data("ovvi-pw".utf8))
        let host = #"[{"id":"e2e-pw","name":"Password Host","target":"ovvi-pw","icon":"cpu"}]"#
        relaunch(one, ["-machines", host, "-machine", "e2e-pw"])
        let connectButton = element("detail.connect")
        XCTAssertTrue(connectButton.exists(within: connect))
        connectButton.click()
        XCTAssertTrue(element("ask.ok").exists(within: connect))
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(element("picker.local.\(one)").exists(within: connect))
        let waiting = element("picker.e2e-pw.+reading")
        XCTAssertTrue(waiting.exists)
        XCTAssertTrue(waiting.vanishes(within: 20))
    }

    /// Add Machine in a new window's list connects the machine in that window: no other window opens.
    func testAddMachineFromANewWindowConnectsInIt() throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let first = mainWindows.firstMatch.identifier
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(element("picker.local.\(one)").exists(within: connect))
        let window = try XCTUnwrap(mainWindows.allElementsBoundByIndex.map(\.identifier).first { $0 != first })
            .map { app.windows[$0] }
        element("picker.+add-machine", in: window).click()
        let settings = settingsWindow
        let name = element("settings.machine.name", in: settings)
        XCTAssertTrue(name.exists(within: 5))
        name.click()
        app.typeText("Nowhere")
        element("settings.machine.target", in: settings).click()
        app.typeText("ovvi-e2e-nowhere.invalid")
        element("settings.machine.save", in: settings).click()
        XCTAssertTrue(settings.vanishes(within: 3))
        let machine = element("window.machine", in: window)
        XCTAssertTrue(machine.has(\.stringValue, "Nowhere", within: connect), machine.stringValue)
        XCTAssertEqual(mainWindows.count, 2)
        keepScreenshot("added machine in its new window")
    }

    func testNewWindowMakesATypedSession() async throws {
        // Down first: a run cut short may have left it.
        try await Self.post("\(eight)/stress", Data())
        addTeardownBlock { [eight] in _ = try? await Self.post("\(eight)/stress", Data()) }
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(element("picker.local.\(one)").exists(within: connect))
        element("picker.+add-machine").click()
        XCTAssertTrue(element("settings.machine.target", in: settingsWindow).exists(within: 5))
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 3))
        element("picker.+edit-machines").click()
        XCTAssertTrue(element("settings.machines.add", in: settingsWindow).exists(within: 5))
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 3))
        let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.map(\.identifier).first { $0 != identifier })
            .map { app.windows[$0] }
        element("picker.filter", in: window).click()
        app.typeText(eight)
        XCTAssertTrue(element("picker.local.+new", in: window).has(\.isSelected, true, within: 3))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("sidebar.header", in: window).has(\.stringValue, eight, within: connect))
        try await Self.snapshot(eight)
    }

    func testNewWindowShowsKnownSessionsAtOnce() throws {
        app.launchEnvironment["SHELL"] = "\(Self.agents)/login-shell"
        app.launchEnvironment["PATH"] = "\(Self.fixtures)/late-herdr:/usr/bin:/bin"
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        relaunch()
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        app.typeKey("t", modifierFlags: [.command, .option])
        XCTAssertTrue(element("open-session.session.\(two)").exists(within: connect))
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("n", modifierFlags: .command)
        let row = element("picker.local.\(one)"), reading = element("picker.local.+reading")
        XCTAssertTrue(until(3) { row.exists || reading.exists })
        XCTAssertTrue(row.exists, "the spinner row came first")
        let label = row.label
        XCTAssertFalse(until(3) { reading.exists || row.label != label })
    }

    func testRelaunchRestoresEveryWindowWithItsSession() async throws {
        try await forgetWindows()
        relaunch(windows: .saved)
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        // One window to start from: a window an earlier run saved may come back too.
        let main = mainWindows
        while main.count > 1 {
            main.element(boundBy: 1).buttons[XCUIIdentifierCloseWindow].click()
        }
        XCTAssertEqual(headers, [one])
        app.typeKey("n", modifierFlags: .command)
        let pick = element("picker.local.\(two)")
        XCTAssertTrue(pick.exists(within: connect))
        pick.click()
        XCTAssertTrue(until(connect) { headers.sorted() == [one, two].sorted() }, "\(headers)")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        relaunch(windows: .restored)
        XCTAssertTrue(until(connect) { headers.sorted() == [one, two].sorted() }, "\(headers)")
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(main.count, 2)
        XCTAssertFalse(element("picker.local.\(one)").exists)

        while main.firstMatch.exists {
            main.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        }
        XCTAssertTrue(until(5) { headers.isEmpty })
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        XCTAssertTrue(element("picker.local.\(one)").exists(within: connect))
        XCTAssertTrue(headers.isEmpty)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(main.count, 1)
    }

    private var headers: [String] {
        mainWindows.allElementsBoundByIndex
            .compactMap { window in
                let header = element("sidebar.header", in: window)
                return header.exists ? header.value as? String : nil
            }
    }

    func testALaunchWithNothingToRestoreConnectsToNothing() async throws {
        relaunch(one, ["-ApplePersistenceIgnoreState", "YES"], windows: .restored)
        XCTAssertTrue(element("picker.local.\(one)").exists(within: connect))
        XCTAssertTrue(app.staticTexts["Ovvi"].exists)
        XCTAssertFalse(element("sidebar").exists)
        // `-machines []` holds without `-session` too: never the user's machines (a check only on a Mac with machines
        // of its own; CI has none).
        let groups = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'picker.section.'"))
        XCTAssertEqual(groups.count, 1)
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(element("sidebar").exists)
        XCTAssertEqual(mainWindows.count, 1)
        keepScreenshot("new window")
    }

    func otherWindow(than identifier: String) throws -> XCUIElement {
        XCTAssertTrue(app.windows.element(boundBy: 1).exists(within: 3))
        XCTAssertEqual(app.windows.count, 2)
        let other = try XCTUnwrap(app.windows.allElementsBoundByIndex.map(\.identifier).first { $0 != identifier })
        let window = app.windows[other]
        XCTAssertTrue(element("terminal.w1:p1", in: window).exists(within: connect))
        return window
    }

    private func expectStreams(_ terminal: String, control: Int, observe: Int, session: String? = nil) async throws {
        try await expect("\(control) control and \(observe) observe runs of \(terminal)") {
            let runs = try await streams(session ?? one).filter { $0.contains(terminal) }
            let controls = runs.count { $0.contains("session control") },
                observes = runs.count { $0.contains("observe") }
            return controls == control && observes == observe
        }
    }

    private func bridges(_ session: String) async throws -> Int {
        try await runs(session).count { $0.contains("remote-api-bridge") }
    }

    /// Brings the window to the front with Window ▸ Cycle Through Windows (⌘`), as a click cannot: on CI's 1024×768
    /// screen both windows have the same frame. `firstMatch` is the front window.
    func raise(_ window: XCUIElement) {
        let identifier = window.identifier
        if app.windows.firstMatch.identifier != identifier {
            app.typeKey("`", modifierFlags: .command)
        }
        XCTAssertTrue(until(3) { app.windows.firstMatch.identifier == identifier }, "window \(identifier) in front")
    }
}
