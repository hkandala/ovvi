import XCTest

extension OvviUITests {
    func testSwitchesKeepHeavyCardsAsTheyWere() async throws {
        let (chatTab, pane) = try await startChat(["-recordLatency", "YES"])
        addTeardownBlock { @MainActor in self.keep(self.element("app.latency").stringValue, as: "latency") }
        app.typeText("many 12 30\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        let chat = element("chat.\(pane)"), earlier = element("chat.\(pane).earlier")
        let kinds = ["user", "reply", "stack", "worked"].map { "chat.\(pane).\($0)" }
        let rows = { try self.nodes(of: chat).count { kinds.contains($0.identifier) } }
        XCTAssertLessThanOrEqual(try rows(), 10)

        let tabs = try await heavyTabs()
        for (tab, kind) in zip(tabs, ["markdown", "git"]) {
            try await select(tab)
            let card = try await self.pane(of: tab)
            XCTAssertTrue(element("\(kind).\(card).page").exists(within: 30), tab)
        }
        try await select(chatTab)
        XCTAssertTrue(until(5) { last.exists && last.isHittable })

        // Every row: no more come later, which would change what the switches keep.
        let first = row(pane, "user", "many 12 30")
        for _ in 0 ..< 30 where !first.isHittable {
            chat.scroll(byDeltaX: 0, deltaY: 5000)
        }
        XCTAssertTrue(first.isHittable)
        XCTAssertFalse(earlier.exists)
        XCTAssertGreaterThan(try rows(), 10)
        let top = try XCTUnwrap(steady(3) {
            let seen = atTop(of: chat, pane)
            return seen.isEmpty ? nil : seen
        })
        let built = try rows()

        for tab in tabs + [chatTab] {
            element("tab.\(tab)").click()
            XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3), tab)
        }
        element("workspace.w1").click()
        XCTAssertTrue(last.vanishes(within: 3))
        element("workspace.w2").click()
        let same = {
            XCTAssertTrue(until(3) { last.exists })
            XCTAssertEqual(try rows(), built)
            XCTAssertEqual(self.atTop(of: chat, pane), top)
        }
        try same()
        XCTAssertTrue(element("chat.\(pane).bottom").exists)
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").exists(within: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 5))
        try same()

        try await replyBoxLetsGo(pane, in: chatTab)
        try await scrolls(tabs[0])
    }

    private func replyBoxLetsGo(_ pane: String, in chatTab: String) async throws {
        let (floatTab, floated) = try await createTab(in: "w2", label: "float")
        closeAfter("tab", floatTab)
        try await select(floatTab)
        XCTAssertTrue(element("terminal.\(floated)").exists(within: 3))
        _ = float(floated)
        element("workspace.w2").click()
        try await select(chatTab)
        let composer = element("chat.\(pane).composer")
        composer.click()
        XCTAssertTrue(hasKeyboard(composer))
        try await select(floatTab)
        XCTAssertTrue(element("pane.\(floated).show").exists(within: 3))
        app.typeText("blur")
        try await select(chatTab)
        XCTAssertTrue(composer.exists(within: 3))
        XCTAssertFalse(composer.stringValue.contains("blur"), composer.stringValue)
    }

    private func select(_ tab: String) async throws {
        let tabs = try await (Self.call(one, "tab.list", ["workspace_id": "w2"])["tabs"] as? [[String: Any]] ?? [])
            .compactMap { $0["tab_id"] as? String }
        let index = try XCTUnwrap(tabs.firstIndex(of: tab))
        XCTAssertTrue(element("tabs.count").has(\.stringValue, "\(tabs.count)", within: 5))
        app.typeKey("\(index + 1)", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3), tab)
    }

    private func scrolls(_ tab: String) async throws {
        try await select(tab)
        let markdown = try await element("markdown.\(pane(of: tab)).page")
        let heading = markdown.staticTexts.matching(NSPredicate(format: "value == 'Part 1'")).firstMatch
        XCTAssertTrue(until(5) { heading.exists && heading.frame.minY >= markdown.frame.minY })
        markdown.scroll(byDeltaX: 0, deltaY: -2000)
        // Above the card, or gone: WebKit leaves text far out of view out of the tree.
        XCTAssertTrue(until(3) { !heading.exists || heading.frame.maxY < markdown.frame.minY })
    }

    func heavyTabs() async throws -> [String] {
        let folder = "/tmp/ovvi-e2e-switch"
        let markdown = "for i in $(seq 1000); do printf '## Part %s\\n\\nSome *text*, `code` and "
            + "[a link](https://ovvi.dev).\\n\\n' $i; done >big.md"
        let repo = "mkdir repo && cd repo && git init -q && for i in $(seq 40); do seq 300 >f$i.txt; done && "
            + "git add -A && git -c user.name=e2e -c user.email=e2e@ovvi.dev commit -qm one && "
            + "for i in $(seq 40); do seq 0 3 600 >f$i.txt; done"
        // A shell of its own, typed into, not a fixture pane the next test reads. In w1: one more tab in w2's bar
        // would push a capsule out of view on CI's narrow screen.
        let (scratch, shell) = try await createTab(in: "w1", label: "switch")
        closeAfter("tab", scratch)
        try await waitForPrompt(shell)
        sendAfter("rm -rf \(folder)\r", to: shell)
        try await send("(rm -rf \(folder) && mkdir \(folder) && cd \(folder) && \(markdown) && \(repo)); clear; "
            + "echo made-$((1+1))\r", to: shell)
        try await waitFor(shell, times: 100) { $0.contains("made-2") }
        var tabs: [String] = []
        for (kind, arg) in [("explorer", "\(folder)/big.md"), ("git", "\(folder)/repo/ uncommitted")] {
            let root: [String: Any] = ["type": "pane", "cwd": folder, "label": "ovvi:\(kind)#e2esw\(tabs.count) \(arg)",
                                       "command": ["sh", "-c", "cat", "sh"]]
            let layout = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": root])
            try tabs.append(field((layout["layout"] as? [String: Any])?["tab_id"], "tab"))
        }
        return tabs
    }
}
