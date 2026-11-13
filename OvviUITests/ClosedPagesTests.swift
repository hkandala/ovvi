import XCTest

extension OvviUITests {
    /// The machine's list is one file for every session: the test writes its own start and removes it after.
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
        let (other, otherPane) = try await newTab("closed-tab")
        try await relabel(otherPane, "ovvi:browser#e2ec03 \(page)")
        try await show(other)
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: 5))
        try await expectSaved("One", iid: "e2ec03", shell: shell)
        let row = element("tab.\(other)")
        row.hover()
        element("tab.\(other).close").click()
        XCTAssertTrue(row.vanishes(within: 3))

        try await show(tab)
        XCTAssertTrue(pageText("ovvi-page-two").exists(within: 5))
        try await expectSaved("Two", iid: "e2ec02", shell: shell)
        hoverHeader(gone)
        element("pane.\(gone).close").click()
        XCTAssertTrue(element("pane.\(gone)").vanishes(within: 3))

        // Newest first, 20 at most: the oldest two went.
        func expectMenu(_ titles: [String], _ count: Int) {
            element("browser.\(kept).closed").click()
            XCTAssertTrue(closedItem(0).exists(within: 5))
            XCTAssertEqual(titles, titles.indices.map { closedItem($0).title })
            XCTAssertTrue(closedItem(count - 1).exists)
            XCTAssertFalse(closedItem(count).exists)
        }
        expectMenu(["One", "Two", "Old 0"], 20)
        XCTAssertEqual(closedItem(19).title, "Old 17")
        keepScreenshot("recently closed, dark")
        var tabs = try await tabIDs()
        closedItem(1).click()
        let reopened = try await newTabID(after: tabs)
        closeAfter("tab", reopened)
        tabs.append(reopened)
        let reopenedPane = try await pane(of: reopened)
        try await expect("two.html in a new tab") { try await paneLabel(reopenedPane).hasSuffix(" \(two)") }
        XCTAssertTrue(element("tab.\(reopened)").has(\.isSelected, true, within: 3))

        relaunch(one, ["-appearance", "light"])
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
        let old = (0 ..< 20).map { #"{"url":"https://old\#($0).invalid/","title":"Old \#($0)"}"# }
        sendAfter("rm -f \(file)\r", to: shell)
        try await send("mkdir -p ~/.local/state/ovvi && printf '%s' '[\(old.joined(separator: ","))]' >\(file) && "
            + "clear\r", to: shell)
        try await waitFor(shell) { !$0.contains("printf") }
    }

    private func closedItem(_ index: Int) -> XCUIElement {
        app.menuItems["browser.closed.\(index)"]
    }
}
