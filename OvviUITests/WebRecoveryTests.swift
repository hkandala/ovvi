import XCTest

/// Web cards whose WebKit page process ends (the system ends one under memory pressure, after a sleep or a long idle)
/// come back by themselves with their page where it was: a browser's address and scroll, a Markdown card's file
/// rendered and its scroll; shown, and in a kept tab out of view.
extension OvviUITests {
    func testWebCardsComeBackAfterTheirProcessEnds() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("ended")
        try await waitForPrompt(shell)
        let folder = "/tmp/ovvi-e2e-ended"
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(folder)\r"])
        }
        try await send("mkdir -p \(folder) && cd \(folder) && { echo '<title>Long</title>'; for i in $(seq 200); do "
            + "echo \"<p>Paragraph $i</p>\"; done; } >long.html && { echo '# Notes'; for i in $(seq 300); do "
            + "echo \"- Line $i, **bold** and \\`code\\`\"; done; } >notes.md && clear && echo ready-$((6*7))\r",
            to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let browser = try await split(shell), markdown = try await split(browser)
        try await Self.call(one, "pane.rename", ["pane_id": browser,
                                                 "label": "ovvi:browser#e2eend file://\(folder)/long.html"])
        try await Self.call(one, "pane.rename", ["pane_id": markdown,
                                                 "label": "ovvi:markdown#e2emde \(folder)/notes.md"])
        try await show(tab)
        let notes = element("markdown.\(markdown).page")
        let heading = notes.staticTexts.matching(NSPredicate(format: "value == 'Notes'")).firstMatch
        let last = notes.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Line 300,'")).firstMatch
        XCTAssertTrue(pageText("Paragraph 1").exists(within: 15))
        XCTAssertTrue(heading.exists(within: 15))
        element("browser.\(browser)").scroll(byDeltaX: 0, deltaY: -100_000)
        notes.scroll(byDeltaX: 0, deltaY: -100_000)
        // Both pages drawn at their ends, the Markdown file rendered.
        func atTheirEnds(_ what: String) {
            XCTAssertTrue(until(15) { pageText("Paragraph 200").isHittable }, "the browser's page, \(what)")
            XCTAssertTrue(until(15) { last.exists && !heading.exists }, "the Markdown page, \(what)")
            let raw = notes.staticTexts.matching(NSPredicate(format: "value CONTAINS '**'")).firstMatch
            XCTAssertFalse(raw.exists, "a line with its marks, \(what): \(raw.exists ? raw.value ?? "" : "")")
        }
        func end() async throws {
            let killed = try await String(decoding: Self.post("\(one)/web-kill"), as: UTF8.self)
            XCTAssertFalse(killed.isEmpty, "no page process of the app")
        }
        atTheirEnds("at first")
        // The scroll noted (WebKit's history item, the page's session).
        try await Task.sleep(for: .milliseconds(500))
        try await end()
        atTheirEnds("after their process ended")
        // In a kept tab out of view: shown again.
        let (other, _) = try await createTab(in: "w2", label: "other")
        closeAfter("tab", other)
        try await show(other)
        try await end()
        try await show(tab)
        atTheirEnds("in a hidden tab")
    }
}
