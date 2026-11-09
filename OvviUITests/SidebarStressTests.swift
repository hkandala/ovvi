import XCTest

/// The sidebar at scale: a session of 200 spaces with 400 agent panes (200 on a Mac, whose 511 terminals the user's
/// programs share; `scripts/stress.py --still`: one state each, no programs running) beside a small session. Fast
/// scrolls of its list, session swipes to and from it, a fold and its unfold, and the pointer over the rows, each
/// recorded ("scroll ‹frames› ‹hitches› ‹ms› ‹p50› ‹p95› ‹max› ‹main thread's CPU› ‹rows made› ‹hitches›", kept in
/// the result bundle as "stress"). The rows made bound the work: a lazy list makes the rows that come into view, an
/// eager one made all of them at each update of the page.
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

        // To the small session's page and back, a swipe each way (which way goes on follows natural scrolling).
        let swiped = records().count
        for _ in 0 ..< 2 {
            for sign in [-1.0, 1.0] {
                try await Self.post("\(one)/swipe", Data("\(sidebar.midX) \(sidebar.midY) \(40 * sign) 15".utf8))
                try await Task.sleep(for: .seconds(1.2))
            }
        }
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, eight, within: 5))
        let swipes = records().dropFirst(swiped)
        note("swipes: \(swipes.joined(separator: ", "))")
        XCTAssertGreaterThanOrEqual(swipes.count, 4)

        // A fold and the unfold, then the pointer down the rows (hover cards come and go).
        fold("w1")
        unfold("w1")
        for index in [2, 5, 9] {
            element("workspace.w\(index)").hover()
            try await Task.sleep(for: .seconds(0.5))
        }

        // An eager list made each of its 600 rows at every scroll frame: thousands a scroll.
        for record in scrolls + swipes {
            let words = record.split(separator: " ")
            let rows = words.count > 8 ? Int(words[8]) ?? .max : .max
            XCTAssertLessThan(rows, 300, String(record))
        }
    }
}
