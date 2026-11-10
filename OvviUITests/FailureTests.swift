import XCTest

extension OvviUITests {
    func testStoppedSessionSaysSoAndComesBackWhenStartedAgain() async throws {
        let (workspace, pane) = try await shown(running(five))
        relaunch(five)
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.exists(within: connect))
        try await expect("its stream") { try await streams(five).count == 1 }

        try await Self.post("\(five)/stop")
        XCTAssertTrue(element("detail.start").exists(within: 10))
        XCTAssertFalse(terminal.exists)
        XCTAssertFalse(element("titlebar.new-tab").isEnabled)
        let file = app.menuBars.menuBarItems["File"]
        file.click()
        XCTAssertFalse(file.menuItems["New Tab"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        // The button: its open context menu carries the same identifier.
        let row = app.buttons["workspace.\(workspace)"]
        row.rightClick()
        XCTAssertFalse(app.menuItems["Rename Space"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.menuItems["Rename Space"].vanishes(within: 2))
        row.doubleClick()
        XCTAssertFalse(element("workspace.\(workspace).rename").exists(within: 1))
        keepScreenshot("not running")
        try await expect("no stream") { try await streams(five).isEmpty }

        try await Self.post("\(five)/start")
        XCTAssertTrue(terminal.exists(within: 10))
        try await expect("one stream again") { try await streams(five).count == 1 }
        let tab = try await createTab(in: workspace, label: "back", session: five).tab
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
    }

    func testLaunchOnAStoppedSessionStartsIt() async throws {
        let workspace = try await shown(running(five)).workspace
        try await Self.post("\(five)/stop")
        try await expect("five to stop") { try await answer(five) == nil }
        relaunch(five)
        XCTAssertTrue(element("workspace.\(workspace)").exists(within: connect))
        try await Self.snapshot(five)
    }

    func testAFailedStartShowsStartingAndKeepsWhy() async throws {
        _ = try await running(five)
        try await Self.post("\(five)/stop")
        try await expect("five to stop") { try await answer(five) == nil }
        app.launchEnvironment["SHELL"] = "\(Self.agents)/login-shell"
        app.launchEnvironment["PATH"] = "\(Self.fixtures)/no-server:/usr/bin:/bin"
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        relaunch(five, ["-startTimeout", "2"])
        let why = element("detail.text"), start = element("detail.start")
        let failed = { why.has(\.stringValue, "The server did not answer within 2.0 seconds", within: $0) }
        XCTAssertTrue(failed(connect), why.debugDescription)
        start.click()
        XCTAssertTrue(element("detail.starting").exists(within: 1))
        XCTAssertTrue(start.exists(within: 5))
        XCTAssertTrue(failed(1), why.debugDescription)
        keepScreenshot("start failed")
        XCTAssertFalse(why.vanishes(within: 5))

        try await Self.post("\(five)/start")
        XCTAssertTrue(start.vanishes(within: connect))
    }

    /// A session with no space: the Start makes one, and the first read after it answers 2 s late. Start must not
    /// show again meanwhile.
    func testAStartShowsStartingUntilTheSessionAnswers() async throws {
        for workspace in try await running(five)["workspaces"] as? [[String: Any]] ?? [] {
            try await Self.call(five, "workspace.close", ["workspace_id": workspace["workspace_id"] ?? ""])
        }
        app.launchEnvironment["SHELL"] = "\(Self.agents)/login-shell"
        let herdr = try URL(filePath: env("OVVI_HERDR")).deletingLastPathComponent().path
        app.launchEnvironment["PATH"] = "\(Self.fixtures)/late-snapshot:\(herdr):/usr/bin:/bin"
        relaunch(five)
        let start = element("detail.start"), newTab = element("titlebar.new-tab")
        XCTAssertTrue(element("detail.empty").firstMatch.exists(within: connect))
        try await Self.post("\(five)/stop")
        XCTAssertTrue(start.exists(within: 10))
        start.click()
        XCTAssertTrue(element("detail.starting").exists(within: 1))
        XCTAssertTrue(until(connect) { start.exists || newTab.isEnabled })
        XCTAssertFalse(start.exists, "Start showed again before the session answered")
        try await Self.snapshot(five)
    }

    func testAnUnreachableMachineShowsConnectingThenReconnecting() {
        let down = #"[{"id":"e2e-down","name":"devbox","target":"ovvi-e2e@192.0.2.1","icon":"server.rack"}]"#
        relaunch(one, ["-machines", down, "-machine", "e2e-down"])
        XCTAssertTrue(element("detail.connecting").exists(within: connect))
        let reconnecting = element("detail.reconnecting")
        XCTAssertTrue(reconnecting.exists(within: connect))
        XCTAssertFalse(element("detail.reconnecting.detail").stringValue.isEmpty)
        keepScreenshot("reconnecting")
    }

    func testPaneClosedInHerdrDropsItsCardAndStream() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, first) = try await newTab("gone")
        let second = try await split(first)
        element("tab.\(tab)").click()
        let doomed = try await terminalID(second)
        try await expect("its stream") { try await streams(one).contains { $0.contains(doomed) } }

        try await Self.call(one, "pane.close", ["pane_id": second])
        XCTAssertTrue(element("pane.\(second)").vanishes(within: 3))
        try await expect("its stream to end") { try await !streams(one).contains { $0.contains(doomed) } }
        XCTAssertTrue(element("pane.\(first)").exists)
    }

    /// herdr refuses the stream for a lasting reason: the card says so, and asks herdr again at most every 5 s, not at
    /// each snapshot. While the page reconnects, the page alone says why; the card streams again once it is live. The
    /// pane's own shell writes and counts the fixture's files: the runner is sandboxed.
    func testAFailedStreamRetriesSlowlyAndWaitsOutAReconnect() async throws {
        let flags = "/tmp/ovvi-e2e-failing-\(UUID().uuidString.prefix(8))"
        let (tab, pane) = try await createTab(in: "w2", label: "stopped")
        closeAfter("tab", tab)
        sendAfter("rm -rf \(flags)\r", to: pane)
        let terminal = try await terminalID(pane)
        let opens = { () async throws -> Int in
            let text = try await self.shell("echo opens=$(grep -c \(terminal) \(flags)/opens)-$((6*7))", in: pane)
            return try XCTUnwrap(text.firstMatch(of: /opens=(\d+)-42/).flatMap { Int($0.1) }, text)
        }
        try await waitForPrompt(pane)
        _ = try await shell("mkdir -p \(flags) && : >\(flags)/terminal && : >\(flags)/opens", in: pane)
        app.launchEnvironment["SHELL"] = "\(Self.agents)/login-shell"
        app.launchEnvironment["PATH"] = "\(Self.fixtures)/failing-herdr:/usr/bin:/bin"
        app.launchEnvironment["OVVI_E2E_HERDR"] = try env("OVVI_HERDR")
        app.launchEnvironment["OVVI_E2E_FLAGS"] = flags
        relaunch()
        let row = element("workspace.w2")
        XCTAssertTrue(row.exists(within: connect))
        row.click()
        try await show(tab)
        let retry = element("pane.\(pane).retry")
        XCTAssertTrue(retry.exists(within: 10))
        // A snapshot each, inside the 5 s.
        for label in 0 ..< 6 {
            try await relabel(pane, "stopped \(label)")
            try await Task.sleep(for: .milliseconds(250))
            // A retry keeps its panel: no blink to the card's fill.
            XCTAssertTrue(retry.exists, "turn \(label)")
        }
        let opened = try await opens()
        XCTAssertLessThanOrEqual(opened, 2)
        XCTAssertTrue(retry.exists)
        keepScreenshot("a failed stream")

        retry.click()
        try await expect("Retry to open it again") { try await opens() > opened }
        XCTAssertTrue(retry.exists(within: 3))

        _ = try await shell(": >\(flags)/down", in: pane)
        try await relabel(pane, "stopped down")
        XCTAssertTrue(element("detail.reconnecting").exists(within: 10))
        XCTAssertTrue(retry.vanishes(within: 2))
        keepScreenshot("reconnecting, a failed stream")

        _ = try await shell("rm \(flags)/down \(flags)/terminal", in: pane)
        XCTAssertTrue(element("detail.reconnecting").vanishes(within: 10))
        XCTAssertTrue(element("pane.\(pane)").has(\.stringValue, "", within: 10))
        XCTAssertFalse(retry.exists)
    }

    /// The screen once the command ran: the typed line holds `$((6*7))`, not 42.
    private func shell(_ command: String, in pane: String) async throws -> String {
        let done = "done-\(UUID().uuidString.prefix(8))-"
        try await send("clear; \(command); echo \(done)$((6*7))\r", to: pane)
        return try await poll("\(command) to run") { () async throws -> String? in
            let text = try await read(pane)
            return text.contains("\(done)42") ? text : nil
        }
    }

    func testClosingAPageAndQuittingLeaveNoStreams() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        XCTAssertTrue(element("tab.w1:t1").isSelected)
        try await expectStreams(3, 0)
        for _ in 0 ..< 2 {
            openPage(two)
            try await expectStreams(3, 1)
            closePage(two)
            try await expect("no herdr runs on two") { try await runs(two).isEmpty }
            try await expectStreams(3, 0)
        }

        // No herdr run outlives the app: each ends when its stdin closes.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        try await expect("no herdr runs left") {
            let left = try await (runs(one), runs(two))
            return left.0.isEmpty && left.1.isEmpty
        }
    }

    private func expectStreams(_ inOne: Int, _ inTwo: Int) async throws {
        try await expect("\(inOne) streams on one, \(inTwo) on two") {
            let counts = try await (streams(one).count, streams(two).count)
            return counts == (inOne, inTwo)
        }
    }
}
