import XCTest

extension OvviUITests {
    /// The machine's list is one file for every session: the test puts it aside, writes its own and puts it back.
    func testClosedBrowserPagesReopenFromTheMenuAndStayAfterARelaunch() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("closed")
        try await waitForPrompt(shell)
        let page = try await writePages(from: shell), two = page.replacing("one.html", with: "two.html")
        try await writeOldClosedPages(from: shell)

        let kept = try await split(shell)
        try await relabel(kept, "ovvi:browser#e2ec01 \(page)")
        let gone = try await split(kept, "down")
        try await relabel(gone, "ovvi:browser#e2ec02 \(two)")
        try await closeTab(showing: page, shell: shell)

        try await show(tab)
        XCTAssertTrue(pageText("ovvi-page-two").exists(within: 5))
        try await expectSaved("Two", iid: "e2ec02", shell: shell)
        hoverHeader(gone)
        element("pane.\(gone).close").click()
        XCTAssertTrue(element("pane.\(gone)").vanishes(within: 3))

        // Newest first, 20 at most: the oldest two went. A title too long ends in an ellipsis.
        func expectMenu(_ titles: [String], _ count: Int) {
            element("browser.\(kept).closed").click()
            XCTAssertTrue(closedItem(0).exists(within: 5))
            XCTAssertEqual(titles, titles.indices.map(closedTitle))
            XCTAssertTrue(closedItem(count - 1).exists)
            XCTAssertFalse(closedItem(count).exists)
        }
        expectMenu(["Two", "One", "Old 0"], 20)
        XCTAssertEqual(closedTitle(19), "Old 17")
        let long = closedTitle(7)
        XCTAssertTrue(long.hasPrefix("Old 5 xxx") && long.hasSuffix("…") && long.count < 80, long)
        keepScreenshot("recently closed, dark")
        var tabs = try await tabIDs()
        closedItem(0).click()
        let reopened = try await newTabID(after: tabs)
        closeAfter("tab", reopened)
        tabs.append(reopened)
        let reopenedPane = try await pane(of: reopened)
        try await expect("two.html in a new tab") { try await paneLabel(reopenedPane).hasSuffix(" \(two)") }
        XCTAssertTrue(element("tab.\(reopened)").has(\.isSelected, true, within: 3))

        relaunch(one, ["-appearance", "light"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        try await show(tab)
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: connect))
        expectMenu(["One", "Old 0"], 19)
        keepScreenshot("recently closed, light")
        XCUIElement.perform(withKeyModifiers: .option) { closedItem(0).click() }
        let side = try await sidePane(in: tab, besides: [shell, kept])
        try await expect("one.html beside the card") { try await paneLabel(side).hasSuffix(" \(page)") }
    }

    /// 20 older pages, newest first: the cap drops the oldest.
    private func writeOldClosedPages(from shell: String) async throws {
        let file = "~/.local/state/ovvi/closed-pages.json"
        let old = (0 ..< 20).map { index in
            let title = "Old \(index)" + (index == 5 ? " " + String(repeating: "x", count: 120) : "")
            return #"{"url":"https://old\#(index).invalid/","title":"\#(title)"}"#
        }
        sendAfter("mv -f \(file).e2e \(file) 2>/dev/null || rm -f \(file)\r", to: shell)
        try await send("mkdir -p ~/.local/state/ovvi && mv -n \(file) \(file).e2e 2>/dev/null; "
            + "printf '%s' '[\(old.joined(separator: ","))]' >\(file) && clear\r", to: shell)
        try await waitFor(shell) { !$0.contains("printf") }
    }

    /// A tab with one browser card, closed: its title is saved first.
    private func closeTab(showing page: String, shell: String) async throws {
        let (tab, pane) = try await newTab("closed-tab")
        try await relabel(pane, "ovvi:browser#e2ec03 \(page)")
        try await show(tab)
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: 5))
        try await expectSaved("One", iid: "e2ec03", shell: shell)
        // Its icon, a PNG.
        try await expectSaved("iVBORw0KGgo", iid: "e2ec03", shell: shell)
        let row = element("tab.\(tab)")
        row.hover()
        element("tab.\(tab).close").click()
        XCTAssertTrue(row.vanishes(within: 3))
    }

    /// The row's text after its icon.
    private func closedTitle(_ index: Int) -> String {
        closedItem(index).title.trimmingCharacters(in: CharacterSet.whitespaces.union(["\u{FFFC}"]))
    }

    private func closedItem(_ index: Int) -> XCUIElement {
        app.menuItems["browser.closed.\(index)"]
    }
}
