import XCTest

/// The test pages are files a shell of the session writes: the runner is sandboxed.
extension OvviUITests {
    func writePages(from pane: String, in session: String? = nil) async throws -> String {
        let folder = "/tmp/ovvi-e2e-browser"
        try await send("""
        mkdir -p \(folder) && printf '<title>One</title><link rel="icon" href="data:image/svg+xml,<svg \
        xmlns=%%22http://www.w3.org/2000/svg%%22 \
        viewBox=%%220 0 16 16%%22><rect width=%%2216%%22 height=%%2216%%22/></svg>"> \
        <p>ovvi-page-one</p><a href="two.html">Two</a> <a href="two.html" target="_blank">Blank</a> \
        <button onclick="window.open(\\x27pop.html\\x27)">Pop</button>' >\(folder)/one.html && \
        printf '<title>Two</title><p>ovvi-page-two</p>' >\(folder)/two.html && \
        printf '<p>ovvi-pop</p><button onclick="window.close()">Done</button>' >\(folder)/pop.html && clear\r
        """, to: pane, in: session)
        try await waitFor(pane, in: session) { !$0.contains("printf") }
        return "file://\(folder)/one.html"
    }

    func pageText(_ text: String) -> XCUIElement {
        app.webViews.staticTexts.matching(NSPredicate(format: "value == %@", text)).firstMatch
    }

    /// A short marker, not the file: a narrow pane wraps the JSON (CI's screen), and the typed command holds no "42".
    func expectSaved(_ text: String, iid: String, shell: String, in session: String? = nil) async throws {
        let path = "~/.local/state/ovvi/\(session ?? one)/browser/\(iid).json"
        try await poll("\(text) in \(path)") { () async throws -> Bool? in
            try await send("clear; grep -q \(text) \(path) && echo saved-$((6*7))\r", to: shell, in: session)
            try await Task.sleep(for: .milliseconds(200))
            return try await read(shell, in: session).contains("saved-42") ? true : nil
        }
    }

    func chooseBrowser(besides left: String, in tab: String) async throws -> (pane: String, label: String) {
        app.typeKey("d", modifierFlags: .command)
        let chooser = try await replaced(left, in: tab, besides: [left])
        XCTAssertTrue(element("pane.\(chooser).chooser.browser").exists(within: 3))
        app.typeKey("3", modifierFlags: [])
        let browser = try await replaced(chooser, in: tab, besides: [left])
        let label = try await paneLabel(browser)
        XCTAssertTrue(label.hasPrefix("ovvi:browser#") && !label.contains(" "), label)
        XCTAssertTrue(hasKeyboard(element("browser.\(browser).address")))
        return (browser, label)
    }

    func testBrowserFromTheChooserLoadsATypedAddressAndKeepsItsPage() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("browser")
        try await waitForPrompt(left)
        let page = try await writePages(from: left)
        element("tab.\(tab)").click()
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        let (browser, made) = try await chooseBrowser(besides: left, in: tab)
        try await waitFor(browser) { $0.contains("Browser") && $0.contains("Shown in Ovvi") }
        XCTAssertTrue(element("browser.\(browser).empty").exists)
        keepScreenshot("browser card, empty")

        app.typeText(page)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: 5))
        XCTAssertTrue(element("browser.\(browser).icon").has(\.stringValue, "page", within: 5))
        try await expect("the typed address in the label") { try await paneLabel(browser) == "\(made) \(page)" }
        let short = page.replacing("file://", with: "")
        try await waitFor(browser) { $0.contains(short) && !$0.contains("file:") }
        keepScreenshot("browser card")
        app.webViews.buttons["Pop"].click()
        let popup = element("browser.\(browser).popup")
        // Over the accessibility timeout (6 s).
        XCTAssertTrue(popup.exists(within: 10))
        popup.buttons["Done"].click()
        XCTAssertTrue(popup.vanishes(within: 3))
        app.webViews.links["Two"].click()
        XCTAssertTrue(pageText("ovvi-page-two").exists(within: 5))
        XCTAssertTrue(element("browser.\(browser).back").isEnabled)

        showInspector(browser)

        try await expectSaved("two.html", iid: String(made.dropFirst("ovvi:browser#".count)), shell: left)
        relaunch()
        element("workspace.w2").click()
        element("tab.\(tab)").click()
        XCTAssertTrue(pageText("ovvi-page-two").exists(within: connect))
        let kept = try await paneLabel(browser)
        XCTAssertEqual(kept, "\(made) \(page)")
        let address = element("browser.\(browser).address")
        address.click()
        XCTAssertTrue(hasKeyboard(address))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("browser.\(browser).back").has(\.isEnabled, true, within: 3))
        element("browser.\(browser).back").click()
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: 5))
        address.click()
        app.typeText("ovvi words")
        app.typeKey(.return, modifierFlags: [])
        let search = "\(made) https://www.google.com/search?q=ovvi%20words"
        try await expect("a Google search in the label") { try await paneLabel(browser) == search }

        try await openBrowserHere(on: left, in: tab, besides: browser)
    }

    func testLinksOpenInNewTabsAndPopupsClose() async throws {
        let (tab, shell) = try await newTab("links")
        try await waitForPrompt(shell)
        let page = try await writePages(from: shell)
        let pane = try await split(shell)
        try await relabel(pane, "ovvi:browser#e2e1ab \(page)")
        element("tab.\(tab)").click()
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: 5))
        let two = page.replacing("one.html", with: "two.html")
        var tabs = try await tabIDs()
        func expectTab(_ how: String) async throws {
            let new = try await newTabID(after: tabs)
            closeAfter("tab", new)
            tabs.append(new)
            let pane = try await self.pane(of: new)
            try await expect("\(how): two.html in \(new)") {
                let label = try await paneLabel(pane)
                return label.hasPrefix("ovvi:browser#") && label.hasSuffix(" \(two)")
            }
            try await expectBeside(new, tab)
            XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected || !pageText("ovvi-page-one").exists }, how)
        }

        app.webViews.links["Two"].rightClick()
        let menu = app.windows.firstMatch.menuItems
        XCTAssertTrue(menu["Open Link in New Tab"].exists(within: 2))
        XCTAssertTrue(menu["Open Link to the Side"].exists)
        XCTAssertFalse(menu["Open Link in New Window"].exists)
        XCTAssertFalse(menu["Download Linked File"].exists)
        keepScreenshot("page menu")
        menu["Open Link in New Tab"].click()
        try await expectTab("the menu")
        XCUIElement.perform(withKeyModifiers: .command) { app.webViews.links["Two"].click() }
        try await expectTab("⌘-click")
        app.webViews.links["Blank"].click()
        try await expectTab("target=_blank")

        // Over 6 s: an accessibility query that reaches the popup's web view as it starts can wait out the
        // accessibility timeout (6 s; CI took 6.1 s), and the popup draws only after it.
        let popup = element("browser.\(pane).popup")
        app.webViews.buttons["Pop"].click()
        XCTAssertTrue(popup.exists(within: 10))
        keepScreenshot("popup")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(popup.vanishes(within: 3))
        app.webViews.buttons["Pop"].click()
        XCTAssertTrue(popup.exists(within: 10))
        element("browser.\(pane).card").buttons["Close"].click()
        XCTAssertTrue(popup.vanishes(within: 3))
        try await openBeside(in: tab, besides: [pane, shell], two)
    }

    private func openBeside(in tab: String, besides panes: [String], _ two: String) async throws {
        XCUIElement.perform(withKeyModifiers: .option) { app.webViews.links["Two"].click() }
        let side = try await sidePane(in: tab, besides: panes)
        try await expect("two.html beside the card") { try await paneLabel(side).hasSuffix(" \(two)") }
        XCTAssertTrue(pageText("ovvi-page-one").exists)
    }

    func showInspector(_ browser: String) {
        let web = element("browser.\(browser)"), height = web.frame.height, top = web.frame.minY
        let window = app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Web Inspector'")).firstMatch
        element("browser.\(browser).inspector").click()
        // WebKit docks it only in a card tall enough, else it opens its own window (CI's small screen).
        XCTAssertTrue(until(5) { web.frame.height < height * 0.8 && abs(web.frame.minY - top) < 1 || window.exists })
        keepScreenshot("web inspector")
        if window.exists {
            window.buttons[XCUIIdentifierCloseWindow].click()
        } else {
            let card = element("browser.\(browser).card"), before = card.frame.width
            let inset = before - web.frame.width
            element("titlebar.sidebar").click()
            XCTAssertTrue(until(3) {
                card.frame.width > before && abs(card.frame.width - web.frame.width - inset) < 1
                    && web.frame.height < card.frame.height * 0.8 && abs(web.frame.minY - top) < 1
            }, "\(web.frame) in \(card.frame)")
            element("titlebar.sidebar").click()
        }
    }

    func openBrowserHere(on left: String, in tab: String, besides browser: String) async throws {
        element("terminal.\(left)").click()
        openPalette()
        app.typeText("open browser here")
        XCTAssertTrue(element("palette.command.Open Browser Here").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        let other = try await replaced(left, in: tab, besides: [browser])
        let otherLabel = try await paneLabel(other)
        XCTAssertTrue(otherLabel.hasPrefix("ovvi:browser#"), otherLabel)
        XCTAssertTrue(hasKeyboard("browser.\(other).address"), "the keyboard is on \(keyboardOwner())")
        openPalette()
        app.typeText("here")
        XCTAssertTrue(element("palette.command.Open Terminal Here").exists(within: 2))
        XCTAssertFalse(element("palette.command.Open Browser Here").exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(hasKeyboard("browser.\(other).address"), "the keyboard is on \(keyboardOwner())")
        app.typeKey("r", modifierFlags: [.command, .shift])
        let shell = try await replaced(other, in: tab, besides: [browser])
        XCTAssertTrue(element("pane.\(shell).chooser.terminal").exists(within: 3))
        let shellLabel = try await paneLabel(shell)
        XCTAssertEqual(shellLabel, "")
    }

    func testAPaneLabeledInHerdrShowsItsPageAfterARestart() async throws {
        let (_, shell) = try await shown(running(five))
        try await waitForPrompt(shell, in: five)
        let page = try await writePages(from: shell, in: five)
        let pane = try await split(shell, in: five)
        closeAfter("pane", pane, in: five)
        try await Self.call(five, "pane.rename", ["pane_id": pane, "label": "ovvi:browser#e2e5ab \(page)"])
        // `.invalid`: approvals live in the defaults the tests share with the user's Ovvi.
        let site = try await split(pane, "down", in: five)
        closeAfter("pane", site, in: five)
        try await Self.call(
            five,
            "pane.rename",
            ["pane_id": site, "label": "ovvi:browser#e2e5ac https://ovvi.invalid/"],
        )
        let tab = try await tabOf(pane, in: five)
        relaunch(five, ["-appearance", "light"])
        XCTAssertTrue(element("browser.\(site).open").exists(within: connect))
        keepScreenshot("open this page, light")
        relaunch(five, ["-appearance", "dark"])
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: connect))
        XCTAssertTrue(element("browser.\(site).open").exists(within: 3))
        XCTAssertEqual(element("browser.\(site).message").value as? String, "ovvi.invalid/")
        keepScreenshot("open this page, dark")
        element("browser.\(site).not-now").click()
        XCTAssertTrue(element("browser.\(site).empty").exists(within: 3))
        XCTAssertFalse(element("browser.\(site).open").exists)
        pageText("ovvi-page-one").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.label, "Browser One", within: 3))
        XCTAssertTrue(twoRows(pane, title: "One", above: "browser.\(pane).address"))
        let back = element("browser.\(pane).back").frame
        XCTAssertEqual(element("browser.\(pane)").frame.minY - back.maxY, 11, accuracy: 1, "\(back)")
        // A rename sends no herdr event: the metadata token makes Ovvi read the layout again.
        let two = page.replacing("one.html", with: "two.html")
        try await relabel(pane, "ovvi:browser#e2e5ab \(two)", in: five)
        XCTAssertTrue(pageText("ovvi-page-two").exists(within: 5))
        XCTAssertTrue(element("browser.\(pane).back").has(\.isEnabled, true, within: 3))
        XCTAssertTrue(element("tab.\(tab)").has(\.label, "Browser Two", within: 3))
        floatAndBack(pane)
        XCTAssertTrue(pageText("ovvi-page-two").exists(within: 3))
        try await expectSaved("two.html", iid: "e2e5ab", shell: shell, in: five)

        try await Self.post("\(five)/stop")
        XCTAssertTrue(element("detail.start").exists(within: 10))
        try await Self.post("\(five)/start")
        XCTAssertTrue(pageText("ovvi-page-two").exists(within: 15))
    }

    func twoRows(_ pane: String, title: String? = nil, above control: String) -> Bool {
        let row1 = element("pane.\(pane).title")
        return title.map { row1.stringValue == $0 } != false && element(control).frame.minY >= row1.frame.maxY
    }
}

extension OvviUITests {
    func testADroppedBrowserKeepsItsPictureAndComesBack() async throws {
        relaunch(one, ["-spareWebCards", "0"])
        let (tab, pane) = try await newTab("dropped")
        try await waitForPrompt(pane)
        let folder = "/tmp/ovvi-e2e-dropped"
        try await send("mkdir -p \(folder) && printf '<script>document.title = \\x27Light \\x27 + Date.now()</script>' "
            + ">\(folder)/light.html && clear\r", to: pane)
        try await waitFor(pane) { !$0.contains("printf") }
        let iid = String(format: "e2e%03x", Int.random(in: 0 ..< 4096)), title = element("pane.\(pane).title")
        try await Self.call(
            one,
            "pane.rename",
            ["pane_id": pane, "label": "ovvi:browser#\(iid) file://\(folder)/light.html"],
        )
        try await show(tab)
        XCTAssertTrue(until(connect) { title.stringValue.hasPrefix("Light ") }, title.stringValue)
        let first = title.stringValue
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, false, within: 3))
        app.typeKey("o", modifierFlags: [.command, .control])
        let tile = element("overview.card.\(pane)")
        XCTAssertTrue(tile.has(\.stringValue, "browser", within: 3), tile.stringValue)
        scrollOverview(to: tile, whole: true)
        XCTAssertGreaterThan(mean(tile), 150, "the dropped page's picture")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        try await show(tab)
        XCTAssertTrue(until(connect) { title.stringValue.hasPrefix("Light ") && title.stringValue != first },
                      "\(first) then \(title.stringValue)")
    }
}

extension OvviUITests {
    func testEachOpenInANewTabShowsItsOwnPage() async throws {
        let (_, shell) = try await newTab("opens")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-opens", names = ["one.txt", "two.txt", "three.txt", "four.txt", "five.txt"]
        try await send("rm -rf \(repo) && mkdir -p \(repo) && cd \(repo) && touch \(names.joined(separator: " ")) "
            + "&& clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let tab = try await newCard("ovvi:explorer#e2eops /private\(repo)/", cwd: repo, show: false).tab
        for name in names {
            try await show(tab)
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(row.exists(within: 10), name)
            let before = try await tabIDs()
            XCUIElement.perform(withKeyModifiers: .command) { row.click() }
            let opened = try await newTabID(after: before)
            closeAfter("tab", opened)
            XCTAssertTrue(element("tab.\(opened)").exists(within: 5), name)
            XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected }, name)
            try await show(opened)
            XCTAssertTrue(element("page.\(opened)").has(\.isHittable, true, within: 5), name)
        }
        try await send("rm -rf \(repo)\r", to: shell)
    }
}
