import XCTest

extension OvviUITests {
    func testATabComesIntoViewWithoutAFlicker() async throws {
        executionTimeAllowance = 300
        relaunch(one, ["-recordFrames", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        _ = try await newTab("third", in: "w1")
        for pane in ["w1:p1", "w1:p2", "w1:p3", "w1:p4", "w2:p1"] {
            try await fill(pane)
        }
        try await fill("w1:p1", in: two)
        openPage(two)
        // Only the shown session's page is in the window: two's card draws now, or its first picture comes in a record.
        try await expectText(["w1:p1"], "warm-up")
        // Keys for the tabs: right after a session change a click can land beside the capsule (CI).
        for (act, panes) in [(key("1", [.command, .option]), ["w1:p1"]), (key("2"), ["w1:p4"]),
                             (click("workspace.w2"), ["w2:p1"]), (click("workspace.w1"), ["w1:p4"]),
                             (key("1"), ["w1:p1", "w1:p2", "w1:p3"])]
        {
            act()
            try await expectText(panes, "warm-up")
        }
        try await Task.sleep(for: .seconds(2))
        try await expectNoFlicker()
    }

    func testATabClickComesIntoViewWithoutAFlicker() async throws {
        relaunch(one, ["-recordFrames", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        for pane in ["w1:p1", "w1:p2", "w1:p3", "w1:p4"] {
            try await fill(pane)
        }
        element("tab.w1:t2").click()
        try await expectText(["w1:p4"], "warm-up")
        element("tab.w1:t1").click()
        try await expectText(["w1:p1", "w1:p2", "w1:p3"], "warm-up")
        try await Task.sleep(for: .seconds(2))
        let records = try await [frames("tab click", click("tab.w1:t2")), frames("tab click back", click("tab.w1:t1"))]
        XCTAssertTrue(records.allSatisfy { !$0.contains(#/ [1-9][0-9]*\//#) }, "\(records)")
    }

    func testACardNeverShowsTheOverviewsSmallSnapshot() async throws {
        relaunch(one, ["-recordFrames", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        var records: [String] = []
        for (name, byTile) in [("capsule after the overview", false), ("tile after the overview", true)] {
            // The second's capsule, w1's fourth, is out of the row's view beside CI's 300 pt sidebar: never hittable.
            let (tab, pane) = try await byTile ? createTab(in: "w1", label: name) : newTab(name, in: "w1")
            if byTile {
                closeAfter("tab", tab)
            }
            try await fill(pane)
            app.typeKey("o", modifierFlags: [.command, .control])
            let card = element("overview.card.\(pane)"), tile = element("overview.tab.\(tab)")
            XCTAssertTrue(until(5) { card.stringValue.hasPrefix("snapshot") }, "\(card.exists) '\(card.stringValue)'")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(element("overview").vanishes(within: 2))
            try await Task.sleep(for: .seconds(2))
            try await records.append(frames(name) {
                if byTile {
                    self.app.typeKey("o", modifierFlags: [.command, .control])
                    XCTAssertTrue(tile.has(\.isHittable, true, within: 3))
                    tile.click()
                } else {
                    self.element("tab.\(tab)").click()
                }
            })
            element("tab.w1:t1").click()
        }
        keep(records.joined(separator: "\n"), as: "frames")
        let blurred = records.filter { $0.split(separator: " ").last?.contains("s") == true }
        XCTAssertTrue(blurred.isEmpty, "\(blurred) of \(records)")
    }

    private func expectNoFlicker() async throws {
        var records: [String] = []
        let option: XCUIElement.KeyModifierFlags = [.command, .option]
        for (name, act) in [
            ("tab click", click("tab.w1:t2")), ("tab click back", click("tab.w1:t1")), ("tab key", key("2")),
            ("workspace", click("workspace.w2")), ("workspace back", click("workspace.w1")),
            ("session jump key", key("2", option)), ("session jump key back", key("1", option)),
            ("next session key", key("]", option)), ("previous session key", key("[", option)),
        ] {
            try await records.append(frames(name, act))
        }
        let sidebar = element("sidebar"), swipe = "\(one)/swipe", center = "\(sidebar.frame.midX) \(sidebar.frame.midY)"
        for (name, step) in [("session swipe", -10), ("session swipe back", 10)] {
            try await records.append(frames(name, swiped: true) {
                try await Self.post(swipe, Data("\(center) \(step) 14".utf8))
            })
        }
        XCTAssertTrue(records.suffix(2).contains { $0.contains("/") }, "no swipe changed the session: \(records)")
        showPage(one)
        try await Task.sleep(for: .seconds(2))
        try await records.append(frames("tab key back", key("1")))
        for name in ["overview tile of another tab", "overview tile of the shown tab"] {
            try await records.append(frames(name) {
                self.app.typeKey("o", modifierFlags: [.command, .control])
                let tile = self.element("overview.tab.w1:t2")
                XCTAssertTrue(tile.has(\.isHittable, true, within: 3))
                tile.click()
            })
        }
        for (name, tab) in [("tab after the sidebar hid", "1"), ("tab after the sidebar showed", "2")] {
            element("titlebar.sidebar").click()
            try await Task.sleep(for: .seconds(1))
            try await records.append(frames(name, key(tab)))
        }
        keep(records.joined(separator: "\n"), as: "frames")
        let flickers = records.filter { $0.contains(#/ [1-9][0-9]*\//#) }
        XCTAssertTrue(flickers.isEmpty, "\(flickers) of \(records)")
    }

    private func frames(_ name: String, swiped: Bool = false, _ act: () async throws -> Void) async throws -> String {
        let probe = element("app.frames"), before = probe.stringValue.split(separator: "; ").count
        try await act()
        // No accessibility query until the record is done: each one holds the app's main thread (up to 240 ms), which
        // moves the commits' timing.
        try await Task.sleep(for: .seconds(2))
        let new = probe.stringValue.split(separator: "; ").dropFirst(before)
        XCTAssertTrue(new.count == 1 || swiped && new.isEmpty, "\(name): \(new)")
        return "\(name): " + new.joined(separator: ", ")
    }

    private func click(_ id: String) -> () -> Void {
        { self.element(id).click() }
    }

    private func key(_ key: String, _ flags: XCUIElement.KeyModifierFlags = .command) -> () -> Void {
        { self.app.typeKey(key, modifierFlags: flags) }
    }
}
