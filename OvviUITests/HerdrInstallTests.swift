import XCTest

/// Install herdr (ui/states), each time with a fake installer, never herdr.dev's: on This Mac under a login shell with
/// no herdr, and over SSH on CI's ovvi-pw, which has none.
extension OvviUITests {
    /// The page shows the command and Install; the installer's lines while it runs; then the page connects.
    func testInstallingHerdrOnThisMacShowsItsProgressAndConnects() throws {
        let install = "\(Self.fixtures)/no-herdr/install"
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        app.launchEnvironment["SHELL"] = "\(Self.fixtures)/no-herdr/login-shell"
        app.launchEnvironment["PATH"] = "/usr/bin:/bin"
        relaunch(one, ["-herdrInstall", install])
        let button = element("detail.install")
        XCTAssertTrue(button.exists(within: connect))
        XCTAssertTrue(app.staticTexts["herdr is not installed"].exists)
        XCTAssertEqual(element("detail.text").stringValue, install)
        keepScreenshot("not installed")
        button.click()
        XCTAssertTrue(element("detail.installing.detail").has(\.stringValue, "> downloading v9.9.9...", within: 3))
        keepScreenshot("installing")
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
    }

    /// A failed install says what the installer printed, and Try Again runs it again.
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

    /// The machine button's Add Remote Host, filled and added.
    func addHost(_ name: String, _ target: String) {
        element("titlebar.machine").click()
        app.menuItems["Add Remote Host…"].click()
        let field = element("host.name")
        XCTAssertTrue(field.exists(within: 3))
        field.click()
        app.typeText(name)
        element("host.target").click()
        app.typeText(target)
        element("host.save").click()
    }

    /// ovvi-pw's password (or another), in the hidden field of ssh's question; Return answers.
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
