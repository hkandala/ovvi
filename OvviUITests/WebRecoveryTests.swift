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
        // Short Markdown lines: CI's narrow cards wrap long ones, and one wheel scroll must reach the end.
        try await send("mkdir -p \(folder) && cd \(folder) && { echo '<title>Long</title>'; for i in $(seq 200); do "
            + "echo \"<p>Paragraph $i</p>\"; done; } >long.html && { echo '# Notes'; for i in $(seq 120); do "
            + "echo \"- Line $i, **b** \\`c\\`\"; done; } >notes.md && clear && echo ready-$((6*7))\r",
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
        let last = notes.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Line 120,'")).firstMatch
        XCTAssertTrue(pageText("Paragraph 1").exists(within: 15))
        XCTAssertTrue(heading.exists(within: 15))
        // To their ends, again while a card still shows its loader over the page (which takes the wheel).
        XCTAssertTrue(until(20) {
            element("browser.\(browser)").scroll(byDeltaX: 0, deltaY: -10000)
            return pageText("Paragraph 200").isHittable
        })
        XCTAssertTrue(until(20) {
            notes.scroll(byDeltaX: 0, deltaY: -10000)
            return last.exists
        })
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
            + "while nc -l 127.0.0.1 \(port) >/dev/null; do :; done\r", to: shell)
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

    /// WebKit gives up on a GPU process that stops answering (a starved Mac) but cannot end it, so every page kept its
    /// drawing connection to it and stayed blank, Reload too. After it the cards draw again by themselves, a kept
    /// tab's Git card when shown, and after Reload, a file's change and a new commit. Needs a GPU process (not CI's).
    func testWebCardsDrawAgainAfterTheGPUProcessHangs() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("hang")
        try await waitForPrompt(shell)
        let folder = "/tmp/ovvi-e2e-hang"
        addTeardownBlock { [one] in
            _ = try? await Self.post("\(one)/web-resume", Data("GPU".utf8))
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(folder)\r"])
        }
        try await send("rm -rf \(folder) && mkdir -p \(folder) && cd \(folder) && git init -q "
            + "&& git -c user.name=e2e -c user.email=e2e@ovvi commit -q --allow-empty -m before "
            + "&& { for i in $(seq 200); do echo \"<p>Paragraph $i</p>\"; done; } >long.html "
            + "&& echo '# Notes' >notes.md && clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let browser = try await split(shell), markdown = try await split(browser)
        let (kept, keptShell) = try await createTab(in: "w2", label: "kept")
        closeAfter("tab", kept)
        let git = try await split(keptShell)
        for (pane, label) in [(browser, "browser#e2ehng file://\(folder)/long.html"),
                              (markdown, "markdown#e2ehmd \(folder)/notes.md"), (git, "git#e2ehgt /private\(folder)/")]
        {
            try await Self.call(one, "pane.rename", ["pane_id": pane, "label": "ovvi:\(label)"])
        }
        try await show(tab)
        let notes = element("markdown.\(markdown).page"), page = element("browser.\(browser)")
        let heading = { notes.staticTexts.matching(NSPredicate(format: "value == %@", $0)).firstMatch }
        XCTAssertTrue(drawn(pageText("Paragraph 1"), in: page, within: 15), "the browser at first")
        XCTAssertTrue(drawn(heading("Notes"), in: notes, within: 15), "the Markdown card at first")
        let gpu = try await web("web-pids")
        try XCTSkipIf(gpu.isEmpty, "no GPU process (CI's virtual Mac)")
        // Made once, then kept out of view.
        try await show(kept)
        let home = element("git.\(git).page")
        let commit = { home.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", $0 + ",")).firstMatch }
        XCTAssertTrue(drawn(commit("before"), in: home, within: 15), "the Git card at first")
        try await show(tab)

        let stopped = try await web("web-stop")
        let ended = try await waitsOut(stopped, scrolling: page)
        XCTAssertTrue(ended, "the app ended the GPU process WebKit gave up on")
        // By themselves; the browser back at its top, which Reload keeps.
        page.scroll(byDeltaX: 0, deltaY: 10000)
        XCTAssertTrue(drawn(pageText("Paragraph 1"), in: page, within: 10), "the browser by itself")
        XCTAssertTrue(drawn(heading("Notes"), in: notes, within: 10), "the Markdown card by itself")
        element("browser.\(browser).reload").click()
        XCTAssertTrue(drawn(pageText("Paragraph 1"), in: page, within: 10), "the browser after Reload")
        try await send("echo '# Changed' >notes.md\r", to: shell)
        XCTAssertTrue(drawn(heading("Changed"), in: notes, within: 10), "the Markdown card's change")
        try await show(kept)
        XCTAssertTrue(drawn(commit("before"), in: home, within: 10), "the kept Git card by itself, shown")
        try await send("git -c user.name=e2e -c user.email=e2e@ovvi commit -q --allow-empty -m after\r", to: shell)
        XCTAssertTrue(drawn(commit("after"), in: home, within: 10), "the kept Git card's new commit")
    }

    /// Scrolls the browser's page while the stopped GPU process holds its draws, until WebKit gives up on it (10 to
    /// 25 s here) and the app ends it: false if it still runs after 30 s. On the old code it lived on, and once let
    /// go 30 s or more after WebKit gave up, it answered no page: every card stayed blank, Reload too.
    private func waitsOut(_ stopped: Set<String>, scrolling page: XCUIElement) async throws -> Bool {
        var delta = -3000.0
        let deadline = Date.now + 30
        while Date.now < deadline {
            page.scroll(byDeltaX: 0, deltaY: delta)
            delta = -delta
            if try await web("web-pids").isDisjoint(with: stopped) {
                return true
            }
        }
        return false
    }

    /// The element shows its text: both dark and light pixels in its frame, not one blank fill.
    private func drawn(_ element: XCUIElement, in page: XCUIElement, within seconds: Double) -> Bool {
        until(seconds) {
            // Only in its page's view: one out of it, or with an empty frame (a blank page's text), has no screenshot.
            guard element.exists, !element.frame.isEmpty, page.frame.contains(element.frame) else { return false }
            let brightness = Self.brightness(element.screenshot().image)
            return (brightness.max() ?? 0) - (brightness.min() ?? 0) > 100
        }
    }

    /// The app's GPU processes, after the action on them.
    private func web(_ action: String) async throws -> Set<String> {
        let pids = try await Self.post("\(one)/\(action)", Data("GPU".utf8))
        return Set(String(decoding: pids, as: UTF8.self).split(separator: "\n").map(String.init))
    }

    /// WebKit starts its GPU and network processes again by itself: the pages still draw, the browser's Reload loads,
    /// a file change still shows.
    private func survivesHelperProcesses(_ browser: String, notes: XCUIElement, heading: XCUIElement,
                                         shell: String) async throws
    {
        // CI's virtual Mac runs WebKit with no GPU process.
        if try await !end("GPU").isEmpty {
            notes.scroll(byDeltaX: 0, deltaY: 10000)
            XCTAssertTrue(heading.exists(within: 10), "the Markdown page drew after the GPU process ended")
        }
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
