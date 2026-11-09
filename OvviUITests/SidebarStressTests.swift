import XCTest

/// The sidebar at scale: a session of 200 spaces with 400 agent panes (200 on a Mac, whose 511 terminals the user's
/// programs share; `scripts/stress.py --still`: one state each, no programs running) beside a small session. Fast
/// scrolls of its list, session swipes to and from it, a fold and its unfold, and the pointer over the rows, each
/// recorded ("scroll ‹frames› ‹hitches› ‹ms› ‹p50› ‹p95› ‹max› ‹main thread's CPU› ‹rows made› ‹hitches›", kept in
/// the result bundle as "stress"). The rows made bound the work: a lazy list makes the rows that come into view, an
/// eager one made all of them whenever the page was made.
extension OvviUITests {
    func testHundredsOfSpacesKeepTheSidebarQuick() async throws {
        executionTimeAllowance = 600
        let eight = try env("OVVI_SESSION8")
        addTeardownBlock { _ = try? await Self.post("\(eight)/stress") }
        let made = try await Self.post("\(eight)/stress", Data("200 200 400 400 still".utf8))
        note(String(decoding: made, as: UTF8.self))
        relaunch(eight, ["-recordLatency", "YES"])
        addTeardownBlock { @MainActor in self.note(self.element("app.latency").stringValue) }
        XCTAssertTrue(element("workspace.w1").exists(within: 30))
        openPage(one)
        showPage(eight)
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, eight, within: 5))
        // The agents' first states.
        try await Task.sleep(for: .seconds(5))
        let sidebar = element("sidebar").frame
        let records = {
            self.element("app.latency").stringValue.split(separator: "; ").filter { $0.hasPrefix("scroll ") }
        }

        // Down and up the list, 60 pt every 16 ms and the momentum after.
        let before = records().count
        for sign in [-1.0, 1.0, -1.0, 1.0] {
            try await Self.post("\(one)/swipe", Data("\(sidebar.midX) \(sidebar.midY) \(60 * sign) 30 0 1".utf8))
            try await Task.sleep(for: .seconds(0.6))
        }
        let scrolls = records().dropFirst(before)
        note("scrolls: \(scrolls.joined(separator: ", "))")
        XCTAssertGreaterThanOrEqual(scrolls.count, 4)

        // The first space, in view again; its fold and unfold, and an agent line's hover card, which comes and goes
        // with the pointer.
        app.typeKey("1", modifierFlags: [.command, .control])
        XCTAssertTrue(element("workspace.w1").has(\.isSelected, true, within: 5))
        fold("w1")
        unfold("w1")
        hoverCardComesAndGoes()

        // The last space (⌃⌘[ from the first goes round), then to the small session's page and back, a swipe each way
        // (which way goes on follows natural scrolling): the page made again shows the selected row.
        app.typeKey("[", modifierFlags: [.command, .control])
        let selected = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier MATCHES %@ AND selected == true", #"workspace\.w[0-9]+"#,
        )).firstMatch
        XCTAssertTrue(selected.exists(within: 5))
        let last = element(selected.identifier)
        XCTAssertNotEqual(last.identifier, "workspace.w1")
        let swiped = records().count
        try await swipeAwayAndBack(over: sidebar)
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, eight, within: 5))
        XCTAssertTrue(last.has(\.isHittable, true, within: 3), "\(last.frame) in \(sidebar)")
        let swipes = records().dropFirst(swiped)
        note("swipes: \(swipes.joined(separator: ", "))")
        XCTAssertGreaterThanOrEqual(swipes.count, 4)

        // The swipes carry it: the page that comes back in is made again, and an eager list made all its rows then
        // (2,300 at 200 spaces and 400 agents), a lazy one those in view (about 50).
        for record in swipes {
            let rows = Int(record.split(separator: " ").dropFirst(8).first ?? "") ?? .max
            XCTAssertLessThan(rows, 300, String(record))
        }
    }

    /// Two swipes each way over the sidebar: to the other page and back.
    private func swipeAwayAndBack(over sidebar: CGRect) async throws {
        for _ in 0 ..< 2 {
            for sign in [-1.0, 1.0] {
                try await Self.post("\(one)/swipe", Data("\(sidebar.midX) \(sidebar.midY) \(40 * sign) 15".utf8))
                try await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    /// The first agent line made: its hover card opens under the pointer (one hover for the whole list), and goes.
    private func hoverCardComesAndGoes() {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'agent.'")).firstMatch
            .hover()
        XCTAssertTrue(element("hovercard").exists(within: 3))
        element("sidebar.header").hover()
        XCTAssertTrue(element("hovercard").vanishes(within: 3))
    }
}
