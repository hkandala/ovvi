import XCTest

extension OvviUITests {
    /// Settings ▸ Appearance ▸ Animations, on by default. Off, a split and its close slide no card, the overview's tile
    /// zooms in no frame and a reorder moves the spaces in no motion; it stays off after a relaunch.
    func testAnimationsOffMakesTheMotionsInstant() async throws {
        // Not pinned: a pinned key would hide the switch's write.
        let args = ["-recordMotion", "YES", "-forceMotion", "YES"]
        relaunch(one, args, pin: false)
        addTeardownBlock { @MainActor [self] in
            openSettings("appearance")
            turn("settings.appearance.animations", true)
        }
        addTeardownBlock { [one] in
            _ = try? await Self.call(
                one,
                "workspace.move_block",
                ["workspace_ids": ["w1"], "before_workspace_id": "w2"],
            )
        }
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("animations")
        step("Animations on")
        try await motions(tab, pane, moving: true)

        step("Animations off")
        openSettings("appearance")
        turn("settings.appearance.animations", false)
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))
        try await motions(tab, pane, moving: false)

        step("Still off after a relaunch")
        relaunch(one, args, pin: false)
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openSettings("appearance")
        let toggle = element("settings.appearance.animations", in: settingsWindow)
        XCTAssertTrue(toggle.exists(within: 3))
        XCTAssertEqual(toggle.value as? Int, 0, "the switch after a relaunch")
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isHittable, true, within: 3))
        element("tab.\(tab)").click()
        try await motions(tab, pane, moving: false)
    }

    /// A split and its close, the overview's tile zoom, and a reorder of the spaces and back: each moves, or each
    /// lands at once.
    private func motions(_ tab: String, _ pane: String, moving: Bool) async throws {
        let card = element("motion.\(pane)"), zoom = element("overview.zoom"), moves = element("sidebar.moves")
        XCTAssertTrue(card.exists(within: 3))
        func moved(_ what: String, _ count: () -> Int, from start: Int) {
            if moving {
                XCTAssertTrue(until(3) { count() > start }, "\(what) moved")
            } else {
                // The change has landed: any motion would have started.
                XCTAssertFalse(until(1) { count() != start }, "\(what) moved: \(count() - start)")
            }
        }

        let slides = { Self.slides(card.label) }, slid = slides()
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeKey("d", modifierFlags: .command)
        let new = try await poll("the split") { try await order(tab).first { $0 != pane } }
        _ = try await Self.call(one, "pane.close", ["pane_id": new])
        try await expect("the close") { try await order(tab) == [pane] }
        XCTAssertTrue(element("pane.\(new)").vanishes(within: 3))
        moved("the split and its close", slides, from: slid)

        let steps = { Int(zoom.stringValue) ?? 0 }, zoomed = steps()
        app.typeKey("o", modifierFlags: [.command, .control])
        let tile = element("overview.tab.\(tab)")
        XCTAssertTrue(tile.has(\.isHittable, true, within: 3))
        tile.click()
        XCTAssertTrue(element("overview").vanishes(within: 2))
        moved("the overview's zoom", steps, from: zoomed)

        // The order's changes with a motion, and without.
        let counts = { moves.stringValue.split(separator: " ").compactMap { Int($0) } }, before = counts()
        XCTAssertEqual(before.count, 2, moves.stringValue)
        let alpha = element("workspace.w1"), beta = element("workspace.w2")
        alpha.rightClick()
        app.menuItems["Move Down"].click()
        XCTAssertTrue(until(3) { alpha.frame.minY > beta.frame.minY }, "Move Down")
        _ = try await Self.call(one, "workspace.move_block", ["workspace_ids": ["w1"], "before_workspace_id": "w2"])
        XCTAssertTrue(until(3) { alpha.frame.minY < beta.frame.minY }, "back up")
        XCTAssertTrue(until(3) { counts().reduce(0, +) >= before.reduce(0, +) + 2 }, moves.stringValue)
        moved("the spaces' reorder", { counts().first ?? 0 }, from: before.first ?? 0)
    }
}
