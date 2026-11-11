import XCTest

extension OvviUITests {
    func testPanelsAndSwitchesReactAtOnce() async throws {
        try launchRecordingLatency(["-forceMotion", "YES"])
        openPage(two)
        showPage(one)
        XCTAssertTrue(until(3) { header == one })
        let palette = element("palette.filter"), openSession = element("open-session.filter")
        let escape = XCUIKeyboardKey.escape.rawValue
        key("k", .command) { palette.exists }
        key(escape, []) { !palette.exists }
        key("k", .command) { palette.exists }
        key("s", []) { palette.value as? String == "s" }
        key(XCUIKeyboardKey.delete.rawValue, []) { self.element("palette.section.Tabs").exists }
        key(escape, []) { !palette.exists }
        key("t", [.command, .option]) { openSession.exists }
        let first = element("app.latency").stringValue.split(separator: "; ").last { $0.hasPrefix("open-session") }
        XCTAssertTrue(first?.split(separator: " ").last?.split(separator: ",").contains { $0 == two } == true,
                      "\(first ?? "none")")
        key(escape, []) { !openSession.exists }
        key("2", .command) { self.element("tab.w1:t2").isSelected }
        key("1", .command) { self.element("tab.w1:t1").isSelected }
        key("]", [.command, .control]) { self.element("workspace.w2").isSelected }
        key("[", [.command, .control]) { self.element("workspace.w1").isSelected }
        key("]", [.command, .option]) { self.header == self.two }
        key("[", [.command, .option]) { self.header == self.one }
        // Half a page: XCUITest's scroll is a sideways wheel's, which turns a page.
        let sidebar = element("sidebar"), name = element("sidebar.header")
        try await swipe(sidebar, by: sidebar.frame.width / 2, until: name, \.stringValue, two)
        try await Task.sleep(for: .seconds(1))
        try await swipe(sidebar, by: sidebar.frame.width / 2, until: name, \.stringValue, one)
        try await Task.sleep(for: .seconds(1))
        // A typed filter's rows made once or twice, not again for each height the lazy list guessed (21 times for
        // the first letter here).
        let typed = recorded().filter { ["S", "\u{7F}"].contains($0.name) }
        XCTAssertEqual(typed.map(\.name), ["S", "\u{7F}"])
        for entry in typed {
            XCTAssertEqual(entry.turns, 0, entry.name)
            XCTAssertLessThanOrEqual(entry.lists, 3, entry.name)
        }
        let keys = recorded().filter { ["⌘", "⌃", "⇧", "⌥"].contains($0.name.first.map(String.init)) }
        XCTAssertEqual(keys.map(\.name), ["⌥⌘1", "⌘K", "⌘K", "⌥⌘T", "⌘2", "⌘1", "⌃⌘]", "⌃⌘[", "⌥⌘]", "⌥⌘["])
        for entry in keys {
            XCTAssertEqual(entry.turns, 0, entry.name)
        }
    }

    func testNewTabSplitAndClosesShowAtOnce() async throws {
        step("A new tab, a split and closes show at once")
        try launchRecordingLatency()
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.' AND selected == true"))
            .firstMatch
        key("t", .command) { selected.label == "New Tab" && !self.element("tab.w1:t1").isSelected }
        app.typeKey(.return, modifierFlags: [])
        var titles: [String] = []
        XCTAssertTrue(until(5) {
            titles.append(selected.label)
            return !["", "New Tab"].contains(titles.last)
        })
        XCTAssertFalse(titles.contains { !$0.isEmpty && $0.allSatisfy(\.isNumber) }, "\(titles)")
        let made = try await newTabID(after: before)
        XCTAssertTrue(element("tab.\(made)").has(\.isSelected, true, within: 3))
        try await settle([made])
        let cards = element("page.\(made)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        key("d", .command) { cards.count == 2 }
        try await settle([made])
        // The new pane (it has the keyboard) is asked for its program a second late: until its first answer a close
        // waits for herdr's.
        try await Task.sleep(for: .seconds(2.5))
        key("w", .command) { cards.count == 1 }
        key("w", [.command, .shift]) { !self.element("tab.\(made)").exists }
        let keys = recorded().filter { ["⌘", "⇧"].contains($0.name.first.map(String.init)) }
        XCTAssertEqual(keys.map(\.name), ["⌘T", "⌘D", "⌘W", "⇧⌘W"])
        // In the key's turn, or the next one (the action's task): herdr's answer takes 10 or more.
        for entry in keys {
            XCTAssertLessThanOrEqual(entry.turns, 1, entry.name)
        }
        try await expect("herdr closed the tab") { try await !tabIDs().contains(made) }
        XCTAssertFalse(element("tab.\(made)").exists)
        try await expectQuickNewTabsAndAnEarlyClose(besides: before)
    }

    private func expectQuickNewTabsAndAnEarlyClose(besides before: [String]) async throws {
        step("Quick new tabs, and a close right after a new tab")
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("t", modifierFlags: .command)
        let quick = try await poll("two new tabs") { () async throws -> [String]? in
            let new = try await tabIDs().filter { !before.contains($0) }
            return new.count == 2 ? new : nil
        }
        XCTAssertTrue(element("tab.\(quick[1])").has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("tab.\(quick[0])").exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.new.'")).count, 0)

        let now = try await tabIDs()
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("w", modifierFlags: [.command, .shift])
        // Read after a second, once herdr made it: until then its tabs match the first read too.
        try await Task.sleep(for: .seconds(1))
        try await expect("the early-closed tab made and closed") {
            let tabs = try await tabIDs()
            return tabs.count == now.count && tabs.contains(quick[1])
        }
        XCTAssertTrue(element("tab.\(quick[1])").has(\.isSelected, true, within: 3))
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    /// A trackpad's events at a known speed (`scripts/swipe.swift`): XCUITest's scroll is one flick.
    func testSessionSwipeFollowsTheFingersAndSlidesOnFromTheirSpeed() async throws {
        step("A session swipe follows the fingers and slides on from their speed")
        try launchRecordingLatency(["-forceMotion", "YES"])
        openPage(two)
        showPage(one)
        XCTAssertTrue(until(3) { header == one })
        let sidebar = element("sidebar"), width = sidebar.frame.width
        let center = "\(sidebar.frame.midX) \(sidebar.frame.midY)"
        // The other way if natural scrolling is off. Past half a page: a lift CI posts over 100 ms late counts as a
        // rest.
        let moves = Int(width / 20) + 1
        var forward = -1.0
        for sign in [-1.0, 1.0] {
            forward = sign
            try await Self.post("\(one)/swipe", Data("\(center) \(10 * sign) \(moves)".utf8))
            // No accessibility query during the slide: XCUITest's snapshots take the main thread (a 240 ms stall).
            try await Task.sleep(for: .seconds(1))
            if header == two {
                break
            }
        }
        XCTAssertEqual(header, two)
        let (swipe, path, shown) = try XCTUnwrap(swipes().last, "no swipe moved")
        let speed = 10 / 0.016
        let times = path.map { $0[0] }, offsets = path.map { $0[1] }
        // Give or take the system's own pace.
        XCTAssertEqual(offsets[0], Double(10 * moves), accuracy: 40, "\(swipe)")
        let target = offsets.last ?? 0
        XCTAssertEqual(target, width - 8, accuracy: 2, "\(swipe)")
        XCTAssertTrue(zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, "\(swipe)")
        // Within 2 pt of the page: 0.14 s from rest takes about 0.13 s; the 0.2 s spring from the fingers' speed 0.17
        // to 0.19 s here, the system's snap 0.33 s.
        let settled = path.first { abs($0[1] - width + 8) <= 2 }?[0] ?? 0
        XCTAssertGreaterThan(settled, 150, "\(swipe)")
        XCTAssertLessThan(settled, 400, "\(swipe)")
        XCTAssertGreaterThan(shown, 0, "\(swipe)")
        XCTAssertLessThan(beforeShow(path) - settled, 120, "\(swipe)")
        // A debug build under XCUITest drops a few frames at the start (about 50 ms).
        let steps = times.filter { $0 <= settled }
        XCTAssertLessThan(zip(steps, steps.dropFirst()).map { $1 - $0 }.max() ?? 1000, 100, "\(swipe)")
        let early = path.last { $0[0] <= 60 } ?? path[0]
        XCTAssertGreaterThan((early[1] - offsets[0]) / max(early[0], 1) * 1000, speed / 2, "\(swipe)")
        XCTAssertLessThan((early[1] - offsets[0]) / max(early[0], 1) * 1000, speed * 3, "\(swipe)")

        let name = element("sidebar.header"), place = name.frame.minX
        try await Self.post("\(one)/swipe", Data("\(center) \(-10 * forward) 4 200".utf8))
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(header, two)
        XCTAssertEqual(name.frame.minX, place, accuracy: 1)

        // The spring from rest is logically complete still about 1.4 % of its way short (1.3–1.6 pt). The session shows
        // only once the pages are on their place: its 100 ms of main thread would hold them short, then they jump.
        try await Self.post("\(one)/swipe", Data("\(center) \(-2 * forward) \(Int(width / 4) + 5) 200".utf8))
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(header, one)
        let (slow, slowPath, slowShown) = try XCTUnwrap(swipes().last, "no swipe moved")
        XCTAssertGreaterThan(slowShown, 0, slow)
        XCTAssertEqual(slowPath.last?[1] ?? -1, 0, accuracy: 0.5, slow)
        try await expectAFlickLandsInStep(center, forward)
    }

    /// From page one at rest, the way the swipe went forward.
    private func expectAFlickLandsInStep(_ center: String, _ forward: Double) async throws {
        step("A quick flick lands on the next page in step")
        let width = element("sidebar").frame.width, name = element("sidebar.header")
        // At rest: the pages arrive 0.2 s after the click (read mid-slide, 1 pt short, on CI).
        let rest = try XCTUnwrap(steady(3) { name.frame.minX })
        try await Self.post("\(one)/swipe", Data("\(center) \(20 * forward) 3".utf8))
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(header, two)
        XCTAssertEqual(name.frame.minX, rest, accuracy: 1)
        let (flick, flickPath, _) = try XCTUnwrap(swipes().last, "no swipe moved")
        XCTAssertEqual(flickPath.last?[1] ?? 0, width - 8, accuracy: 2, "\(flick)")
        let landed = flickPath.first { abs($0[1] - width + 8) <= 2 }?[0] ?? 1000
        XCTAssertLessThan(landed, 400, "\(flick)")
        XCTAssertLessThan(beforeShow(flickPath) - landed, 120, "\(flick)")
        let flickSteps = flickPath.map { $0[0] }.filter { $0 <= landed }
        XCTAssertLessThan(zip(flickSteps, flickSteps.dropFirst()).map { $1 - $0 }.max() ?? 1000, 100, "\(flick)")
    }

    func testSessionSwipeIntoManyTabsDrawsThemWithTheSidebar() async throws {
        addTeardownBlock { [eight] in _ = try? await Self.post("\(eight)/stress") }
        try await Self.post("\(eight)/stress", Data("200 20 200 0".utf8))
        for _ in 0 ..< 3 {
            try await Self.call(eight, "pane.split", ["target_pane_id": "w1:p1", "direction": "down", "cwd": "/tmp",
                                                      "focus": false, "env": ["ZDOTDIR": "/var/empty"]])
        }
        relaunch(eight, ["-recordLatency", "YES", "-forceMotion", "YES"])
        addTeardownBlock { @MainActor in self.keep(self.element("app.latency").stringValue, as: "latency") }
        XCTAssertTrue(element("pane.w1:p1").exists(within: 20))
        openPage(one)
        XCTAssertTrue(until(3) { header == one })
        let sidebar = element("sidebar"), center = "\(sidebar.frame.midX) \(sidebar.frame.midY)"
        // Which sign goes back follows natural scrolling. 10 pt past half the sidebar's width: a lift CI posts over 100
        // ms late counts as a rest, and short of half the pages spring back.
        let moves = Int(sidebar.frame.width / 20) + 1
        var back = 10.0
        for target in [eight, one, eight] {
            for _ in 0 ..< 2 {
                try await Self.post("\(one)/swipe", Data("\(center) \(back) \(moves)".utf8))
                // No accessibility query until the window drew it: XCUITest's take the main thread.
                try await Task.sleep(for: .seconds(1.5))
                if header == target {
                    break
                }
                back = -back
            }
            XCTAssertEqual(header, target)
            back = -back
        }
        let shows = element("app.latency").stringValue.split(separator: "; ").filter { $0.hasPrefix("session ") }
            .compactMap { Int($0.split(separator: " ")[1].dropLast(2)) }
        XCTAssertEqual(shows.count, 3, "\(shows)")
        // The better of the two: CI's first show of a page after a launch is sometimes twice as slow.
        XCTAssertLessThan(min(shows[0], shows[2]), 600, "\(shows)")
    }

    private func swipes() -> [(String, [[Double]], Double)] { // swiftlint:disable:this large_tuple
        element("app.latency").stringValue.split(separator: "; ").filter { $0.hasPrefix("swipe ") }.map { swipe in
            let words = swipe.split(separator: " ")
            let path = words.count > 2
                ? words[2].split(separator: ",").map { $0.split(separator: ":").compactMap { Double($0) } } : []
            return (String(swipe), path, words.count > 3 ? Double(words[3]) ?? -1 : -1)
        }.filter { $0.1.count > 4 }
    }

    /// Not the show's own time: a late frame delays it (CI's VM drew none for 60 ms there, the show 80 ms after the
    /// page).
    private func beforeShow(_ path: [[Double]]) -> Double {
        path.last?[0] ?? 0
    }

    private func launchRecordingLatency(_ args: [String] = []) throws {
        relaunch(one, ["-recordLatency", "YES"] + args)
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        addTeardownBlock { @MainActor in self.keep(self.element("app.latency").stringValue, as: "latency") }
    }

    private func key(_ key: String, _ flags: XCUIElement.KeyModifierFlags, until done: () -> Bool) {
        app.typeKey(key, modifierFlags: flags)
        XCTAssertTrue(until(5, done), "after \(key)")
        Thread.sleep(forTimeInterval: 0.5)
    }

    struct Entry {
        let name: String, turns: Int, lists: Int
    }

    func recorded() -> [Entry] {
        element("app.latency").stringValue.split(separator: "; ").map { entry in
            let words = entry.split(separator: " ").map(String.init)
            return Entry(name: words.first ?? "", turns: Int(words.count > 2 ? words[2] : "") ?? -1,
                         lists: Int(words.count > 4 ? words[4] : "") ?? -1)
        }
    }
}
