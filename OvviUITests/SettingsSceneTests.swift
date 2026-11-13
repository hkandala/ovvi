import XCTest

extension OvviUITests {
    func testSettingsScenes() async throws {
        // About 70 pictures.
        executionTimeAllowance = 900
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("settings scenes")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-settings-scenes"
        let quiet = #"{"version":"0.1.0","description":"A plugin with a long description that runs past one line "#
            + #"of the header on purpose.","ovvi":{"id":"ovvi-e2e-quiet","name":"Quiet Plugin With A Rather Long "#
            + #"Name","api":3,"entry":"main.js","icon":"moon"}}"#
        let card = try await shoutCard(config, shell: shell, extra: "echo '{\"hideInNewPane\":[\"codex\"]}' > "
            + "\(config)/settings.json && mkdir -p \(config)/plugins/ovvi-e2e-quiet && echo '\(quiet)' > "
            + "\(config)/plugins/ovvi-e2e-quiet/package.json && touch \(config)/plugins/ovvi-e2e-quiet/main.js")
        let machines = #"[{"id":"e2e-m1","name":"devbox","target":"ovvi-e2e@localhost","icon":"server.rack"},"#
            + #"{"id":"e2e-m2","name":"gpubox","target":"ovvi-e2e@127.0.0.1","icon":"cpu"},"#
            + #"{"id":"e2e-m3","name":"build-farm-us-east-1-primary-worker-07","#
            + #""target":"ci@build-farm-us-east-1-primary-worker-07.example.internal","icon":"cpu"}]"#
        for appearance in ["dark", "light"] {
            relaunch(one, ["-configFolder", config, "-appearance", appearance, "-machines", machines,
                           // Quoted: a bare value that starts with - is read as a flag.
                           "-agentArguments.claude", #""--model opus""#,
                           "-browserApprovals.local", #"("localhost:5173", "grafana.internal")"#,
                           "-browserApprovals.e2e-m1", #"("staging.acme.dev")"#])
            XCTAssertTrue(element("workspace.w2").exists(within: connect))
            element("workspace.w2").click()
            try await show(card.tab)
            XCTAssertTrue(element("pane.\(card.pane).trust").exists(within: 10))
            scene("\(appearance) 00 main window", app.windows.firstMatch)
            let tour = SettingsTour(test: self, look: appearance)
            tour.pages()
            tour.machines()
            tour.plugins()
            tour.search()
            app.typeKey("w", modifierFlags: .command)
        }
    }

    /// Settings ▸ Keyboard Shortcuts and the ⌘/ panel in both looks: the page, a search, recording, a conflict.
    func testKeyboardShortcutsScenes() {
        for appearance in ["dark", "light"] {
            relaunch(one, ["-appearance", appearance])
            XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
            app.typeKey("/", modifierFlags: .command)
            XCTAssertTrue(element("shortcuts").exists(within: 2))
            scene("\(appearance) 1 shortcuts panel",
                  app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'")).firstMatch)
            app.typeKey(.escape, modifierFlags: [])
            openSettings("keys")
            let window = settingsWindow, field = element("keys.tab.new", in: window)
            XCTAssertTrue(field.exists(within: 3))
            scene("\(appearance) 2 keys", window)
            field.click()
            scene("\(appearance) 3 keys recording", window)
            window.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(element("keys.tab.new.question", in: window).exists(within: 2))
            scene("\(appearance) 4 keys conflict", window)
            element("keys.tab.new", in: window).click()
            window.typeKey(.escape, modifierFlags: [])
            let search = element("keys.search", in: window)
            search.click()
            search.typeText("find")
            scene("\(appearance) 5 keys search", window)
            search.typeKey("a", modifierFlags: .command)
            search.typeKey(.delete, modifierFlags: [])
            window.scrollViews.allElementsBoundByIndex.last?.scroll(byDeltaX: 0, deltaY: -20000)
            scene("\(appearance) 6 keys plugins", window)
            window.typeKey("w", modifierFlags: .command)
        }
    }

    fileprivate func scene(_ name: String, _ window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)).hover()
        Thread.sleep(forTimeInterval: 0.4)
        // A closed menu is still there with an empty frame.
        let menus = app.menus.allElementsBoundByIndex.filter { $0.frame.width > 1 }
        for (shot, suffix) in [(window, "")] + menus.map({ ($0, " (menu)") }) {
            let attachment = XCTAttachment(screenshot: shot.screenshot())
            attachment.name = name + suffix
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

@MainActor
private final class SettingsTour {
    let test: OvviUITests, look: String, window: XCUIElement
    var count = 0

    init(test: OvviUITests, look: String) {
        self.test = test
        self.look = look
        window = test.settingsWindow
    }

    func shoot(_ name: String) {
        count += 1
        test.scene("\(look) \(String(format: "%02d", count)) \(name)", window)
    }

    func open(_ id: String, waitFor next: String? = nil) {
        test.element(id, in: window).click()
        if let next {
            XCTAssertTrue(test.element(next, in: window).exists(within: 5), next)
        }
    }

    func menu(_ id: String, _ name: String) {
        open(id)
        shoot(name)
        test.app.typeKey(.escape, modifierFlags: [])
    }

    func back() {
        window.buttons["Back"].firstMatch.click()
    }

    func bottom(_ name: String) {
        window.scrollViews.allElementsBoundByIndex.last?.scroll(byDeltaX: 0, deltaY: -2000)
        shoot(name)
    }

    func pages() {
        for page in ["general", "appearance", "terminal"] {
            test.openSettings(page)
            shoot(page)
        }
        menu("settings.terminal.font", "terminal font menu")
        menu("settings.terminal.option", "terminal option menu")
        test.openSettings("agents")
        shoot("agents")
        menu("settings.agents.view", "agents view menu")
        bottom("agents bottom")
        test.openSettings("privacy")
        shoot("privacy")
    }

    func machines() {
        test.openSettings("machines")
        shoot("machines")
        open("settings.machine.e2e-m1", waitFor: "settings.machine.name")
        shoot("machine devbox")
        open("settings.machine.clear")
        shoot("machine clear confirm")
        test.app.typeKey(.escape, modifierFlags: [])
        open("settings.machine.remove")
        shoot("machine remove confirm")
        test.app.typeKey(.escape, modifierFlags: [])
        back()
        open("settings.machine.e2e-m3", waitFor: "settings.machine.name")
        shoot("machine long name")
        back()
        open("settings.machine.local", waitFor: "settings.machine.clear")
        shoot("machine this mac")
        back()
        open("settings.machines.add", waitFor: "settings.machine.name")
        shoot("machine add empty")
        open("settings.machine.name")
        test.app.typeText("buildbox")
        open("settings.machine.target")
        test.app.typeText("me@buildbox.local")
        shoot("machine add filled")
        test.app.typeText(" box")
        shoot("machine add error")
        back()
    }

    func plugins() {
        test.openSettings("plugins")
        shoot("plugins")
        for plugin in ["browser", "explorer", "git"] {
            open("plugins.\(plugin)")
            shoot("plugin \(plugin)")
            bottom("plugin \(plugin) bottom")
            back()
        }
        open("plugins.ovvi-e2e-shout", waitFor: "plugins.ovvi-e2e-shout.setting.shout")
        shoot("plugin shout")
        back()
        open("plugins.ovvi-e2e-quiet", waitFor: "plugins.ovvi-e2e-quiet.remove")
        shoot("plugin no settings")
    }

    func search() {
        let search = window.searchFields.firstMatch
        search.click()
        search.typeText("cursor")
        XCTAssertTrue(test.element("settings.search.terminal.cursor", in: window).exists(within: 2))
        shoot("search found")
        search.typeKey("a", modifierFlags: .command)
        search.typeText("zzzz")
        shoot("search none")
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        test.openSettings("agents")
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: -1))
        edge.click(forDuration: 0.3, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: -140)))
        shoot("agents shorter")
    }
}
