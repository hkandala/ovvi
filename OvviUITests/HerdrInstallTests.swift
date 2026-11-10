import XCTest

/// Always a fake installer, never herdr.dev's.
extension OvviUITests {
    func testInstallingHerdrOnThisMacShowsItsProgressAndConnects() throws {
        let install = "\(Self.fixtures)/no-herdr/install"
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        app.launchEnvironment["SHELL"] = "\(Self.fixtures)/no-herdr/login-shell"
        app.launchEnvironment["PATH"] = "/usr/bin:/bin"
        relaunch(one, ["-herdrInstall", install])
        let button = element("detail.install")
        XCTAssertTrue(button.exists(within: connect))
        XCTAssertTrue(app.staticTexts["herdr is not installed"].exists)
        XCTAssertEqual(element("detail.command").stringValue, install)
        XCTAssertTrue(element("detail.text").stringValue.hasPrefix("Ovvi runs on herdr"))
        keepScreenshot("not installed")
        button.click()
        XCTAssertTrue(element("detail.installing.detail").has(\.stringValue, "> downloading v9.9.9...", within: 3))
        keepScreenshot("installing")
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
    }

    func testAFailedInstallOnARemoteMachineSaysWhy() async throws {
        try await skipWithoutSSH()
        try await Self.post("\(one)/ssh-drop", Data("ovvi-pw".utf8))
        try await Self.post("\(one)/ssh-forget", Data("ovvi-pw".utf8))
        let install = #"echo "  > fetching latest release manifest..."; sleep 1; "#
            + #"echo "  x cannot reach herdr.dev" >&2; exit 1"#
        let host = #"[{"id":"e2e-pw","name":"Password Host","target":"ovvi-pw","icon":"cpu"}]"#
        relaunch(one, ["-machines", host, "-machine", "e2e-pw", "-herdrInstall", install])
        let connectButton = element("detail.connect")
        XCTAssertTrue(connectButton.exists(within: connect))
        connectButton.click()
        XCTAssertTrue(element("ask.ok").exists(within: connect))
        element("ask.ok").click()
        typePassword()
        let button = element("detail.install")
        XCTAssertTrue(button.exists(within: connect))
        XCTAssertTrue(app.staticTexts["herdr is not installed on Password Host"].exists)
        button.click()
        XCTAssertTrue(element("detail.installing").exists(within: 3))
        let text = element("detail.text")
        XCTAssertTrue(text.has(\.stringValue, "> fetching latest release manifest...\nx cannot reach herdr.dev\n"
                + "The installer exited with status 1.", within: connect), text.stringValue)
        keepScreenshot("install failed")
        XCTAssertTrue(app.staticTexts["herdr did not install"].exists)
        button.click()
        XCTAssertTrue(element("detail.installing").exists(within: 3))
    }

    func addHost(_ name: String, _ target: String) {
        // At rest first: right after a launch the title row lays out again, and a click on an earlier frame opens no
        // menu (on CI).
        let button = element("titlebar.machine")
        XCTAssertNotNil(steady(5) { button.isHittable ? button.frame : nil }, "\(button.frame)")
        button.click()
        app.menuItems["Add Machine…"].click()
        let settings = settingsWindow
        let field = element("settings.machine.name", in: settings)
        XCTAssertTrue(field.exists(within: 5))
        field.click()
        app.typeText(name)
        element("settings.machine.target", in: settings).click()
        app.typeText(target)
        element("settings.machine.save", in: settings).click()
        XCTAssertTrue(settings.vanishes(within: 3))
    }

    func typePassword(_ password: String = "ovvi-e2e-pw") {
        let answer = element("ask.answer")
        XCTAssertTrue(answer.exists(within: connect))
        XCTAssertEqual(answer.elementType, .secureTextField)
        answer.click()
        app.typeText(password)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(answer.vanishes(within: 3))
    }
}
