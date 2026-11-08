import XCTest

/// Web cards whose WebKit processes end (the system ends one under memory pressure, after a sleep or a long idle)
/// come back by themselves with their page where it was: a browser's address and scroll, a Markdown card's file
/// rendered and its scroll; shown, in a kept tab out of view, and after the GPU or the network process ended.
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
        element("browser.\(browser)").scroll(byDeltaX: 0, deltaY: -10000)
        notes.scroll(byDeltaX: 0, deltaY: -10000)
        // Both pages drawn at their ends, the Markdown file rendered.
        func atTheirEnds(_ what: String) {
            XCTAssertTrue(until(15) { pageText("Paragraph 200").isHittable }, "the browser's page, \(what)")
            XCTAssertTrue(until(15) { last.exists && !heading.exists }, "the Markdown page, \(what)")
            let raw = notes.staticTexts.matching(NSPredicate(format: "value CONTAINS '**'")).firstMatch
            XCTAssertFalse(raw.exists, "a line with its marks, \(what): \(raw.exists ? raw.value ?? "" : "")")
        }
        atTheirEnds("at first")
        // The scroll noted (WebKit's history item, the page's session).
        try await Task.sleep(for: .milliseconds(500))
        let killed = try await end()
        XCTAssertGreaterThanOrEqual(killed.count, 2, "both cards' page processes")
        atTheirEnds("after their process ended")
        // In a kept tab out of view: shown again.
        let (other, _) = try await createTab(in: "w2", label: "other")
        closeAfter("tab", other)
        try await show(other)
        _ = try await end()
        try await show(tab)
        atTheirEnds("in a hidden tab")
        try await survivesHelperProcesses(browser, notes: notes, heading: heading, shell: shell)
    }

    /// A page whose process ends again before it loaded (an image that never comes keeps it loading) says so, and
    /// Reload brings it back: never a blank card.
    func testABrowserPageThatEndsTwiceSaysSoAndReloads() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("twice")
        try await waitForPrompt(shell)
        let folder = "/tmp/ovvi-e2e-twice", port = Int.random(in: 20000 ..< 30000)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_keys", ["pane_id": shell, "keys": ["ctrl+c"]])
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(folder)\r"])
        }
        try await send("mkdir -p \(folder) && printf '<title>Hang</title><p>ovvi-hang</p><img "
            + "src=\"http://127.0.0.1:\(port)/x.png\">' >\(folder)/hang.html && clear && "
            + "while :; do nc -l 127.0.0.1 \(port) >/dev/null; done\r", to: shell)
        let browser = try await split(shell)
        try await Self.call(one, "pane.rename", ["pane_id": browser,
                                                 "label": "ovvi:browser#e2etwc file://\(folder)/hang.html"])
        try await show(tab)
        XCTAssertTrue(pageText("ovvi-hang").exists(within: 15))
        _ = try await end()
        // Its page process again, as the page loads anew: the image keeps it from ever finishing.
        let message = element("browser.\(browser).message")
        try await poll("the card to say its page stopped", times: 10) { () async throws -> Bool? in
            _ = try await end()
            return message.exists(within: 1) ? true : nil
        }
        XCTAssertEqual(message.value as? String, "The page stopped working")
        element("browser.\(browser).retry").click()
        XCTAssertTrue(message.vanishes(within: 10))
        XCTAssertTrue(pageText("ovvi-hang").exists(within: 15))
    }

    /// WebKit starts its GPU and network processes again by itself: the pages still draw, the browser's Reload loads,
    /// a file change still shows.
    private func survivesHelperProcesses(_ browser: String, notes: XCUIElement, heading: XCUIElement,
                                         shell: String) async throws
    {
        let gpu = try await end("GPU")
        XCTAssertFalse(gpu.isEmpty, "no GPU process of the app")
        notes.scroll(byDeltaX: 0, deltaY: 10000)
        XCTAssertTrue(heading.exists(within: 10), "the Markdown page drew after the GPU process ended")
        let network = try await end("Networking")
        XCTAssertFalse(network.isEmpty, "no network process of the app")
        element("browser.\(browser).reload").click()
        XCTAssertTrue(
            until(15) { pageText("Paragraph 200").isHittable },
            "the browser's Reload after the network ended",
        )
        try await send("printf '# Changed\\n' >>notes.md\r", to: shell)
        notes.scroll(byDeltaX: 0, deltaY: -10000)
        XCTAssertTrue(notes.staticTexts.matching(NSPredicate(format: "value == 'Changed'")).firstMatch
            .exists(within: 10))
    }

    /// Kills the app's WebKit page processes, or its GPU or network process: the pids killed.
    private func end(_ kind: String = "") async throws -> [String] {
        let killed = try await String(decoding: Self.post("\(one)/web-kill", Data(kind.utf8)), as: UTF8.self)
        return killed.split(separator: "\n").map(String.init)
    }
}
