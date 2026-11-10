import XCTest

extension OvviUITests {
    func testADragOverWebCardsShowsTheirEdgesAndDrops() async throws {
        let (tabs, first) = try await newWorkspace("web")
        let tab = tabs[0]
        try await waitForPrompt(first)
        let page = try await writePages(from: first)
        let browser = try await split(first), plugin = try await split(browser)
        let explorer = "ovvi:explorer#e2edrp /private/tmp/ovvi-e2e-browser/"
        for (pane, label) in [(browser, "ovvi:browser#e2edrb \(page)"), (plugin, explorer)] {
            try await relabel(pane, label)
        }
        restoreHerdrFocusAfter()
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: 10))
        XCTAssertTrue(element("files.\(plugin).page").descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "one.html")).firstMatch.exists(within: 10))

        // Through the helper's press, which leaves XCUITest free to read the highlight while it holds: drag.swift's
        // release 4 s into a timed hold can leave a session that never ends (CI).
        let from = card(first, 0, 0).withOffset(CGVector(dx: 60, dy: 17)).screenPoint
        let over = [browser, plugin].map { card($0, 0.9, 0.6).screenPoint }
        let path = "\(from.x) \(from.y) \(over[0].x) \(over[0].y) 4 \(over[1].x) \(over[1].y)"
        let drag = Task.detached { [one] in try await Self.post("\(one)/press", Data(path.utf8)) }
        let indicator = element("drop.indicator")
        for pane in [browser, plugin] {
            let frame = element("pane.\(pane)").frame
            let right = CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
            var seen = CGRect.null
            // A hold of 4 s: a snapshot near a web view can take seconds.
            XCTAssertTrue(until(8) {
                // One snapshot a look: the last card's highlight may still fade out beside the new one.
                seen = (try? indicator.firstMatch.snapshot())?.frame ?? .null
                return abs(seen.minX - right.minX) < 3 && abs(seen.maxX - right.maxX) < 3
                    && abs(seen.minY - right.minY) < 3 && abs(seen.maxY - right.maxY) < 3
            }, "the highlight over \(pane)'s right half \(right): \(seen)")
        }
        _ = try await drag.value
        try await release()
        try await expect("the pane right of the plugin card") { try await order(tab) == [browser, plugin, first] }
        XCTAssertTrue(indicator.vanishes(within: 2))
    }
}
