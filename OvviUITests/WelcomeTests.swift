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

    /// A first launch shows it, its intro first; → and ← turn the pages, Return is Next, a menu key does nothing behind
    /// it, Get Started closes it, and the next launch shows none. With herdr found there is no herdr step.
    func testTheWelcomeTurnsItsPagesAndClosesForGood() async throws {
        try await Self.post("\(one)/welcome", Data("forget".utf8))
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/welcome", Data("done".utf8)) }
        relaunch(one, ["-welcomeHold", "60"])
        // The intro first (the mark and the name); → during it only ends it, on the first page.
        let intro = element("welcome.intro")
        XCTAssertTrue(intro.exists(within: connect), "no welcome on a first launch")
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(intro.vanishes(within: 1.5), "→ left the intro on")
        XCTAssertTrue(welcomeNext.exists(within: 2))
        let count = try XCTUnwrap(welcomePage.split(separator: " ").last.flatMap { Int($0) }, welcomePage)
        XCTAssertEqual(welcomePage, "1 of \(count)")
        let tabs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'")).count
        app.typeKey("t", modifierFlags: .command)
        XCTAssertFalse(until(2) {
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'")).count
                != tabs
        }, "⌘T made a tab behind the welcome")
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

        relaunch(one)
        XCTAssertTrue(element("titlebar.machine").exists(within: connect))
        XCTAssertFalse(welcomeNext.exists(within: 2), "the welcome again after it was done")
    }

    /// Settings ▸ General ▸ Show Welcome, found by a search, opens it again; Esc skips it from its first page.
    func testSettingsShowsTheWelcomeAgain() {
        relaunch(one)
        XCTAssertTrue(element("titlebar.machine").exists(within: connect))
        app.typeKey(",", modifierFlags: .command)
        let search = settingsWindow.searchFields.firstMatch
        XCTAssertTrue(search.exists(within: 3))
        search.click()
        app.typeText("onboarding")
        element("settings.search.general.welcome", in: settingsWindow).click()
        element("settings.general.welcome", in: settingsWindow).click()
        XCTAssertTrue(welcomeNext.exists(within: 5))
        XCTAssertEqual(welcomePage.prefix(5), "1 of ")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(welcomeNext.vanishes(within: 3))
    }

    /// The pictures are the set of the app's appearance, and switch with it while the panel shows.
    func testTheWelcomePicturesFollowTheAppearance() {
        relaunch(one, ["-welcomeDone", "NO"])
        let picture = element("welcome.picture")
        XCTAssertTrue(picture.exists(within: connect))
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        for look in ["Light", "Dark"] {
            pick("Appearance", look)
            XCTAssertTrue(until(3) { picture.stringValue.hasSuffix(" \(look.lowercased())") }, picture.stringValue)
        }
        // Esc on the last page closes it too, as Get Started does.
        for _ in 0 ..< 12 where welcomeNext.label == "Next" {
            app.typeKey(.rightArrow, modifierFlags: [])
            _ = until(1) { welcomeNext.label == "Get Started" }
        }
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
    }

    /// A Mac with no herdr on its login shell's PATH (HerdrInstallTests' seam), the welcome not done yet.
    func launchWithoutHerdr(install: String) throws {
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        app.launchEnvironment["SHELL"] = "\(Self.fixtures)/no-herdr/login-shell"
        app.launchEnvironment["PATH"] = "/usr/bin:/bin"
        relaunch(one, ["-welcomeDone", "NO", "-herdrInstall", install])
        XCTAssertTrue(welcomeNext.exists(within: connect))
    }

    /// Next until the herdr step's button shows: its button.
    func walkToTheHerdrStep() throws -> XCUIElement {
        let install = element("welcome.herdr.install")
        while !install.exists(within: 1), welcomeNext.label == "Next" {
            welcomeNext.click()
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
            // The panel's glass blurs what is behind it on screen: the app's own window, filling the screen.
            let main = app.windows.containing(.any, identifier: "titlebar.machine").firstMatch
            XCTAssertTrue(main.exists(within: connect))
            if let screen = NSScreen.main?.visibleFrame, main.frame.width < screen.width - 1 {
                app.menuBars.menuBarItems["Window"].click()
                app.menuBars.menuItems["Zoom"].click()
            }
            do {
                let checkout = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                try await Self.post("\(one)/record",
                                    Data("/tmp/ovvi-welcome/\(checkout.lastPathComponent)-\(look).mp4".utf8))
            } catch {
                throw XCTSkip("\(error)")
            }
            // The intro unwatched (queries of the app's whole tree stall its main thread), then each page for 4.5 s,
            // as its pictures rise and move in. The herdr step is the last.
            XCTAssertTrue(element("welcome.intro").exists(within: connect))
            try await Task.sleep(for: .seconds(3.5))
            let install = element("welcome.herdr.install")
            var last = false
            while !last {
                try await Task.sleep(for: .seconds(4.5))
                if install.exists {
                    install.click()
                    _ = welcomeNext.has(\.isEnabled, true, within: connect)
                    try await Task.sleep(for: .seconds(2))
                }
                last = welcomeNext.label == "Get Started"
                welcomeNext.click()
            }
            try await Task.sleep(for: .seconds(1))
            try await Self.post("\(one)/record-stop")
        }
    }
}
