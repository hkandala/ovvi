import XCTest

/// HTML (ui/window#opening-links-and-files): a Markdown link to an HTML file opens its page in the browser
/// (⌘-click: in a new tab behind, ⌥-click: to the side); File Explorer shows the file as text, and its header's Open
/// in Browser opens the page in a new tab, selected. A file of another kind has no Open in Browser.
extension OvviUITests {
    func testHtmlOpensInTheBrowserFromLinksAndTheFileCard() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("html")
        let folder = "/tmp/ovvi-e2e-html"
        try await waitForPrompt(shell)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(folder)\r"])
        }
        try await send("mkdir -p \(folder) && cd \(folder) && printf '<h1>Hi</h1>\\n' >page.html "
            + "&& printf '[Page](page.html)\\n' >notes.md && printf 'x\\n' >plain.txt && clear "
            + "&& echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let html = "\(folder)/page.html"

        let (tab, notes) = try await newCard("ovvi:explorer#e2eht1 \(folder)/notes.md")
        let link = element("markdown.\(notes).page").links["Page"]
        XCTAssertTrue(link.exists(within: 10))
        let tabs = try await tabIDs()
        XCUIElement.perform(withKeyModifiers: .command) { link.click() }
        let behind = try await newTabID(after: tabs)
        closeAfter("tab", behind)
        try await browserLabel(pane(of: behind), html)
        XCTAssertTrue(element("tab.\(tab)").isSelected)
        XCUIElement.perform(withKeyModifiers: .option) { link.click() }
        let side = try await poll("a pane beside the card") { () async throws -> String? in
            try await (snapshot()["panes"] as? [[String: Any]] ?? []).first {
                $0["tab_id"] as? String == tab && $0["pane_id"] as? String != notes
            }?["pane_id"] as? String
        }
        try await browserLabel(side, html)

        let (_, file) = try await newCard("ovvi:explorer#e2eht2 \(html)")
        let button = element("pane.\(file).browser")
        XCTAssertTrue(button.exists(within: 10))
        keepScreenshot("html file card")
        let before = try await tabIDs()
        button.click()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 5))
        try await browserLabel(pane(of: opened), html)

        let (_, plain) = try await newCard("ovvi:explorer#e2eht3 \(folder)/plain.txt")
        XCTAssertTrue(element("pane.\(plain).open-with").exists(within: 10))
        XCTAssertFalse(element("pane.\(plain).browser").exists)
    }

    /// A file that is gone says so in a notice, "File not found: ‹path›": a terminal link (⌥-click on an absolute path
    /// with an extension), `ovvi open` from a shell and a Markdown link. A word that only looks like a path opens
    /// nothing, silently.
    func testGoneFilesSayFileNotFound() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("gone")
        element("tab.\(tab)").click()
        let folder = "/tmp/ovvi-e2e-gone"
        try await waitForPrompt(shell)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(folder)\r"])
        }
        try await send("mkdir -p \(folder) && cd \(folder) && printf '[Gone](gone.md)\\n' >notes.md && clear; "
            + "echo /reload your open pi; echo \(folder)/gone.md\r", to: shell)
        try await waitFor(shell) { $0.hasPrefix("/reload your open pi\n") }
        let terminal = element("terminal.\(shell)")
        let grid = try XCTUnwrap(terminal.value as? String).split(separator: " ").compactMap { Double($0) }
        let link = { (row: Double) in
            terminal.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: terminal.frame.width / grid[1] * 5.5, dy: terminal.frame.height / grid[0] * (row + 0.5),
            ))
        }
        let notice = element("detail.notice")
        XCUIElement.perform(withKeyModifiers: .command) { link(0).click() }
        XCTAssertFalse(notice.exists(within: 1))
        XCUIElement.perform(withKeyModifiers: .option) { link(1).click() }
        notFound(notice, "/tmp/ovvi-e2e-gone/gone.md")
        keepScreenshot("file not found notice")

        try await send("clear; \(Self.ovviCommand) open gone.md\r", to: shell)
        notFound(notice, "gone.md")

        let (_, notes) = try await newCard("ovvi:explorer#e2egn1 \(folder)/notes.md")
        let gone = element("markdown.\(notes).page").links["Gone"]
        XCTAssertTrue(gone.exists(within: 10))
        gone.click()
        notFound(notice, "/tmp/ovvi-e2e-gone/gone.md")
        XCTAssertEqual(element("pane.\(notes).title").stringValue, "notes.md")
    }

    /// The notice says the file is not found, then closes with its ✕.
    private func notFound(_ notice: XCUIElement, _ end: String) {
        let text = notice.staticTexts.matching(NSPredicate(
            format: "value BEGINSWITH 'File not found: ' AND value ENDSWITH %@",
            end,
        ))
        XCTAssertTrue(text.firstMatch.exists(within: 10), notice.debugDescription)
        notice.buttons["notice.close"].click()
        XCTAssertTrue(notice.vanishes(within: 3))
    }

    /// The pane is a browser card on the file's `file:` page.
    private func browserLabel(_ pane: String, _ path: String) async throws {
        try await expect("a browser on \(path) in \(pane)") {
            let label = try await paneLabel(pane)
            return label.hasPrefix("ovvi:browser#") && label.hasSuffix(" file://\(path)")
        }
    }
}
