import XCTest

/// 400 agent panes, 200 on a Mac, whose 511 terminals the user's programs share.
extension OvviUITests {
    func testHundredsOfSpacesKeepTheSidebarQuick() async throws {
        executionTimeAllowance = 600
        addTeardownBlock { [eight] in _ = try? await Self.post("\(eight)/stress") }
        let made = try await Self.post("\(eight)/stress", Data("200 200 400 400 still".utf8))
        note(String(decoding: made, as: UTF8.self))
        relaunch(eight, ["-recordLatency", "YES"])
        addTeardownBlock { @MainActor in self.note(self.element("app.latency").stringValue) }
        XCTAssertTrue(element("workspace.w1").exists(within: 30))
        openPage(one)
        showPage(eight)
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, eight, within: 5))
        try await Task.sleep(for: .seconds(5))
        let sidebar = element("sidebar").frame
        let records = {
            self.element("app.latency").stringValue.split(separator: "; ").filter { $0.hasPrefix("scroll ") }
        }

        let before = records().count
        for sign in [-1.0, 1.0, -1.0, 1.0] {
            try await Self.post("\(one)/swipe", Data("\(sidebar.midX) \(sidebar.midY) \(60 * sign) 30 0 1".utf8))
            try await Task.sleep(for: .seconds(0.6))
        }
        let scrolls = records().dropFirst(before)
        note("scrolls: \(scrolls.joined(separator: ", "))")
        XCTAssertGreaterThanOrEqual(scrolls.count, 4)

        app.typeKey("2", modifierFlags: [.command, .control])
        app.typeKey("1", modifierFlags: [.command, .control])
        XCTAssertTrue(element("workspace.w1").has(\.isSelected, true, within: 5))
        fold("w1")
        unfold("w1")
        hoverCardComesAndGoes()

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
        for record in swipes {
            let rows = Int(record.split(separator: " ").dropFirst(8).first ?? "") ?? .max
            XCTAssertLessThan(rows, 300, String(record))
        }
        XCTAssertGreaterThanOrEqual(swipes.count, 4)
    }

    private func swipeAwayAndBack(over sidebar: CGRect) async throws {
        for _ in 0 ..< 2 {
            for sign in [-1.0, 1.0] {
                try await Self.post("\(one)/swipe", Data("\(sidebar.midX) \(sidebar.midY) \(40 * sign) 15".utf8))
                try await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    private func hoverCardComesAndGoes() {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'agent.'")).firstMatch
            .hover()
        XCTAssertTrue(element("hovercard").exists(within: 3))
        element("sidebar.header").hover()
        XCTAssertTrue(element("hovercard").vanishes(within: 3))
    }
}
