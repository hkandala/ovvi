import XCTest

/// HTML (ui/window#opening-links-and-files): a Markdown link to an HTML file opens its page in the browser (⌥-click: to
/// the side); File Explorer shows the file as text, and its header's Open in Browser opens the page in a new tab,
/// selected. A file of another kind has no Open in Browser.
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

        let (tab, notes) = try await explorerCard("\(folder)/notes.md", "e2eht1")
        let link = element("markdown.\(notes).page").links["Page"]
        XCTAssertTrue(link.exists(within: 10))
        XCUIElement.perform(withKeyModifiers: .option) { link.click() }
        let side = try await poll("a pane beside the card") { () async throws -> String? in
            try await (snapshot()["panes"] as? [[String: Any]] ?? []).first {
                $0["tab_id"] as? String == tab && $0["pane_id"] as? String != notes
            }?["pane_id"] as? String
        }
        try await browserLabel(side, html)

        let (_, file) = try await explorerCard(html, "e2eht2")
        let button = element("pane.\(file).browser")
        XCTAssertTrue(button.exists(within: 10))
        keepScreenshot("html file card")
        let before = try await tabIDs()
        button.click()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 5))
        try await browserLabel(pane(of: opened), html)

        let (_, plain) = try await explorerCard("\(folder)/plain.txt", "e2eht3")
        XCTAssertTrue(element("pane.\(plain).open-with").exists(within: 10))
        XCTAssertFalse(element("pane.\(plain).browser").exists)
    }

    /// A File Explorer card on `path` in a tab of its own, shown.
    private func explorerCard(_ path: String, _ iid: String) async throws -> (tab: String, pane: String) {
        let root: [String: Any] = ["type": "pane", "cwd": "/tmp", "label": "ovvi:explorer#\(iid) \(path)",
                                   "command": ["sh", "-c", "cat", "sh"]]
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": root])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        closeAfter("tab", tab)
        try await show(tab)
        return try (tab, field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane"))
    }

    /// The pane is a browser card on the file's `file:` page.
    private func browserLabel(_ pane: String, _ path: String) async throws {
        try await expect("a browser on \(path) in \(pane)") {
            let label = try await paneLabel(pane)
            return label.hasPrefix("ovvi:browser#") && label.hasSuffix(" file://\(path)")
        }
    }
}
