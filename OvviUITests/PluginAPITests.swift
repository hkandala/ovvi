import XCTest

extension OvviUITests {
    func testAPluginPageCallsEveryPartOfTheAPI() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("plugin-api")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-api-config", folder = "/tmp/ovvi-e2e-api", root = "/private/tmp/ovvi-e2e-api"
        try await writeConfig(config, folder: folder, shell: shell)
        keepClipboard()
        relaunch(one, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()

        let (cardTab, card) = try await newCard("ovvi:plugin-api#e2eapi \(root)/", cwd: folder)
        XCTAssertTrue(text("ready: yes").exists(within: 10))
        for line in ["state: 1", "card: 1 plugin-api This Mac \(root)/", "files.write: true", #"files.read: "hello\n""#,
                     "files.readBytes: 6", "files.info: 6 false true",
                     "files.changed: changed The file changed on disk",
                     "files.missing: notFound Not a file", #"run: 3 "\#(root)\nin\n""#,
                     "files.list: sub/ .gitignore a.txt ignored.txt!", "files.paths: .gitignore a.txt",
                     "git.root: \(root)", "git.status: U .gitignore, U a.txt", "git.changes: a.txt", "git.commit: one",
                     "git.head: main", "git.branches: main", "git.diff: true", "clipboard: written", "symbol: true",
                     "motion: on"]
        {
            XCTAssertTrue(text(line).exists, line)
        }
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "ovvi-plugin-api")
        let log = "\(config)/logs/plugins/plugin-api.log", line = "/ log: order /"
        let ordered = #"awk '\#(line) { if ($4 != ++n) { print "un" "ordered at " n; exit } } "#
            + #"END { print "calls-" n "-in-order-" 6*7 }' "# + log
        try await send("clear; for t in 1 2 3 4 5 6; do [ $(awk '\(line)' \(log) | wc -l) = 1000 ] && break; "
            + "sleep 0.5; done; \(ordered)\r", to: shell)
        try await waitFor(shell) { $0.contains("-in-order-42") }
        let order = try await read(shell)
        XCTAssertTrue(order.contains("calls-1000-in-order") && !order.contains("unordered"), order)
        keepScreenshot("plugin API fixture")

        let shown = count("visible: true ")
        try await send("echo x > \(folder)/watched.txt\r", to: shell)
        XCTAssertTrue(text("watch: 1").exists(within: 5))
        try await machineChecks(folder, shell: shell, tab: tab, cardTab: cardTab)
        XCTAssertTrue(text("watch.again: yes").exists(within: 5))
        XCTAssertTrue(text("visible: true \(shown + 2)").exists)

        try await cardCalls(card, in: cardTab, root: root)
        try await reloadsUnderAToast(card, in: cardTab, shell: shell)
        try await failingCard(root)

        relaunch(one, ["-configFolder", config, "-animations", "NO"])
        element("workspace.w2").click()
        try await show(cardTab)
        XCTAssertTrue(text("state: 3").exists(within: 10))
        XCTAssertTrue(text("motion: off").exists, "Animations off on the card's root")
        try await send("rm -rf \(config) \(folder) ~/.local/state/ovvi/\(one)/plugin-api\r", to: shell)
    }

    private func writeConfig(_ config: String, folder: String, shell: String) async throws {
        let fixture = "\(Self.fixtures)/plugin-api"
        try await send(
            "rm -rf \(config) \(folder) ~/.local/state/ovvi/\(one)/plugin-api && mkdir -p \(config) \(folder)/sub && "
                + "echo '{\"packages\":[\"\(fixture)\"]}' > \(config)/settings.json && "
                + "echo '[\"plugin-api\"]' > \(config)/trust.json && "
                + "clear && echo made-$((6*7))\r",
            to: shell,
        )
        try await waitFor(shell) { $0.contains("made-42") }
    }

    private func machineChecks(_ folder: String, shell: String, tab: String, cardTab: String) async throws {
        element("tab.\(tab)").click()
        try await send("clear; cat \(folder)/a.txt; git -C \(folder) log --format=%s; grep -c "
            + "'\"count\":\"counted\".*\"runs\":1' ~/.local/state/ovvi/\(one)/plugin-api/e2eapi.json; "
            + "echo done-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("four\none\n1\ndone-42") }
        try await show(cardTab)
    }

    private func cardCalls(_ card: String, in tab: String, root: String) async throws {
        let button = { (title: String) in self.element("plugin-api.\(card).page").buttons[title] }
        button("Toast").click()
        toastStopsAtItsWidest(card)
        element("pane.\(card).toast.main").click()
        XCTAssertTrue(text("toast: Yes").exists(within: 3))
        XCTAssertTrue(text("keyboard: true").exists)

        button("Menu").click()
        XCTAssertTrue(app.menuItems["Two"].exists(within: 3))
        app.menuItems["Two"].click()
        XCTAssertTrue(text("menu: two").exists(within: 3))

        button("Pick").click()
        XCTAssertTrue(app.sheets.buttons["Cancel"].exists(within: 5))
        app.sheets.buttons["Cancel"].click()
        XCTAssertTrue(text("pick: undefined").exists(within: 3))

        button("Dirty").click()
        XCTAssertTrue(element("pane.\(card).dirty").exists(within: 3))
        button("Clean").click()
        XCTAssertTrue(element("pane.\(card).dirty").vanishes(within: 3))

        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(text("save: heard").exists(within: 3))
        app.typeKey("y", modifierFlags: [.command, .shift])
        XCTAssertTrue(text("control: shout").exists(within: 3))
        element("pane.\(card).again").click()
        XCTAssertTrue(text("control: again").exists(within: 3))
        XCTAssertTrue(element("pane.\(card).count").has(\.stringValue, "counted", within: 1))

        button("Go").click()
        XCTAssertTrue(text("place: \(root)/sub/ x").exists(within: 3))
        try await expect("the label follows") { try await paneLabel(card).hasSuffix(" \(root)/sub/") }
        app.typeKey("-", modifierFlags: .control)
        XCTAssertTrue(text("place: \(root)/ x").exists(within: 3))
        try await expect("the label goes back") { try await paneLabel(card).hasSuffix(" \(root)/") }

        let before = try await tabIDs()
        closeNew("tab", besides: before)
        button("Open").click()
        let opened = try await newTabID(after: before)
        let pane = try await pane(of: opened)
        let label = try await paneLabel(pane)
        XCTAssertTrue(label.hasSuffix(" \(root)/a.txt"), label)

        try await show(tab)
        button("Clean").click()
        let tabs = try await tabIDs()
        app.typeKey("t", modifierFlags: .command)
        _ = try await newTabID(after: tabs)
        try await show(tab)
        XCTAssertFalse(text("control: taken").exists(within: 0.5))
    }

    /// A long toast in a wide card: the whole text, the capsule 520 pt and centered.
    private func toastStopsAtItsWidest(_ card: String) {
        let toast = element("pane.\(card).toast"), main = element("pane.\(card).toast.main")
        XCTAssertTrue(toast.exists(within: 3))
        XCTAssertTrue(toast.stringValue.hasSuffix("shows on hover."), toast.stringValue)
        // The capsule runs 14 pt before the text and 7 pt past the last button.
        let wide = element("plugin-api.\(card).page").frame, left = toast.frame.minX - 14, right = main.frame.maxX + 7
        XCTAssertGreaterThan(wide.width, 600)
        // A text cut with … can take a few points less than it was offered.
        XCTAssertLessThanOrEqual(right - left, 521, "a long toast stops at its widest")
        XCTAssertGreaterThan(right - left, 500)
        XCTAssertEqual(left - wide.minX, wide.maxX - right, accuracy: 1)
    }

    /// The new page has no toast: the old one's buttons would answer nobody.
    private func reloadsUnderAToast(_ card: String, in tab: String, shell: String) async throws {
        try await show(tab)
        element("plugin-api.\(card).page").buttons["Toast"].click()
        let toast = element("pane.\(card).toast")
        XCTAssertTrue(toast.exists(within: 3))
        try await run("\(Self.ovviCommand) plugins reload plugin-api", in: shell, "reload", 0, "built: true")
        XCTAssertTrue(text("state: 2").exists(within: 10))
        XCTAssertTrue(toast.vanishes(within: 3), toast.stringValue)
    }

    private func failingCard(_ root: String) async throws {
        let pane = try await newCard("ovvi:plugin-api#e2efal \(root)/fail/", cwd: root).pane
        XCTAssertTrue(element("pane.\(pane).failure").has(\.stringValue, "Plugin API stopped", within: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'asked to fail'")).firstMatch
            .exists)
        XCTAssertTrue(element("pane.\(pane).reload").exists)
    }

    private func count(_ prefix: String) -> Int {
        let text = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", prefix)).firstMatch
        return text.exists ? Int(text.stringValue.dropFirst(prefix.count)) ?? 0 : 0
    }
}
