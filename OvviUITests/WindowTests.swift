import AppKit
import XCTest

/// Several windows: windows on one session share its store and agree on one controller (D66); the other
/// watches with the control capsule. Session one's t1 is p1 | (p2 / p3), t2 holds p4.
extension OvviUITests {
    func testSecondWindowWatchesUntilItsUserTypes() async throws {
        let (first, second) = try newWindow()
        // Window 1 opened the session first: it controls, window 2 watches.
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))
        XCTAssertFalse(element("notice.controlled", in: first).exists)
        XCTAssertEqual(element("notice.controlled", in: second).images["notice.symbol"].label, "Information")
        XCTAssertFalse(element("notice.controlled", in: second).buttons["notice.close"].exists)
        let terminal = try await terminalID("w1:p1")
        try await expectStreams(terminal, control: 1, observe: 1)
        // Watched because of another Ovvi window: the capsule, not the per-card button.
        XCTAssertFalse(element("pane.w1:p1.take-back", in: second).exists)
        // A wider card than window 1's, so the PTY size tells the windows apart.
        app.typeKey("s", modifierFlags: [.command, .control])
        keepScreenshot("window 1 controls", of: first)
        keepScreenshot("window 2 watches", of: second)

        // Typing in window 2 makes it the controller, and the key is sent.
        element("terminal.w1:p1", in: second).click()
        XCTAssertTrue(element("notice.controlled", in: first).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        app.typeText("echo one-$((40+2))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p1") { $0.contains("\none-42") }
        // keepScreenshot raises window 1, which is not input: window 2 keeps control (the PTY size below).
        keepScreenshot("window 1 observes the echo", of: first)
        // Window 1 still streams the pane, now watching it.
        try await expectStreams(terminal, control: 1, observe: 1)
        try await expectPTYSize("w1:p1", in: second)

        raise(first)
        element("notice.controlled.take-back", in: first).click()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: first).vanishes(within: 3))
        try await expectPTYSize("w1:p1", in: first)

        // Each window keeps its own selection.
        raise(second)
        element("tab.w1:t2", in: second).click()
        XCTAssertTrue(element("tab.w1:t2", in: second).has(\.isSelected, true, within: 2))
        XCTAssertTrue(element("tab.w1:t1", in: first).isSelected)
        // Window 1 never showed t2, so nobody holds p4: watching, window 2 still opens it as observe.
        try await expectStreams(terminalID("w1:p4"), control: 0, observe: 1)
        // A key press with no click takes the session, and is then sent.
        app.typeText("echo two-$((40+3))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p4") { $0.contains("\ntwo-43") }
        XCTAssertTrue(element("notice.controlled", in: first).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        try await expectStreams(terminalID("w1:p4"), control: 1, observe: 0)
    }

    func testClosingTheControllingWindowHandsControlOver() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        // One events stream per session, however many windows show it (request bridges come and go).
        try await expect("one bridge run") { try await bridges(one) == 1 }
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))
        try await expect("still one bridge run") { try await bridges(one) == 1 }
        app.typeKey("s", modifierFlags: [.command, .control])

        // Window 1 controls and closes: window 2 takes over at its own card size.
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
        // Still window 1's until its page closes.
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
        // The capsule shows only while the page in view is watched.
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

    // MARK: Helpers

    /// ⌘N once the first window shows session one, and session one picked in the new one: the first window and the
    /// new one.
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

    /// ⌘N opens a window that connects to nothing: it lists each machine's sessions, running first, and the throwaway
    /// run's only. A pick opens that session there; the first window keeps its page.
    func testNewWindowListsTheSessionsToPickFrom() throws {
        let three = try env("OVVI_SESSION3")
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
        two.click()
        XCTAssertTrue(element("workspace.w1", in: window).exists(within: connect))
        XCTAssertEqual(element("sidebar.header", in: window).stringValue, self.two)
        XCTAssertTrue(element("terminal.w1:p1", in: app.windows[identifier]).exists)
    }

    /// Each machine's row resolves within 15 s on its own: Password Host's read waits behind this window's Connect,
    /// whose ssh question nobody answers, and gives up while This Mac's sessions show (CI's sshd).
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

    /// ⌘N opens a window that fills the screen's visible frame, as a zoom does.
    func testNewWindowFillsTheScreen() throws {
        let (_, window) = try newWindow()
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        XCTAssertEqual(window.frame.width, screen.width, accuracy: 2, "\(window.frame) in \(screen)")
        // A window as tall as the screen comes out a few points taller, its bottom under the Dock's top edge: 677 and
        // 679 in 674 on CI, the second window only (the first comes out at 674), from one run to the next.
        XCTAssertTrue((screen.height - 2 ... screen.height + 8).contains(window.frame.height),
                      "\(window.frame) in \(screen)")
        XCTAssertEqual(window.frame.minX, screen.minX, accuracy: 2, "\(window.frame) in \(screen)")
    }

    /// The new-window view makes a typed session: Return on its New Session row starts it on This Mac and opens it
    /// as the window's first page; Add Machine opens Settings at its add form, Edit Machines at Machines.
    func testNewWindowMakesATypedSession() async throws {
        let eight = try env("OVVI_SESSION8")
        // Down first: a run cut short may have left it.
        try await Self.post("\(eight)/stress", Data())
        addTeardownBlock { _ = try? await Self.post("\(eight)/stress", Data()) }
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

    /// ⌘N shows This Mac's sessions from its first frame, from the page's own read, while its own read answers 2 s
    /// late: no spinner row comes first, and the rows do not change under the pointer.
    func testNewWindowShowsKnownSessionsAtOnce() throws {
        app.launchEnvironment["SHELL"] = "\(Self.agents)/login-shell"
        app.launchEnvironment["PATH"] = "\(Self.fixtures)/late-herdr:/usr/bin:/bin"
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        relaunch()
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        // The page's session list is read: Open Session lists it.
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

    /// ⌘Q with two windows on two sessions and a launch bring both windows back, each with its session; a launch
    /// after the last window closed shows the new-window view.
    func testRelaunchRestoresEveryWindowWithItsSession() async throws {
        try await forgetWindows()
        app.launchArguments = ["-session", one, "-NSQuitAlwaysKeepsWindows", "YES"] + Self.noConfig
        app.launch()
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        // One window to start from: a window an earlier run saved may come back too.
        let main = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'"))
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

        app.launchArguments = ["-defaultSession", one, "-machines", "[]"] + Self.noConfig
        app.launch()
        XCTAssertTrue(until(connect) { headers.sorted() == [one, two].sorted() }, "\(headers)")
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(main.count, 2)
        XCTAssertFalse(element("picker.title").exists)

        // Every window closed, then ⌘Q: the next launch shows the view, connected to nothing.
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

    /// Each main window's page header, the session in view.
    private var headers: [String] {
        app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'")).allElementsBoundByIndex
            .compactMap { window in
                let header = element("sidebar.header", in: window)
                return header.exists ? header.value as? String : nil
            }
    }

    /// A launch with no window to restore and no `-session` connects to nothing: the window lists the sessions to pick
    /// from, and no card streams.
    func testALaunchWithNothingToRestoreConnectsToNothing() async throws {
        app.terminate()
        app.launchArguments = ["-defaultSession", one, "-machines", "[]", "-ApplePersistenceIgnoreState", "YES"]
            + Self.noConfig
        app.launch()
        XCTAssertTrue(element("picker.local.\(one)").exists(within: connect))
        XCTAssertTrue(app.staticTexts["Ovvi"].exists)
        XCTAssertFalse(element("sidebar").exists)
        // `-machines []` holds without `-session` too: This Mac's group alone, never the user's machines (a check
        // only on a Mac with machines of its own; CI has none).
        let groups = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'picker.section.'"))
        XCTAssertEqual(groups.count, 1)
        // Still no page a moment later, and one window.
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(element("sidebar").exists)
        XCTAssertEqual(app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'")).count, 1)
        keepScreenshot("new window")
    }

    /// The window that is not this one, once there are two; it shows session one.
    func otherWindow(than identifier: String) throws -> XCUIElement {
        XCTAssertTrue(app.windows.element(boundBy: 1).exists(within: 3))
        XCTAssertEqual(app.windows.count, 2)
        let other = try XCTUnwrap(app.windows.allElementsBoundByIndex.map(\.identifier).first { $0 != identifier })
        let window = app.windows[other]
        XCTAssertTrue(element("terminal.w1:p1", in: window).exists(within: connect))
        return window
    }

    /// The terminal's `control` and `observe` runs, any client's, settle at these counts.
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
