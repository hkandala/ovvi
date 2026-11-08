import XCTest

/// Pictures of the window's empty, connecting, loading, failed and not-installed states, in dark and in light, for a
/// designer's look (on demand). A state that does not show in time is shot anyway: the picture says what came.
extension OvviUITests {
    func testStateScenes() async throws {
        executionTimeAllowance = 900
        continueAfterFailure = true
        let ssh = await (try? Self.post("\(one)/ssh-connections")) != nil
        let machines = #"[{"id":"e2e-down","name":"devbox","target":"ovvi-e2e@192.0.2.1","icon":"server.rack"},"#
            + #"{"id":"e2e-pw","name":"Password Host","target":"ovvi-pw","icon":"cpu"}]"#
        for look in ["dark", "light"] {
            let base = ["-appearance", look, "-machines", machines]
            await liveScenes(look, base)
            try await sessionScenes(look, base)
            await herdrScenes(look, base)
            if ssh {
                try await askingScenes(look, base)
            }
            await settingsScene(look, base)
        }
    }

    /// The live window's own states: a filter, the palette, Open Session, cards, ⌘N.
    private func liveScenes(_ look: String, _ base: [String]) async {
        relaunch(one, base)
        _ = element("workspace.w2").exists(within: connect)
        element("sidebar.filter").click()
        app.typeText("zzzz")
        _ = element("workspace.w2").vanishes(within: 2)
        await stateShot(look, "S3 sidebar filter, no match")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("k", modifierFlags: .command)
        app.typeText("zzzzqq")
        await stateShot(look, "P2 palette, no match")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("t", modifierFlags: [.command, .option])
        try? await Task.sleep(for: .seconds(1))
        await stateShot(look, "P1 open session")
        app.typeKey(.escape, modifierFlags: [])
        // A blank browser, a failed one, and a plugin pane whose plugin is not on this Mac.
        if let (tab, left) = try? await newTab("scenes") {
            try? await waitForPrompt(left)
            element("tab.\(tab)").click()
            element("terminal.\(left)").click()
            if let (browser, _) = try? await chooseBrowser(besides: left, in: tab) {
                await stateShot(look, "C7 browser, blank")
                app.typeText("localhost:\(Int.random(in: 47100 ... 47900))\r")
                _ = element("browser.\(browser).retry").exists(within: 5)
                await stateShot(look, "C8 browser, load failed")
            }
            _ = try? await Self.call(one, "pane.rename", ["pane_id": left, "label": "ovvi:ovvi-e2e-gone#e2e1 x"])
            try? await Task.sleep(for: .seconds(1.5))
            await stateShot(look, "C6 plugin not on this Mac")
        }
        let first = app.windows.firstMatch.identifier
        app.typeKey("n", modifierFlags: .command)
        _ = app.windows.element(boundBy: 1).exists(within: 3)
        try? await Task.sleep(for: .seconds(2))
        if let other = app.windows.allElementsBoundByIndex.map(\.identifier).first(where: { $0 != first }) {
            app.windows[other].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)).hover()
            keepScreenshot("\(look) W12 new window", of: app.windows[other])
        }
    }

    /// A session that stopped; one with no workspaces (the app starts it with one, which closes).
    private func sessionScenes(_ look: String, _ base: [String]) async throws {
        let five = try env("OVVI_SESSION5"), eight = try env("OVVI_SESSION8")
        relaunch(five, base)
        _ = element("workspace.w1").exists(within: connect)
        _ = try? await Self.post("\(five)/stop")
        _ = element("detail.start").exists(within: 10)
        await stateShot(look, "W7 session not running")
        _ = try? await Self.post("\(five)/start")
        relaunch(eight, base)
        _ = element("workspace.w1").exists(within: connect)
        _ = try? await Self.call(eight, "workspace.close", ["workspace_id": "w1"])
        _ = element("detail.empty").exists(within: 5)
        await stateShot(look, "W9 S2 session with no workspaces")
        _ = try? await Self.post("\(eight)/stress", Data())
    }

    /// No herdr on This Mac (a login shell whose PATH and home have none), a herdr that never answers, and a machine
    /// that does not answer: Connecting for ssh's 10 s, then Reconnecting.
    private func herdrScenes(_ look: String, _ base: [String]) async {
        app.launchEnvironment["SHELL"] = "\(Self.fixtures)/no-herdr/login-shell"
        app.launchEnvironment["PATH"] = "/usr/bin:/bin"
        relaunch(one, base)
        _ = app.staticTexts["herdr is not installed"].exists(within: connect)
        await stateShot(look, "W3 herdr not installed")
        app.launchEnvironment["PATH"] = "\(Self.fixtures)/slow-herdr:/usr/bin:/bin"
        relaunch(one, base)
        _ = element("detail.connecting").exists(within: 5)
        await stateShot(look, "W1 connecting")
        app.launchEnvironment["SHELL"] = nil
        app.launchEnvironment["PATH"] = nil
        relaunch(one, base + ["-machine", "e2e-down"])
        _ = element("detail.connecting").exists(within: 5)
        await stateShot(look, "W2 connecting over SSH")
        _ = element("detail.reconnecting").exists(within: 20)
        await stateShot(look, "W8 reconnecting, machine unreachable")
    }

    /// A machine that asks: Disconnected with Connect, ssh's question, then no herdr there (CI's sshd).
    private func askingScenes(_ look: String, _ base: [String]) async throws {
        try await Self.post("\(one)/ssh-drop", Data("ovvi-pw".utf8))
        try await Self.post("\(one)/ssh-forget", Data("ovvi-pw".utf8))
        relaunch(one, base + ["-machine", "e2e-pw"])
        _ = element("detail.connect").exists(within: connect)
        await stateShot(look, "W5 disconnected")
        element("detail.connect").click()
        if element("ask.text").exists(within: connect) {
            await stateShot(look, "W2b ssh question")
            element("ask.ok").click()
        }
        let answer = element("ask.answer")
        if answer.exists(within: connect) {
            answer.click()
            app.typeText("ovvi-e2e-pw")
            app.typeKey(.return, modifierFlags: [])
        }
        _ = app.staticTexts["herdr is not installed on Password Host"].exists(within: connect)
        await stateShot(look, "W4 herdr not installed on a remote machine")
    }

    /// Settings: a search with no result.
    private func settingsScene(_ look: String, _ base: [String]) async {
        relaunch(one, base)
        _ = element("workspace.w2").exists(within: connect)
        app.typeKey(",", modifierFlags: .command)
        let settings = settingsWindow
        guard settings.exists(within: 5) else { return }
        app.typeKey("f", modifierFlags: .command)
        app.typeText("zzzzqq")
        try? await Task.sleep(for: .seconds(0.6))
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)).hover()
        keepScreenshot("\(look) X1 settings search, no result", of: settings)
        app.typeKey("w", modifierFlags: .command)
    }

    /// The main window, the pointer off it.
    private func stateShot(_ look: String, _ name: String) async {
        let main = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'")).firstMatch
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)).hover()
        try? await Task.sleep(for: .seconds(0.4))
        keepScreenshot("\(look) \(name)", of: main.exists ? main : nil)
    }

    /// The tests' fixtures folder.
    static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures").path
}
