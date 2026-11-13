import XCTest

/// The welcome panel (ui/welcome): on a first launch (`-welcomeDone NO`; scripts/e2e.sh marks it done for every other
/// test), from Settings ▸ General, and its herdr step with a fake installer, never herdr.dev's.
extension OvviUITests {
    var welcomeNext: XCUIElement {
        element("welcome.next")
    }

    /// The dots' "page of pages".
    var welcomePage: String {
        element("welcome.dots").stringValue
    }

    /// A first launch shows it; its pictures follow the appearance; → and ← turn the pages, Return is Next, a menu key
    /// does nothing behind it, Get Started closes it, and the next launch shows none. With herdr found there is no
    /// herdr step.
    func testTheWelcomeTurnsItsPagesAndClosesForGood() async throws {
        step("Welcome: a first launch shows only the welcome, and ⌘T does nothing behind it")
        try await Self.post("\(one)/welcome", Data("forget".utf8))
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/welcome", Data("done".utf8)) }
        relaunch(one)
        XCTAssertTrue(welcomeNext.exists(within: connect), "no welcome on a first launch")
        XCTAssertFalse(element("titlebar.machine").exists, "a window behind the welcome on a first launch")
        let count = try XCTUnwrap(welcomePage.split(separator: " ").last.flatMap { Int($0) }, welcomePage)
        XCTAssertEqual(welcomePage, "1 of \(count)")
        let tabs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'")).count
        app.typeKey("t", modifierFlags: .command)
        XCTAssertFalse(until(2) {
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'")).count
                != tabs
        }, "⌘T made a tab behind the welcome")

        step("Welcome: the pictures follow the appearance")
        let picture = element("welcome.picture")
        XCTAssertTrue(picture.exists(within: 3))
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        for look in ["Light", "Dark"] {
            pick("Appearance", look)
            XCTAssertTrue(until(3) { picture.stringValue.hasSuffix(" \(look.lowercased())") }, picture.stringValue)
        }

        step("Welcome: → ← and Return turn the pages, Get Started closes it")
        // A key during the intro only ends it: the walk starts once it is gone.
        XCTAssertTrue(element("welcome.intro").vanishes(within: 5), "the intro stays")
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(element("welcome.dots").has(\.stringValue, "2 of \(count)", within: 3))
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(element("welcome.dots").has(\.stringValue, "1 of \(count)", within: 3))
        for page in 2 ... count {
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(element("welcome.dots").has(\.stringValue, "\(page) of \(count)", within: 3))
            XCTAssertFalse(element("welcome.herdr.install").exists, "a herdr step with herdr installed")
        }
        XCTAssertEqual(welcomeNext.label, "Get Started")
        welcomeNext.click()
        XCTAssertTrue(welcomeNext.vanishes(within: 3))
        XCTAssertTrue(element("titlebar.machine").exists(within: connect), "no window after Get Started")

        step("Welcome: the next launch shows none")
        relaunch(one)
        XCTAssertTrue(element("titlebar.machine").exists(within: connect), "no window on the launch after Get Started")
        // The window opens only when no welcome shows on this launch (Welcome.firstLaunch).
        XCTAssertFalse(welcomeNext.exists, "the welcome again after it was done")
        showTheWelcomeFromSettings()
    }

    /// A first launch, as after scripts/reset-app-data.sh (macOS keeps saved windows where it needs Full Disk Access),
    /// shows only the welcome: a window macOS saved neither comes back nor connects. Skip opens the new-window list,
    /// and the next launch brings that window back, not the old one.
    func testAFirstLaunchShowsOnlyTheWelcomeOverSavedWindows() async throws {
        step("Welcome: a window saved with its session")
        try await forgetWindows()
        relaunch(windows: .saved)
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        step("Welcome: the first launch shows only the welcome")
        try await Self.post("\(one)/welcome", Data("forget".utf8))
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/welcome", Data("done".utf8)) }
        relaunch(windows: .restored)
        XCTAssertTrue(welcomeNext.exists(within: connect), "no welcome on a first launch")
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(mainWindows.count, 0, "a saved window came back behind the welcome")
        // The panel is no window to XCUITest: the whole screen.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "first launch"
        shot.lifetime = .keepAlways
        add(shot)

        step("Welcome: Skip opens the new-window list; the next launch restores it, not the old window")
        XCTAssertTrue(element("welcome.intro").vanishes(within: 5), "the intro stays")
        element("welcome.skip").click()
        XCTAssertTrue(element("picker.local.\(one)").exists(within: connect), "no new-window list after Skip")
        XCTAssertEqual(mainWindows.count, 1)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        relaunch(windows: .restored)
        XCTAssertTrue(element("picker.local.\(one)").exists(within: connect))
        XCTAssertFalse(element("workspace.w1").exists, "the window saved before the first launch came back")
        XCTAssertEqual(mainWindows.count, 1)
    }

    /// Settings ▸ General ▸ Show Welcome, found by a search, opens it again; Esc closes it from its first page and from
    /// its last.
    private func showTheWelcomeFromSettings() {
        step("Welcome: Settings shows it again, and Esc on its first page closes it")
        app.typeKey(",", modifierFlags: .command)
        let search = settingsWindow.searchFields.firstMatch
        XCTAssertTrue(search.exists(within: 3))
        search.click()
        app.typeText("onboarding")
        element("settings.search.general.welcome", in: settingsWindow).click()
        let show = element("settings.general.welcome", in: settingsWindow)
        show.click()
        XCTAssertTrue(welcomeNext.exists(within: 5))
        XCTAssertEqual(welcomePage.prefix(5), "1 of ")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(welcomeNext.vanishes(within: 3))

        step("Welcome: Esc on its last page closes it too, as Get Started does")
        show.click()
        // Opened a second time, it took 5 s to draw in the VM.
        XCTAssertTrue(welcomeNext.exists(within: connect))
        // It plays its intro again, and a key during the intro only ends it.
        XCTAssertTrue(element("welcome.intro").vanishes(within: 5), "the intro stays")
        for _ in 0 ..< 12 where welcomeNext.label == "Next" {
            let page = welcomePage
            app.typeKey(.rightArrow, modifierFlags: [])
            XCTAssertTrue(until(3) { welcomePage != page }, "→ stayed on \(page)")
        }
        XCTAssertEqual(welcomeNext.label, "Get Started")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(welcomeNext.vanishes(within: 3))
    }

    /// Without herdr the herdr step shows; Next waits for it. Install shows the installer's line, then Next goes on;
    /// a failed install says why and Retry runs it again.
    func testTheWelcomeInstallsAMissingHerdr() throws {
        try launchWithoutHerdr(install: "\(Self.fixtures)/no-herdr/install")
        let install = try walkToTheHerdrStep()
        XCTAssertFalse(welcomeNext.isEnabled)
        install.click()
        XCTAssertTrue(element("welcome.herdr.progress").has(\.stringValue, "> downloading v9.9.9...", within: 3))
        XCTAssertTrue(welcomeNext.has(\.isEnabled, true, within: connect))
        XCTAssertFalse(install.exists)

        try launchWithoutHerdr(install: #"echo "  > fetching..."; echo "  x cannot reach herdr.dev" >&2; exit 1"#)
        let retry = try walkToTheHerdrStep()
        retry.click()
        let failure = element("welcome.herdr.failure")
        XCTAssertTrue(failure.has(\.stringValue, "> fetching...\nx cannot reach herdr.dev\n"
                + "The installer exited with status 1.", within: connect), failure.stringValue)
        XCTAssertEqual(retry.label, "Retry")
        XCTAssertFalse(welcomeNext.isEnabled)
        element("welcome.skip").click()
        XCTAssertTrue(welcomeNext.vanishes(within: 3))
        XCTAssertTrue(element("titlebar.machine").exists(within: connect), "no window after Skip")
    }

    /// A login shell slower than the launch's 3 s bound still finds herdr before the panel opens: no herdr step.
    func testASlowLoginShellStillLeavesOutTheHerdrStep() throws {
        app.launchEnvironment["SHELL"] = "\(Self.fixtures)/slow-shell/login-shell"
        let herdr = try URL(filePath: env("OVVI_HERDR")).deletingLastPathComponent().path
        app.launchEnvironment["PATH"] = "\(herdr):/usr/bin:/bin"
        relaunch(one, ["-welcomeDone", "NO"])
        XCTAssertTrue(welcomeNext.exists(within: connect))
        XCTAssertTrue(element("welcome.intro").vanishes(within: 5), "the intro stays")
        while welcomeNext.label == "Next" {
            XCTAssertFalse(element("welcome.herdr.install").exists, "a herdr step with herdr installed")
            let page = welcomePage
            welcomeNext.click()
            XCTAssertTrue(until(3) { welcomePage != page }, "Next stayed on \(page)")
        }
        XCTAssertFalse(element("welcome.herdr.install").exists, "a herdr step with herdr installed")
        welcomeNext.click()
        XCTAssertTrue(welcomeNext.vanishes(within: 3))
    }

    /// A Mac with no herdr on its login shell's PATH (HerdrInstallTests' seam), the welcome not done yet.
    func launchWithoutHerdr(install: String) throws {
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        app.launchEnvironment["SHELL"] = "\(Self.fixtures)/no-herdr/login-shell"
        app.launchEnvironment["PATH"] = "/usr/bin:/bin"
        relaunch(one, ["-welcomeDone", "NO", "-herdrInstall", install])
        XCTAssertTrue(welcomeNext.exists(within: connect))
        // A click during the intro only ends it.
        XCTAssertTrue(element("welcome.intro").vanishes(within: 5), "the intro stays")
    }

    /// Next until the herdr step's button shows: its button. herdr is missing before the panel opens, so the step is
    /// there from the first page on and a page that shows needs no wait for it.
    func walkToTheHerdrStep() throws -> XCUIElement {
        let install = element("welcome.herdr.install")
        while !install.exists, welcomeNext.label == "Next" {
            let page = welcomePage
            welcomeNext.click()
            XCTAssertTrue(until(3) { welcomePage != page }, "Next stayed on \(page)")
        }
        XCTAssertTrue(install.exists, "no herdr step")
        return install
    }

    /// Not a check: films the welcome in dark and then light, with a missing herdr and the fake installer, to
    /// /tmp/ovvi-welcome/<checkout>-<look>.mp4, one name per checkout as worktrees film at once (on demand, local: the
    /// recording needs the screen recording permission).
    func testWelcomeFilm() async throws {
        executionTimeAllowance = 600
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/record-stop") }
        for look in ["dark", "light"] {
            app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
            app.launchEnvironment["SHELL"] = "\(Self.fixtures)/no-herdr/login-shell"
            // The step shows herdr.dev's command; its `curl` is a fixture that gives the fake installer.
            app.launchEnvironment["PATH"] = "\(Self.fixtures)/films:/usr/bin:/bin"
            relaunch(one, ["-welcomeDone", "NO", "-appearance", look, "-forceMotion", "YES", "-welcomeAfter", "20"])
            // The panel's glass blurs what is behind it on screen: the app's own window, filling the screen. A first
            // launch opens none until the welcome ends: the film opens one (File ▸ New Window) before the panel shows.
            // Without herdr it is the new-window view, whose one row installs herdr.
            XCTAssertTrue(app.menuBars.menuBarItems["File"].exists(within: connect))
            app.menuBars.menuBarItems["File"].click()
            app.menuBars.menuItems["New Window"].click()
            // A new window fills the screen by itself.
            XCTAssertTrue(until(connect) { app.windows.count > 0 }, "no window")
            do {
                let checkout = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                try await Self.post("\(one)/record",
                                    Data("/tmp/ovvi-welcome/\(checkout.lastPathComponent)-\(look).mp4".utf8))
            } catch {
                throw XCTSkip("\(error)")
            }
            XCTAssertTrue(welcomeNext.exists(within: connect))
            // The intro (about 2 s), then each page's clip plays through (the longest is 20 s): pages turn only on
            // Next. The herdr step is last: why, Install, then all set.
            try await Task.sleep(for: .seconds(2.5 + 21))
            while welcomeNext.label != "Get Started" {
                welcomeNext.click()
                try await Task.sleep(for: .seconds(21))
            }
            let install = element("welcome.herdr.install")
            if install.exists {
                try await Task.sleep(for: .seconds(5))
                install.click()
                _ = welcomeNext.has(\.isEnabled, true, within: connect)
                try await Task.sleep(for: .seconds(5))
            }
            welcomeNext.click()
            try await Task.sleep(for: .seconds(1))
            try await Self.post("\(one)/record-stop")
        }
    }
}
