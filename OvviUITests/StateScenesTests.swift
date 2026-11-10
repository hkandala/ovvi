import XCTest

extension OvviUITests {
    func testStateScenes() async throws {
        executionTimeAllowance = 900
        continueAfterFailure = true
        let ssh = try await hasSSH()
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

    private func sessionScenes(_ look: String, _ base: [String]) async throws {
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

    private func herdrScenes(_ look: String, _ base: [String]) async {
        app.launchEnvironment["SHELL"] = "\(Self.fixtures)/no-herdr/login-shell"
        app.launchEnvironment["PATH"] = "/usr/bin:/bin"
        relaunch(one, base + ["-herdrInstall", #"echo "  > downloading v0.9.5..."; sleep 30"#])
        _ = element("detail.install").exists(within: connect)
        await stateShot(look, "W3 herdr not installed")
        element("detail.install").click()
        _ = element("detail.installing").exists(within: 3)
        await stateShot(look, "W3b installing herdr")
        relaunch(one, base + ["-herdrInstall", #"echo "  > fetching latest release manifest..."; "#
                + #"echo "  x cannot reach https://herdr.dev/latest.json" >&2; exit 1"#])
        _ = element("detail.install").exists(within: connect)
        element("detail.install").click()
        _ = app.staticTexts["herdr did not install"].exists(within: 5)
        await stateShot(look, "W3c herdr install failed")
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

    private func settingsScene(_ look: String, _ base: [String]) async {
        relaunch(one, base)
        _ = element("workspace.w2").exists(within: connect)
        app.typeKey(",", modifierFlags: .command)
        let settings = settingsWindow
        guard settings.exists(within: 5) else { return }
        settings.searchFields.firstMatch.click()
        app.typeText("zzzzqq")
        try? await Task.sleep(for: .seconds(0.6))
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)).hover()
        keepScreenshot("\(look) X1 settings search, no result", of: settings)
        app.typeKey("w", modifierFlags: .command)
    }

    func testNewWindowScenes() async throws {
        let ssh = try await hasSSH()
        let host = #"[{"id":"e2e-pw","name":"Password Host","target":"ovvi-pw","icon":"cpu"}]"#
        for look in ["dark", "light"] {
            relaunch(one, ["-appearance", look, "-machines", ssh ? host : "[]"])
            _ = element("terminal.w1:p1").exists(within: connect)
            let first = app.windows.firstMatch.identifier
            app.typeKey("n", modifierFlags: .command)
            if let window = until(3, { app.windows.count > 1 }) ? app.windows.allElementsBoundByIndex
                .first(where: { $0.identifier != first }) : nil
            {
                keepScreenshot("\(look) N0 new window, first frames", of: window)
            }
            _ = element("picker.local.\(one)").exists(within: connect)
            if ssh {
                _ = element("picker.e2e-pw.+connect").exists(within: 20)
            }
            await newWindowShot(look, "N1 new window")
            app.typeText("ovvi-e2e-build")
            await newWindowShot(look, "N2 new window, a typed name")
            element("picker.+add-machine").click()
            try? await Task.sleep(for: .seconds(1))
            await newWindowShot(look, "N4 new window, Add Machine")
            app.launchEnvironment["SHELL"] = "\(Self.fixtures)/no-herdr/login-shell"
            app.launchEnvironment["PATH"] = "/usr/bin:/bin"
            // A fake installer: a stray Return on Install herdr must never run herdr.dev's.
            relaunch(one, ["-appearance", look, "-herdrInstall", "\(Self.fixtures)/no-herdr/install",
                           "-ApplePersistenceIgnoreState", "YES"], windows: .restored)
            _ = element("picker.local.+install").exists(within: connect)
            await newWindowShot(look, "N3 new window, no herdr")
            app.launchEnvironment["SHELL"] = nil
            app.launchEnvironment["PATH"] = nil
        }
    }

    func testEmptySessionScenes() async {
        for look in ["dark", "light"] {
            _ = try? await Self.post("\(eight)/stress", Data())
            relaunch(eight, ["-appearance", look])
            _ = element("workspace.w1").exists(within: connect)
            _ = try? await Self.call(eight, "workspace.close", ["workspace_id": "w1"])
            _ = element("detail.empty").exists(within: 5)
            try? await Task.sleep(for: .seconds(1))
            await stateShot(look, "E1 session with no spaces")
        }
        _ = try? await Self.post("\(eight)/stress", Data())
    }

    private func newWindowShot(_ look: String, _ name: String) async {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)).hover()
        try? await Task.sleep(for: .seconds(0.6))
        keepScreenshot("\(look) \(name)", of: window)
    }

    private func stateShot(_ look: String, _ name: String) async {
        let main = mainWindows.firstMatch
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)).hover()
        try? await Task.sleep(for: .seconds(0.4))
        keepScreenshot("\(look) \(name)", of: main.exists ? main : nil)
    }
}
