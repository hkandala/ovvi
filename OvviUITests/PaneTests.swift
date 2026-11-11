import XCTest

extension OvviUITests {
    func testDividersDragDoubleClickAndBalance() async throws {
        let (tab, first) = try await newTab("dividers")
        // herdr halves the pane it splits: 50 / 25 / 25.
        let second = try await split(first), third = try await split(second)
        element("tab.\(tab)").click()
        let divider = element("divider.\(tab).root")
        XCTAssertTrue(element("divider.\(tab).1").exists(within: 3))

        // ⌥⌘= through its menu item: a global hotkey on this Mac takes the key ahead of the app.
        pick("Pane", "Balance Splits")
        try await expectWidths(tab, [first: 1 / 3, second: 1 / 3, third: 1 / 3])
        XCTAssertTrue(divider.has(\.stringValue, "33%", within: 3), divider.stringValue)

        let total = element("page.\(tab)").frame.width - 3 * 8
        let center = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.hover()
        keepScreenshot("three panes, grip")
        center.click(forDuration: 0.2, thenDragTo: center.withOffset(CGVector(dx: total * 0.15, dy: 0)))
        try await expectRatio(tab, 1 / 3 + 0.15)

        divider.doubleClick()
        try await expectRatio(tab, 0.5)
        XCTAssertTrue(divider.has(\.stringValue, "50%", within: 3), divider.stringValue)
    }

    func testSplitRightTwiceGivesThirds() async throws {
        step("The split button adds a pane right of its card")
        let (tab, pane) = try await newTab("thirds")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("page.\(tab)").has(\.isHittable, true, within: 3))
        let cards = element("page.\(tab)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()
        try await expect("2 panes in herdr") { try await order(tab).count == 2 }
        XCTAssertTrue(cards.element(boundBy: 1).exists(within: 2))
        XCTAssertLessThan(cards.element(boundBy: 0).frame.maxX, cards.element(boundBy: 1).frame.minX)
        keepScreenshot("split")

        step("A second split of the same card gives thirds")
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()
        try await expect("3 panes in herdr") { try await order(tab).count == 3 }
        let panes = try await order(tab)
        try await expectWidths(tab, Dictionary(uniqueKeysWithValues: panes.map { ($0, 1.0 / 3) }))
        for pane in panes {
            try await expect("terminal \(pane) fits its card") {
                abs(element("terminal.\(pane)").frame.width - (element("pane.\(pane)").frame.width - 2 * 10)) <= 2
            }
        }
    }

    func testKeysMoveTheKeyboardSwapAndResize() async throws {
        let (tab, first) = try await newTab("keys")
        let second = try await split(first)
        restoreHerdrFocusAfter()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))

        app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))

        app.typeKey(.rightArrow, modifierFlags: [.command, .control])
        pick("Pane", "Resize Pane Right")
        try await expectRatio(tab, 0.55)

        // ⌥⇧⌘→ through its menu item: global hotkeys of other apps take ⌥⇧ chords.
        pick("Pane", "Move Pane Right")
        try await expect("the two swapped") { try await order(tab) == [second, first] }
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))

        pick("Pane", "Focus Follows Mouse")
        addTeardownBlock { @MainActor in self.pick("Pane", "Focus Follows Mouse") }
        hoverHeader(second)
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
        // Still the keyboard's card while the rename in the other card has the keys.
        paneMenu(first, "Rename Pane…")
        XCTAssertTrue(hasKeyboard("pane.\(first).rename"))
        hoverHeader(second)
        let rename = element("pane.\(first).rename")
        // Focus Follows Mouse moves the keyboard 150 ms after the pointer rests.
        XCTAssertFalse(until(0.5) { !NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: rename) })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
    }

    func testClosingAPaneGivesTheKeyboardToThePaneUsedBefore() async throws {
        let (tab, first) = try await newTab("used-panes")
        let second = try await split(first), third = try await split(second), fourth = try await split(third)
        element("tab.\(tab)").click()
        try await settle([tab])
        for pane in [second, fourth, first] {
            element("terminal.\(pane)").click()
            XCTAssertTrue(hasKeyboard("terminal.\(pane)"), pane)
        }
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(first)").vanishes(within: 3))
        XCTAssertTrue(hasKeyboard("terminal.\(fourth)"))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(fourth)").vanishes(within: 3))
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
    }

    func testSplitsGiveTheNewPaneTheKeyboardAndKeysFollowTheTree() async throws {
        let (tab, first) = try await newTab("split-keys")
        element("tab.\(tab)").click()
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))
        app.typeKey("d", modifierFlags: .command)
        let second = try await poll("a pane right of the first") { try await order(tab).last { $0 != first } }
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
        hoverHeader(first)
        element("pane.\(first).split-down").click()
        let third = try await poll("a pane below the first") { () async throws -> String? in
            let panes = try await order(tab)
            return panes.count == 3 ? panes[1] : nil
        }
        let tree = try await order(tab)
        XCTAssertEqual(tree, [first, third, second])
        XCTAssertTrue(hasKeyboard("terminal.\(third)"))
        for (key, pane) in [("]", second), ("]", first), ("[", second), ("[", third)] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(hasKeyboard("terminal.\(pane)"), "⌘\(key) to \(pane)")
        }

        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.\(first)").vanishes(within: 2))
        XCTAssertEqual(element("pane.\(third).zoom").label, "Restore Pane ⇧⌘↩")
        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.\(first)").exists(within: 2))
    }

    func testQuickSplitsSplitTheNewestAndItKeepsTheKeyboard() async throws {
        step("Quick splits split the newest pane, and it keeps the keyboard")
        relaunch(one, ["-recordMotion", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let (tab, first) = try await newTab("quick-splits")
        element("tab.\(tab)").click()
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))
        let cards = element("cards.\(tab)")
        XCTAssertTrue(cards.exists(within: 2))
        let before = cards.stringValue.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(before.count, 2, cards.stringValue)
        func counts(came: Int, went: Int) -> String {
            "\(before[0] + came) \(before[1] + went)"
        }
        for _ in 0 ..< 3 {
            app.typeKey("d", modifierFlags: .command)
        }
        let panes = try await poll("four panes") { () async throws -> [String]? in
            let panes = try await order(tab)
            return panes.count == 4 ? panes : nil
        }
        XCTAssertEqual(panes.first, first)
        var node = try await root(tab)
        for pane in panes.dropLast() {
            XCTAssertEqual((node["first"] as? [String: Any])?["pane_id"] as? String, pane, "herdr's tree: \(node)")
            node = node["second"] as? [String: Any] ?? [:]
        }
        XCTAssertTrue(hasKeyboard("terminal.\(panes[3])"))
        XCTAssertTrue(cards.has(\.stringValue, counts(came: 3, went: 0), within: 2), "came went: \(cards.stringValue)")
        pickTerminal(panes[3])
        try await typeAndRead(panes[3])
        for (closed, next) in [(panes[3], panes[2]), (panes[2], panes[1])] {
            app.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(element("pane.\(closed)").vanishes(within: 3))
            XCTAssertTrue(hasKeyboard("terminal.\(next)"), "after closing \(closed)")
        }
        XCTAssertTrue(cards.has(\.stringValue, counts(came: 3, went: 2), within: 2), "came went: \(cards.stringValue)")
        try await expectQuickCloses()
    }

    private func expectQuickCloses() async throws {
        step("Closes right after quick splits, and the active border")
        let (burst, alone) = try await newTab("quick-close")
        element("tab.\(burst)").click()
        element("terminal.\(alone)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(alone)"))
        XCTAssertTrue(element("pane.\(alone)").exists)
        XCTAssertFalse(element("pane.\(alone).border").exists)
        let burstCards = element("cards.\(burst)")
        XCTAssertTrue(burstCards.exists(within: 2))
        let start = burstCards.stringValue.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(start.count, 2, burstCards.stringValue)
        for key in ["d", "d", "d", "w", "w", "w", "d"] {
            app.typeKey(key, modifierFlags: .command)
        }
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let left = try await poll("a new last pane with the keyboard") { () async throws -> [String]? in
            let panes = try await order(burst), last = element("terminal.\(panes.last ?? "")")
            return panes.count > 1 && last.exists && focused.evaluate(with: last) ? panes : nil
        }
        XCTAssertEqual(left.count, 2, "herdr's tree: \(left)")
        XCTAssertEqual(left.first, alone)
        let total = "\(start[0] + 4) \(start[1] + 3)"
        XCTAssertTrue(burstCards.has(\.stringValue, total, within: 2), "came went: \(burstCards.stringValue)")
        XCTAssertTrue(element("pane.\(left[1]).border").exists)
        element("terminal.\(alone)").click()
        XCTAssertTrue(element("pane.\(alone).border").exists(within: 1))
        XCTAssertFalse(element("pane.\(left[1]).border").exists)
        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.\(alone).border").vanishes(within: 2))
    }

    func testSelectPaneKeysPickTheLastUsedElseTheTopNeighbor() async throws {
        let (tab, first) = try await newTab("arrows")
        let second = try await split(first)
        var rows = try await [split(second)]
        for _ in 0 ..< 3 {
            try await rows.append(split(rows[rows.count - 1], "down"))
        }
        element("tab.\(tab)").click()
        pick("Pane", "Balance Splits")
        try await expectWidths(tab, Dictionary(uniqueKeysWithValues: ([first, second] + rows).map { ($0, 1.0 / 3) }))
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))
        let steps: [(XCUIKeyboardKey, String)] = [
            (.rightArrow, second), (.rightArrow, rows[0]), (.downArrow, rows[1]), (.downArrow, rows[2]),
            (.leftArrow, second), (.rightArrow, rows[2]),
            (.leftArrow, second), (.leftArrow, first), (.leftArrow, first), (.upArrow, first),
        ]
        for (index, (key, pane)) in steps.enumerated() {
            app.typeKey(key, modifierFlags: [.command, .option])
            XCTAssertTrue(hasKeyboard("terminal.\(pane)"), "step \(index) to \(pane)")
        }
    }

    func testContextMenuSplitsLeftRenamesAndMovesToNewTab() async throws {
        let (tab, pane) = try await newTab("menu")
        restoreHerdrFocusAfter()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(pane)").exists(within: 3))

        paneMenu(pane, "Split Left", screenshot: "context menu")
        try await expect("a new pane left of the first") {
            let panes = try await order(tab)
            return panes.count == 2 && panes.last == pane
        }

        paneMenu(pane, "Rename Pane…")
        let field = element("pane.\(pane).rename")
        XCTAssertTrue(hasKeyboard(field))
        field.typeText("renamed\r")
        try await expect("herdr's label") { try await paneLabel(pane) == "renamed" }
        XCTAssertTrue(element("pane.\(pane)").has(\.label, "renamed", within: 2))
        paneMenu(pane, "Reset Pane Name")
        try await expect("no label") { try await paneLabel(pane).isEmpty }
        XCTAssertTrue(until(2) { element("pane.\(pane)").label != "renamed" })

        // A tab after it: herdr adds the new tab last, and the app moves it right after the pane's tab.
        let (spare, _) = try await createTab(in: "w2")
        closeAfter("tab", spare)
        XCTAssertTrue(element("tab.\(spare)").exists(within: 5))
        let before = try await tabIDs()
        paneMenu(pane, "Move Pane to Tab", "New Tab")
        let moved = try await newTabID(after: before)
        closeAfter("tab", moved)
        try await expect("the pane in the new tab") { try await order(moved) == [pane] }
        XCTAssertTrue(element("tab.\(moved)").has(\.isSelected, true, within: 3))
        try await expectBeside(moved, tab)

        let terminal = try await terminalID(pane)
        let workspaces = try await workspaceIDs()
        closeNew("workspace", besides: workspaces)
        paneMenu(pane, "Move Pane to Tab", "New Space")
        let away = try await poll("the pane in a new workspace") { () async throws -> String? in
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
            return panes.first { $0["terminal_id"] as? String == terminal && $0["pane_id"] as? String != pane }?[
                "pane_id",
            ] as? String
        }
        XCTAssertTrue(hasKeyboard("terminal.\(away)"))
    }

    func testZoomIsDisabledAloneAndAZoomedCardShowsRestoreAndClose() async throws {
        let (tab, first) = try await newTab("zoom")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        hoverHeader(first)
        XCTAssertTrue(element("pane.\(first).zoom").exists(within: 2))
        XCTAssertFalse(element("pane.\(first).zoom").isEnabled)

        let second = try await split(first)
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))
        hoverHeader(first)
        XCTAssertTrue(element("pane.\(first).zoom").has(\.isEnabled, true, within: 2))
        element("pane.\(first).zoom").click()
        XCTAssertTrue(element("pane.\(second)").vanishes(within: 2))
        XCTAssertEqual(element("pane.\(first).zoom").label, "Restore Pane ⇧⌘↩")
        XCTAssertTrue(element("pane.\(first).close").exists)
        XCTAssertFalse(element("pane.\(first).split-right").exists)
        XCTAssertFalse(element("pane.\(first).split-down").exists)
        keepScreenshot("zoomed card")

        try await Self.call(one, "pane.close", ["pane_id": second])
        XCTAssertTrue(element("pane.\(first).split-right").exists(within: 3))
        XCTAssertEqual(element("pane.\(first).zoom").label, "Zoom Pane ⇧⌘↩")
        XCTAssertFalse(element("pane.\(first).zoom").isEnabled)
    }
}

extension OvviUITests {
    func paneMenu(_ pane: String, _ item: String, _ subitem: String? = nil, screenshot: String? = nil) {
        element("pane.\(pane)").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 60, dy: 18))
            .rightClick()
        // In the window, not the menu bar's View ▸ Pane, which has the same titles.
        let entry = app.windows.firstMatch.menuItems[item]
        XCTAssertTrue(entry.exists(within: 2))
        if let screenshot {
            keepScreenshot(screenshot)
        }
        entry.click()
        if let subitem {
            let sub = entry.menuItems[subitem]
            XCTAssertTrue(sub.exists(within: 2))
            sub.click()
        }
    }

    /// `pane.swap` moves herdr's focus to the swapped pane (herdr 0.9.5 ignores `focus:false` there), and the app
    /// opens on herdr's focused workspace and tab. After the test, a swap of w1:p1 with w1:p2 and back puts the
    /// focus on w1:t1 and w1:p1 again, where the other tests expect it, without a focus call.
    func restoreHerdrFocusAfter() {
        addTeardownBlock { [one] in
            for _ in 0 ..< 2 {
                try await Self.call(one, "pane.swap", ["source_pane_id": "w1:p1", "target_pane_id": "w1:p2"])
            }
        }
    }

    func root(_ tab: String) async throws -> [String: Any] {
        let layout = try await Self.call(one, "layout.export", ["tab_id": tab])["layout"] as? [String: Any]
        return try field(layout?["root"], "\(tab)'s layout")
    }

    func order(_ tab: String) async throws -> [String] {
        func leaves(_ node: [String: Any]) -> [String] {
            if let id = node["pane_id"] as? String {
                return [id]
            }
            return ["first", "second"].flatMap { leaves(node[$0] as? [String: Any] ?? [:]) }
        }
        return try await leaves(root(tab))
    }

    func expectWidths(_ tab: String, _ widths: [String: Double]) async throws {
        func shares(_ node: [String: Any], _ share: Double) -> [String: Double] {
            if let id = node["pane_id"] as? String {
                return [id: share]
            }
            let ratio = node["ratio"] as? Double ?? 0, right = node["direction"] as? String == "right"
            let first = shares(node["first"] as? [String: Any] ?? [:], right ? share * ratio : share)
            return first.merging(shares(node["second"] as? [String: Any] ?? [:], right ? share * (1 - ratio) : share)) {
                $1
            }
        }
        try await expect("widths \(widths)") {
            let found = try await shares(root(tab), 1)
            return found.count == widths.count && widths.allSatisfy { abs((found[$0.key] ?? -1) - $0.value) <= 0.02 }
        }
    }

    func expectRatio(_ tab: String, _ ratio: Double) async throws {
        try await expect("ratio \(ratio)") { try await abs((root(tab)["ratio"] as? Double ?? -1) - ratio) <= 0.02 }
    }
}
