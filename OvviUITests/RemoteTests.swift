import XCTest

/// Remote machines over SSH, against CI's sshd on localhost (`scripts/ci-sshd.sh`): ovvi-key is this
/// user with a key, so its sessions are the e2e ones; ovvi-pw asks a host key and a password and has no herdr. They
/// skip where no such sshd runs.
extension OvviUITests {
    /// Key Host, for a launch that starts on it (`-machine e2e-key`).
    static let keyHost = #"[{"id":"e2e-key","name":"Key Host","target":"ovvi-key","icon":"server.rack"}]"#

    func testAddingAKeyHostOpensItInANewWindowWithoutAsking() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        addHost("Key Host", "ovvi-key")
        // A new window on it, with session one from herdr over SSH; this one keeps its page.
        let remote = try otherWindow(than: identifier)
        XCTAssertEqual(machine(of: remote), "Key Host")
        XCTAssertEqual(machine(of: first), "This Mac")
        XCTAssertTrue(element("terminal.w1:p1", in: first).exists)
        XCTAssertFalse(element("ask.text").exists)
        keepScreenshot("remote window", of: remote)
        // Its own machine in its menu: nothing opens.
        element("titlebar.machine", in: remote).click()
        app.menuItems["Key Host"].firstMatch.click()
        XCTAssertFalse(app.windows.element(boundBy: 2).exists(within: 2))
        // Picked in the first window's menu, it brings the Key Host window forward: no new one.
        raise(first)
        element("titlebar.machine", in: first).click()
        app.menuItems["Key Host"].firstMatch.click()
        XCTAssertTrue(until(3) { app.windows.firstMatch.identifier == remote.identifier })
        XCTAssertFalse(app.windows.element(boundBy: 2).exists)
        XCTAssertEqual(machine(of: first), "This Mac")
        // ⌘N lists Key Host's sessions after This Mac's: a pick opens one there.
        app.typeKey("n", modifierFlags: .command)
        let pick = app.buttons.matching(NSPredicate(format: "identifier LIKE 'picker.*.\(one)'")).element(boundBy: 1)
        XCTAssertTrue(pick.exists(within: connect))
        pick.click()
        XCTAssertTrue(until(connect) { machine(of: app.windows.firstMatch) == "Key Host" })
        XCTAssertEqual(app.windows.count, 3)
        // It went through the host's ControlMaster.
        let dropped = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
        XCTAssertFalse(dropped.isEmpty)
    }

    func testAPasswordHostAsksAndNeverRetriesByItself() async throws {
        try await skipWithoutSSH()
        // Not one an earlier test left: it would need no password. Its host key is new again.
        try await Self.post("\(one)/ssh-drop", Data("ovvi-pw".utf8))
        try await Self.post("\(one)/ssh-forget", Data("ovvi-pw".utf8))
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        addHost("Password Host", "ovvi-pw")
        // A new host key, asked in the new window: its fingerprint on a line of its own, and Connect instead of
        // ssh's yes or no.
        let text = element("ask.text")
        XCTAssertTrue(text.exists(within: connect))
        XCTAssertFalse(element("ask.text", in: first).exists)
        XCTAssertTrue(element("terminal.w1:p1", in: first).exists)
        let facts = text.value as? String ?? ""
        XCTAssertTrue(facts.contains("fingerprint is:\nSHA256:"), facts)
        XCTAssertFalse(facts.contains("yes/no"), facts)
        keepScreenshot("host key")
        // The question replaces the page's Connecting.
        XCTAssertFalse(element("detail.connecting").exists)
        element("ask.ok").click()
        // A wrong password: ssh asks again.
        typePassword("wrong")
        typePassword()
        // Connecting again while ovvi-pw's slow login shell looks for herdr (scripts/ci-sshd.sh).
        XCTAssertTrue(element("detail.connecting").exists(within: 2))
        let missing = app.staticTexts["herdr is not installed on Password Host"]
        XCTAssertTrue(missing.exists(within: connect))

        // The connection dies: one try without a prompt, then Connect, and no more tries.
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

        // Connect asks again: Connecting from the click until the question, then until the session answers.
        // Disconnected never shows meanwhile.
        element("detail.connect").click()
        XCTAssertTrue(element("detail.connect").vanishes(within: 1))
        XCTAssertTrue(element("ask.answer").exists(within: connect))
        XCTAssertFalse(element("detail.connecting").exists)
        XCTAssertFalse(element("detail.connect").exists)
        typePassword()
        XCTAssertTrue(element("detail.connecting").exists(within: 2))
        XCTAssertFalse(element("detail.connect").exists)
        XCTAssertTrue(missing.exists(within: connect))
    }

    func testARemotePageComesBackAfterItsConnectionDies() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        let terminal = element("terminal.w1:p2")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p2")
        // Drawn first: a click while the card still loaded was lost, and the window then gave herdr's focused pane
        // the keyboard (the CI recording).
        XCTAssertTrue(drawn("w1:p2", within: connect), element("pane.w1:p2").stringValue)
        terminal.click()
        XCTAssertTrue(hasKeyboard(terminal))
        app.typeText("echo relay-$((40+2))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p2") { $0.contains("\nrelay-42") }

        let first = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
        XCTAssertFalse(first.isEmpty)
        // A new master without a prompt; the card streams again and takes keys.
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

    /// CI's sshd allows 2 sessions per connection (a strict server's limit): six panes, the events stream and every
    /// call still go through, over the one session of the relay.
    func testAHostThatAllowsTwoSessionsStreamsEveryPane() async throws {
        try await skipWithoutSSH()
        let (tab, first) = try await createWorkspace("many")
        var panes = [first]
        for (target, direction) in [(0, "right"), (0, "down"), (1, "down"), (1, "right"), (3, "down")] {
            let created = try await Self.call(
                one,
                "pane.split",
                ["target_pane_id": panes[target], "direction": direction,
                 "cwd": "/tmp", "focus": false],
            )
            try panes.append(id(created, "pane"))
        }
        var terminals: [String] = []
        for pane in panes {
            try await terminals.append(terminalID(pane))
        }
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
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

    /// Marks and float requests go over the relay: Key Host's panes in view are marked, and a request on one floats
    /// Key Host's pane (a float on This Mac, which has no window here, would be a notice).
    func testARemoteMachinesPanesAreMarkedAndFloatThere() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        try await markAndFloat()
    }

    /// A file dropped on Key Host's card is copied there, as herdr's remote client does, and the copy's path is pasted:
    /// `cat` reads it on the machine. The machine is this Mac, so the path must also not be the dropped file's own.
    func testAFileDroppedOnARemoteCardPastesItsCopysPath() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("drop")
        // By key: the test is about the drop, not about a click on a capsule just in over the relay.
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

    /// The machine menu's Add Machine opens Settings ▸ Machines at its form; the icon picker's search finds a dotted
    /// name only.
    func testAddMachineOpensSettingsAtItsForm() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
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

    /// Settings ▸ Machines edits a machine: a rename, a new target and icon reach its open window; Remove takes it
    /// off the machine menu.
    func testEditingARemoteHostRenamesItAndRemoveTakesItOff() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
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
        let window = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'")).firstMatch
        XCTAssertTrue(until(3) { machine(of: window) == "Build Box" })
        XCTAssertEqual(element("titlebar.machine", in: window).value as? String, "flask")
        XCTAssertTrue(element("terminal.w1:p1", in: window).exists)
        // The open page stays on its connection; Remove takes it off the list.
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

    /// A remote window's Open Session, from the machine menu and the sidebar, lists that machine's sessions and opens
    /// one as a page.
    func testARemoteWindowOpensAnotherSessionOfItsMachine() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
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

    /// Each window's Open Session lists its own machine's sessions only: Password Host has no herdr,
    /// so its window lists none of This Mac's, which the first window's panel just read.
    func testOpenSessionListsOnlyItsWindowsMachine() async throws {
        try await skipWithoutSSH()
        try await Self.post("\(one)/ssh-drop", Data("ovvi-pw".utf8))
        try await Self.post("\(one)/ssh-forget", Data("ovvi-pw".utf8))
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let first = app.windows.firstMatch.identifier
        openSessionPanel()
        XCTAssertTrue(element("open-session.session.\(two)").exists(within: connect))
        XCTAssertTrue(element("open-session.section.Running").exists)
        app.typeKey(.escape, modifierFlags: [])
        addHost("Password Host", "ovvi-pw")
        XCTAssertTrue(element("ask.text").exists(within: connect))
        element("ask.ok").click()
        typePassword()
        XCTAssertTrue(app.staticTexts["herdr is not installed on Password Host"].exists(within: connect))
        XCTAssertNotEqual(app.windows.firstMatch.identifier, first)
        let menu = element("titlebar.machine", in: app.windows.firstMatch)
        menu.click()
        menu.menuItems["Open Session…"].click()
        XCTAssertTrue(element("open-session.open.\(one)").exists(within: 3))
        XCTAssertFalse(until(2) { element("open-session.session.\(two)").exists })
        keepScreenshot("password host open session")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Settings ▸ Machines at Key Host's page, from the machine menu's Edit Machines.
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

    /// How many connections CI's sshd has seen.
    private func connections() async throws -> Int {
        try await field(Int(String(decoding: Self.post("\(one)/ssh-connections"), as: UTF8.self)), "sshd connections")
    }

    func skipWithoutSSH() async throws {
        if await (try? Self.post("\(one)/ssh-connections")) == nil {
            throw XCTSkip("no sshd on 127.0.0.1:2222 (scripts/ci-sshd.sh, CI only)")
        }
    }
}
