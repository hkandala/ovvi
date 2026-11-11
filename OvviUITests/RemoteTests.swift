import XCTest

/// CI's sshd on localhost (`scripts/ci-sshd.sh`): ovvi-key is this user with a key, so its sessions are the e2e ones;
/// ovvi-pw asks a host key and a password and has no herdr.
extension OvviUITests {
    func testAddingAKeyHostOpensItInANewWindowWithoutAsking() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        addHost("Key Host", "ovvi-key")
        let remote = try otherWindow(than: identifier)
        XCTAssertEqual(machine(of: remote), "Key Host")
        XCTAssertEqual(machine(of: first), "This Mac")
        XCTAssertTrue(element("terminal.w1:p1", in: first).exists)
        XCTAssertFalse(element("ask.text").exists)
        keepScreenshot("remote window", of: remote)
        element("titlebar.machine", in: remote).click()
        app.menuItems["Key Host"].firstMatch.click()
        XCTAssertFalse(app.windows.element(boundBy: 2).exists(within: 2))
        raise(first)
        element("titlebar.machine", in: first).click()
        app.menuItems["Key Host"].firstMatch.click()
        XCTAssertTrue(until(3) { app.windows.firstMatch.identifier == remote.identifier })
        XCTAssertFalse(app.windows.element(boundBy: 2).exists)
        XCTAssertEqual(machine(of: first), "This Mac")
        app.typeKey("n", modifierFlags: .command)
        let pick = app.buttons.matching(NSPredicate(format: "identifier LIKE 'picker.*.\(one)'")).element(boundBy: 1)
        XCTAssertTrue(pick.exists(within: connect))
        pick.click()
        XCTAssertTrue(until(connect) { machine(of: app.windows.firstMatch) == "Key Host" })
        XCTAssertEqual(app.windows.count, 3)
        let dropped = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
        XCTAssertFalse(dropped.isEmpty)
    }

    func testAPasswordHostAsksAndNeverRetriesByItself() async throws {
        step("Open Session in This Mac's window lists its sessions")
        try await skipWithoutSSH()
        // Not one an earlier test left: it would need no password. Its host key is new again.
        try await Self.post("\(one)/ssh-drop", Data("ovvi-pw".utf8))
        try await Self.post("\(one)/ssh-forget", Data("ovvi-pw".utf8))
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        openSessionPanel()
        XCTAssertTrue(element("open-session.session.\(two)").exists(within: connect))
        XCTAssertTrue(element("open-session.section.Running").exists)
        app.typeKey(.escape, modifierFlags: [])

        step("A password host asks for its host key and password")
        addHost("Password Host", "ovvi-pw")
        let text = element("ask.text")
        XCTAssertTrue(text.exists(within: connect))
        XCTAssertFalse(element("ask.text", in: first).exists)
        XCTAssertTrue(element("terminal.w1:p1", in: first).exists)
        let facts = text.value as? String ?? ""
        XCTAssertTrue(facts.contains("fingerprint is:\nSHA256:"), facts)
        XCTAssertFalse(facts.contains("yes/no"), facts)
        keepScreenshot("host key")
        XCTAssertFalse(element("detail.connecting").exists)
        element("ask.ok").click()
        typePassword("wrong")
        typePassword()
        // Connecting again while ovvi-pw's slow login shell looks for herdr (scripts/ci-sshd.sh).
        XCTAssertTrue(element("detail.connecting").exists(within: 2))
        let missing = app.staticTexts["herdr is not installed on Password Host"]
        XCTAssertTrue(missing.exists(within: connect))

        try await expectNoRetryAfterADrop()

        step("Connect asks for the password again")
        element("detail.connect").click()
        XCTAssertTrue(element("detail.connect").vanishes(within: 1))
        XCTAssertTrue(element("ask.answer").exists(within: connect))
        XCTAssertFalse(element("detail.connecting").exists)
        XCTAssertFalse(element("detail.connect").exists)
        typePassword()
        XCTAssertTrue(element("detail.connecting").exists(within: 2))
        XCTAssertFalse(element("detail.connect").exists)
        XCTAssertTrue(missing.exists(within: connect))

        step("Open Session in the remote window lists only its machine's sessions")
        XCTAssertNotEqual(app.windows.firstMatch.identifier, identifier)
        let menu = element("titlebar.machine", in: app.windows.firstMatch)
        menu.click()
        menu.menuItems["Open Session…"].click()
        XCTAssertTrue(element("open-session.open.\(one)").exists(within: 3))
        XCTAssertFalse(until(2) { element("open-session.session.\(two)").exists })
        keepScreenshot("password host open session")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testARemotePageComesBackAfterItsConnectionDies() async throws {
        try await skipWithoutSSH()
        relaunch(one, Self.onKeyHost)
        let terminal = element("terminal.w1:p2")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p2")
        // Drawn first: a click while the card still loads is lost, and the window then gives herdr's focused pane the
        // keyboard (on CI).
        XCTAssertTrue(drawn("w1:p2", within: connect), element("pane.w1:p2").stringValue)
        terminal.click()
        XCTAssertTrue(hasKeyboard(terminal))
        app.typeText("echo relay-$((40+2))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p2") { $0.contains("\nrelay-42") }

        let first = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
        XCTAssertFalse(first.isEmpty)
        try await poll("typing to reach the pane again", times: 20) { () async throws -> Bool? in
            app.typeText("echo relay-$((40+3))")
            app.typeKey(.return, modifierFlags: [])
            try await Task.sleep(for: .seconds(1))
            return try await read("w1:p2").contains("\nrelay-43") ? true : nil
        }
        XCTAssertFalse(element("ask.text").exists)
        XCTAssertFalse(element("detail.reconnecting").exists)
        let second = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
        XCTAssertFalse(second.isEmpty)
        XCTAssertNotEqual(first, second)
    }

    /// CI's sshd allows 2 sessions per connection (a strict server's limit).
    func testAHostThatAllowsTwoSessionsStreamsEveryPane() async throws {
        try await skipWithoutSSH()
        let (tab, first) = try await createWorkspace("many")
        var panes = [first]
        for (target, direction) in [(0, "right"), (0, "down"), (1, "down"), (1, "right"), (3, "down")] {
            try await panes.append(split(panes[target], direction))
        }
        var terminals: [String] = []
        for pane in panes {
            try await terminals.append(terminalID(pane))
        }
        relaunch(one, Self.onKeyHost)
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("workspace.\(workspace(of: tab))").click()
        try await expect("every pane of \(tab) to stream", times: 100) {
            let running = try await streams(one)
            return terminals.allSatisfy { terminal in running.contains { $0.contains(terminal) } }
        }
        keepScreenshot("six panes over two sessions")
        let last = element("terminal.\(panes[5])")
        XCTAssertTrue(last.exists)
        try await waitForPrompt(panes[5])
        XCTAssertTrue(drawn(panes[5], within: connect), element("pane.\(panes[5])").stringValue)
        last.click()
        XCTAssertTrue(hasKeyboard(last))
        app.typeText("echo ovvi-$((40+5))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor(panes[5]) { $0.contains("\novvi-45") }
    }

    func testARemoteMachinesPanesAreMarkedAndFloatThere() async throws {
        try await skipWithoutSSH()
        relaunch(one, Self.onKeyHost)
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        try await markAndFloat()
    }

    /// Key Host's stores are this Mac's fixture home: it is localhost.
    func testARemoteMachinesArchivedSessionsShowPastAStuckAgent() async throws {
        try await skipWithoutSSH()
        try await writeStuckStores()
        relaunch(one, Self.onKeyHost)
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        showsTheOthersPastAStuckAgent(on: "Key Host")
    }

    /// The machine is this Mac, so the path must also not be the dropped file's own.
    func testAFileDroppedOnARemoteCardPastesItsCopysPath() async throws {
        try await skipWithoutSSH()
        relaunch(one, Self.onKeyHost)
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("drop")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.has(\.isHittable, true, within: 3))
        try await waitForPrompt(pane)
        try await send("cat ", to: pane)
        let from = element("sidebar").frame, card = terminal.frame
        let points = "\(from.midX) \(from.midY) \(card.midX) \(card.midY)"
        let path = try await String(decoding: Self.post("\(one)/file-drag", Data(points.utf8)), as: UTF8.self)
        let folder = URL(filePath: path).deletingLastPathComponent().lastPathComponent
        try await waitFor(pane, toShow: #"/drop\ me\'s\ \(1\).txt"#)
        let pasted = try await read(pane).replacing("\n", with: "")
        XCTAssertTrue(pasted.contains("/ovvi-drops-"), pasted)
        XCTAssertFalse(pasted.contains(folder), pasted)
        try await send("\r", to: pane)
        try await waitFor(pane) { $0.contains("\novvi-e2e-dropped") }
    }

    func testAddMachineOpensSettingsAtItsForm() {
        step("The machine menu lists This Mac; picking it opens no window")
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("titlebar.machine").click()
        let thisMac = app.menuItems["This Mac"]
        XCTAssertTrue(thisMac.exists(within: 2))
        // Its checkmark is not in XCUITest's view of a menu item; the screenshot shows it.
        XCTAssertTrue(app.menuItems["Add Machine…"].exists)
        keepScreenshot("machine menu")
        thisMac.click()
        XCTAssertTrue(thisMac.vanishes(within: 2))
        XCTAssertFalse(until(0.5) { app.windows.count != 1 || !element("tab.w1:t2").exists })

        step("Add Machine opens Settings at its form; the icon search picks an icon")
        element("titlebar.machine").click()
        app.menuItems["Add Machine…"].click()
        let settings = settingsWindow
        XCTAssertTrue(element("settings.machine.name", in: settings).exists(within: 5))
        let icon = element("host.icon", in: settings)
        XCTAssertEqual(icon.value as? String, "server.rack")
        icon.click()
        XCTAssertTrue(element("host.icon.search").exists(within: 3))
        element("host.icon.search").click()
        app.typeText("globe.eu")
        XCTAssertTrue(element("host.icon.gamecontroller").vanishes(within: 2))
        keepScreenshot("icon search", of: settings)
        XCTAssertFalse(element("host.icon.globe").exists)
        let europe = element("host.icon.globe.europe.africa")
        europe.click()
        XCTAssertTrue(europe.vanishes(within: 2))
        XCTAssertEqual(icon.value as? String, "globe.europe.africa")
        settings.typeKey("w", modifierFlags: .command)
    }

    func testEditingARemoteHostRenamesItAndRemoveTakesItOff() async throws {
        try await skipWithoutSSH()
        relaunch(one, Self.onKeyHost)
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let settings = editHost()
        let name = element("settings.machine.name", in: settings)
        XCTAssertEqual(name.value as? String, "Key Host")
        let target = element("settings.machine.target", in: settings)
        XCTAssertEqual(target.value as? String, "ovvi-key")
        name.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Build Box")
        target.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("ovvi-pw")
        element("host.icon", in: settings).click()
        XCTAssertTrue(element("host.icon.search").exists(within: 3))
        element("host.icon.search").click()
        app.typeText("flask")
        element("host.icon.flask").click()
        element("settings.machine.save", in: settings).click()
        let window = mainWindows.firstMatch
        XCTAssertTrue(until(3) { machine(of: window) == "Build Box" })
        XCTAssertEqual(element("titlebar.machine", in: window).value as? String, "flask")
        XCTAssertTrue(element("terminal.w1:p1", in: window).exists)
        element("settings.machine.remove", in: settings).click()
        let sheet = settings.sheets.firstMatch
        XCTAssertTrue(sheet.buttons["Remove"].exists(within: 5))
        sheet.buttons["Remove"].click()
        XCTAssertTrue(name.vanishes(within: 3))
        settings.typeKey("w", modifierFlags: .command)
        element("titlebar.machine", in: window).click()
        XCTAssertTrue(app.menuItems["Add Machine…"].exists(within: 2))
        XCTAssertFalse(app.menuItems["Build Box"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testARemoteWindowOpensAnotherSessionOfItsMachine() async throws {
        try await skipWithoutSSH()
        relaunch(one, Self.onKeyHost)
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let menu = element("titlebar.machine")
        menu.click()
        menu.menuItems["Open Session…"].click()
        let other = element("open-session.session.\(two)")
        XCTAssertTrue(other.exists(within: connect))
        XCTAssertTrue(element("open-session.section.Running on Key Host").exists)
        keepScreenshot("remote open session")
        other.click()
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, two, within: connect))
        XCTAssertEqual(machine(of: app.windows.firstMatch), "Key Host")
        openSessionPanel()
        XCTAssertTrue(element("open-session.open.\(one)").exists(within: 2))
        XCTAssertTrue(element("open-session.open.\(two)").exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func expectNoRetryAfterADrop() async throws {
        step("A dropped password host never connects again by itself")
        let before = try await connections()
        let dropped = try await Self.post("\(one)/ssh-drop", Data("ovvi-pw".utf8))
        XCTAssertFalse(dropped.isEmpty)
        XCTAssertTrue(element("detail.connect").exists(within: connect))
        XCTAssertFalse(element("ask.text").exists)
        // ssh's own error, without the server's login banner (CI's sshd has one).
        let failure = element("detail.text").value as? String ?? ""
        XCTAssertTrue(failure.contains("Permission denied"), failure)
        XCTAssertFalse(failure.contains("Authorized users only"), failure)
        let after = try await connections()
        XCTAssertLessThanOrEqual(after, before + 1)
        for _ in 0 ..< 30 {
            try await Task.sleep(for: .milliseconds(200))
            let now = try await connections()
            XCTAssertEqual(now, after, "a retry connected by itself")
        }
        keepScreenshot("disconnected")
    }

    private func editHost() -> XCUIElement {
        element("titlebar.machine").click()
        app.menuItems["Edit Machines…"].click()
        let settings = settingsWindow
        let row = element("settings.machine.e2e-key", in: settings)
        XCTAssertTrue(row.exists(within: 5))
        row.click()
        XCTAssertTrue(element("settings.machine.name", in: settings).exists(within: 3))
        return settings
    }

    private func machine(of window: XCUIElement) -> String {
        element("window.machine", in: window).value as? String ?? ""
    }

    private func connections() async throws -> Int {
        try await field(Int(String(decoding: Self.post("\(one)/ssh-connections"), as: UTF8.self)), "sshd connections")
    }
}
