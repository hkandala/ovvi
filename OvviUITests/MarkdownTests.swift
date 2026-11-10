import AppKit
import XCTest

extension OvviUITests {
    func testMarkdownCardReadsEditsSavesAndLinks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("markdown")
        let folder = "/tmp/ovvi-e2e-markdown"
        try await waitForPrompt(shell)
        sendAfter("rm -rf \(folder)\r", to: shell)
        try await send("mkdir -p \(folder) && cd \(folder) && printf '%s\\n' '---' 'title: Hidden' '---' '# Notes' "
            + "'Some *words*.' '## Second' '- [ ] Ship it' '' '[Other](other.md)' '' '| A | B |' '| - | - |' "
            + "'| 1 | 2 |' '' '1. Alpha' '1. Beta' '' '   More of beta.' '' 'See [Docs][d] &copy;' '' "
            + "'[d]: https://example.com' >notes.md && printf 'Other\\n' >other.md && clear "
            + "&& echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let (tab, card) = try await newCard("ovvi:explorer#e2emdc \(folder)/notes.md")

        let page = element("markdown.\(card).page")
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.exists(within: 10))
        XCTAssertTrue(element("pane.\(card).mode.rich text").isSelected)
        XCTAssertFalse(element("pane.\(card).lock").isSelected)
        XCTAssertEqual(element("pane.\(card).lock").label, "Edit")
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'B'")).firstMatch.exists)
        XCTAssertFalse(page.textViews.firstMatch.exists)
        element("pane.\(card).outline").click()
        XCTAssertTrue(element("pane.\(card).outline").has(\.isSelected, true, within: 3))
        XCTAssertTrue(page.buttons["Second"].exists(within: 3))
        XCTAssertFalse(page.buttons["title: Hidden"].exists)
        keepScreenshot("markdown card, read, outline")
        constructs(page)
        try await tick(card, page: page, shell: shell)

        try await editAndSave(card, page: page, shell: shell)

        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, "explorer", within: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))

        openPalette()
        app.typeText("markdown read")
        XCTAssertTrue(element("palette.command.Lock Editing").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("pane.\(card).lock").has(\.isSelected, false, within: 3))
        try await send("printf '## Third\\n' >>notes.md\r", to: shell)
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'Third'")).firstMatch.exists(within: 5))
        copyAll(page)
        try await links(card, page: page, folder: folder, tab: tab)
        try await source(card, page: page, shell: shell)
    }

    private func links(_ card: String, page: XCUIElement, folder: String, tab: String) async throws {
        let before = try await tabIDs()
        XCUIElement.perform(withKeyModifiers: .command) { page.links["Other"].click() }
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        XCTAssertTrue(element("tab.\(opened)").has(\.label, "File Explorer other.md", within: 5))
        let label = try await paneLabel(pane(of: opened))
        XCTAssertTrue(label.hasPrefix("ovvi:explorer#") && label.hasSuffix(" \(folder)/other.md"), label)
        try await show(tab)
        follow(card, page: page)
        try await openWebLink(page, from: tab)
    }

    private func source(_ card: String, page: XCUIElement, shell: String) async throws {
        let mode = element("pane.\(card).mode.source"), lock = element("pane.\(card).lock")
        mode.click()
        XCTAssertTrue(mode.has(\.isSelected, true, within: 3))
        let box = page.checkBoxes.firstMatch, dirty = element("pane.\(card).dirty")
        XCTAssertTrue(page.buttons["Show Preview"].exists(within: 5))
        XCTAssertFalse(box.exists)
        page.click()
        app.typeText("q")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(lock.has(\.isSelected, true, within: 3))
        let source = page.textViews.firstMatch
        XCTAssertTrue(until(5) { source.exists && source.stringValue.contains("Some *words*.") }, source.stringValue)
        XCTAssertFalse(source.stringValue.contains("q") || dirty.exists, source.stringValue)
        app.typeText("q")
        XCTAssertTrue(until(3) { source.stringValue == "q" }, source.stringValue)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 3))
        page.buttons["Show Preview"].click()
        XCTAssertTrue(box.exists(within: 5))
        keepScreenshot("markdown card, source")
        box.click()
        XCTAssertTrue(until(3) { source.stringValue.contains("- [ ] Ship it") }, source.stringValue)
        XCTAssertTrue(dirty.exists(within: 3))
        source.click()
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 3))
        try await send("clear && grep -q '^- \\[ \\] Ship it$' notes.md && echo split-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("split-42") }
        page.buttons["Hide Preview"].click()
        XCTAssertTrue(box.vanishes(within: 3))
        page.buttons["Show Preview"].click()
        XCTAssertTrue(box.exists(within: 3))
        page.links["Other"].click()
        XCTAssertTrue(element("pane.\(card).outline").vanishes(within: 5))
        XCTAssertTrue(mode.has(\.isSelected, true, within: 3))
        XCTAssertTrue(lock.isSelected && page.buttons["Hide Preview"].exists)
    }

    private func openWebLink(_ page: XCUIElement, from tab: String) async throws {
        let before = try await tabIDs()
        page.links["Docs"].click()
        let browser = try await newTabID(after: before)
        closeAfter("tab", browser)
        XCTAssertTrue(element("tab.\(browser)").has(\.isSelected, true, within: 5))
        let label = try await paneLabel(pane(of: browser))
        XCTAssertTrue(label.hasPrefix("ovvi:browser#") && label.contains(" https://example.com"), label)
        try await show(tab)
    }

    private func follow(_ card: String, page: XCUIElement) {
        page.links["Other"].rightClick()
        XCTAssertTrue(app.menuItems["Open to the Side"].exists(within: 2))
        XCTAssertTrue(app.menuItems["Open in New Tab"].exists && app.menuItems["Copy Link"].exists)
        keepScreenshot("markdown link menu")
        // Not Services ▸ Open in the menu bar.
        app.windows.menuItems["Open"].click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "other.md", within: 5))
        XCTAssertTrue(element("pane.\(card).outline").vanishes(within: 3))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "notes.md", within: 5))
        XCTAssertTrue(element("pane.\(card).outline").exists(within: 3))
    }

    private func constructs(_ page: XCUIElement) {
        let text = { (value: String) in self.text(value, in: page) }
        XCTAssertTrue(text("2.").exists(within: 3))
        let beta = text("Beta"), more = text("More of beta.")
        XCTAssertTrue(more.exists)
        XCTAssertLessThan(
            abs(more.frame.minX - beta.frame.minX),
            3,
            "Beta at \(beta.frame), its paragraph at \(more.frame)",
        )
        XCTAssertTrue(page.links["Docs"].exists)
        XCTAssertFalse(page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'example.com'")).firstMatch.exists)
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value CONTAINS '©'")).firstMatch.exists)
    }

    private func editAndSave(_ card: String, page: XCUIElement, shell: String) async throws {
        page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.click()
        app.typeText("q")
        let link = page.links["Other"].frame
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).lock").has(\.isSelected, true, within: 3))
        XCTAssertEqual(element("pane.\(card).lock").label, "Stop Editing")
        let editor = page.textViews.firstMatch
        XCTAssertTrue(until(5) { editor.exists && editor.stringValue.contains("## Second") }, editor.stringValue)
        XCTAssertTrue(editor.stringValue.contains("Some words."))
        XCTAssertFalse(editor.stringValue.contains("*words*"))
        XCTAssertEqual(page.links["Other"].frame, link)
        page.links["Other"].click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "other.md", within: 5))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "notes.md", within: 5))
        page.staticTexts.matching(NSPredicate(format: "value == '1'")).firstMatch.click()
        XCTAssertTrue(until(3) { editor.stringValue.contains("| 1 | 2 |") }, editor.stringValue)
        page.buttons["Notes"].click()
        XCTAssertTrue(until(3) { editor.stringValue.contains("# Notes") && !editor.stringValue.contains("## Second") })
        XCTAssertFalse(element("pane.\(card).dirty").exists)
        app.typeText("x")
        XCTAssertTrue(element("pane.\(card).dirty").exists(within: 3))
        keepScreenshot("markdown card, edit")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).dirty").vanishes(within: 5))
        try await send("clear && grep -q '^x# Notes$' notes.md && echo saved-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("saved-42") }
    }

    private func tick(_ card: String, page: XCUIElement, shell: String) async throws {
        let box = page.checkBoxes.firstMatch
        let heading = page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch
        XCTAssertTrue(box.exists(within: 5))
        XCTAssertLessThan(
            abs(box.frame.minX - heading.frame.minX),
            6,
            "the box at \(box.frame), the heading at \(heading.frame)",
        )
        box.click()
        try await send(
            "clear && until grep -q '^- \\[x\\] Ship it$' notes.md; do sleep 0.1; done && echo ticked-$((6*7))\r",
            to: shell,
        )
        try await waitFor(shell) { $0.contains("ticked-42") }
        XCTAssertTrue(until(3) { box.value as? Int == 1 }, "\(box.value ?? "no value")")
        XCTAssertTrue(element("pane.\(card).dirty").vanishes(within: 3))
    }

    private func copyAll(_ page: XCUIElement) {
        keepClipboard()
        NSPasteboard.general.clearContents()
        page.staticTexts.matching(NSPredicate(format: "value == 'Third'")).firstMatch.click()
        app.typeKey("f", modifierFlags: .command)
        let search = page.searchFields.firstMatch
        XCTAssertTrue(search.exists(within: 2) && hasKeyboard(search))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(search.vanishes(within: 2))
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(until(3) {
            let copied = NSPasteboard.general.string(forType: .string) ?? ""
            return copied.hasPrefix("---\ntitle: Hidden") && copied.contains("[Other](other.md)")
        }, NSPasteboard.general.string(forType: .string) ?? "nothing copied")
    }
}
