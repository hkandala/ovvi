import XCTest

extension OvviUITests {
    func testABrowserKeepsAFailedAddressAndTakesClicksOffItsPage() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("browser clicks")
        try await waitForPrompt(left)
        let page = try await writePages(from: left)
        element("tab.\(tab)").click()
        element("terminal.\(left)").click()
        let (browser, label) = try await chooseBrowser(besides: left, in: tab)
        let address = element("browser.\(browser).address")
        let port = Int.random(in: 47100 ... 47900)
        app.typeText("localhost:\(port)\r")
        let message = element("browser.\(browser).message")
        XCTAssertTrue(message.has(\.stringValue, "Nothing answers on localhost:\(port)", within: 5),
                      message.stringValue)
        XCTAssertTrue(element("browser.\(browser).reload").isEnabled)
        // Not over the card's own rename: it would load its address again.
        try await expect("the label follows") { try await paneLabel(browser).contains(" http://localhost:\(port)") }
        try await relabel(browser, "\(label) https://ovvi.invalid/")
        XCTAssertTrue(element("browser.\(browser).open").exists(within: 5), message.stringValue)
        element("browser.\(browser).not-now").click()
        XCTAssertTrue(element("browser.\(browser).empty").exists(within: 3), message.stringValue)
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        element("browser.\(browser).empty").click()
        XCTAssertTrue(hasKeyboard(address))

        app.typeText("\(page)\r")
        XCTAssertTrue(pageText("ovvi-page-one").exists(within: 5))
        address.click()
        app.typeText("localhost:\(port)\r")
        XCTAssertTrue(message.has(\.stringValue, "Nothing answers on localhost:\(port)", within: 5),
                      message.stringValue)
        XCTAssertTrue(until(2) { address.stringValue.hasPrefix("http://localhost:\(port)") }, address.stringValue)
        let failed = address.stringValue
        keepScreenshot("failed address")

        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        message.click()
        // A web view reports no focus of its own.
        let terminal = element("terminal.\(left)")
        XCTAssertTrue(until(2) { !NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: terminal) })
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(address))
        app.typeKey(.escape, modifierFlags: [])

        // Not `python3 -m http.server`: its getfqdn() lookup raised the Local Network prompt on CI.
        try await send("python3 -c 'import functools, http.server as h, socketserver as s; "
            + "t = s.ThreadingTCPServer((\"127.0.0.1\", \(port)), "
            + "functools.partial(h.SimpleHTTPRequestHandler, directory=\"/tmp/ovvi-e2e-browser\")); "
            + "print(\"Serving HTTP\", flush=True); t.serve_forever()'\r", to: left)
        // The first python3 on CI starts slowly (xcrun).
        try await waitFor(left, times: 300) { $0.contains("Serving HTTP") }
        element("browser.\(browser).retry").click()
        XCTAssertTrue(pageText("Directory listing for /").exists(within: 5))
        XCTAssertEqual(address.value as? String, failed)
    }
}

extension OvviUITests {
    /// A web card moved into another tab shows its page there at once: its old tab's page, hidden as the pane left it,
    /// can make one more host for the web view after the new card's took it.
    func testMovedWebCardsShowTheirPagesAtOnce() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (target, shell) = try await newTab("target")
        try await waitForPrompt(shell)
        let page = try await writePages(from: shell), folder = "/tmp/ovvi-e2e-moved"
        try await send("mkdir -p \(folder) && touch \(folder)/ovvi-moved.txt && clear\r", to: shell)
        sendAfter("rm -rf \(folder)\r", to: shell)
        try await waitFor(shell) { !$0.contains("touch") }
        let iid = String(format: "e2%03x", Int.random(in: 0 ..< 4096))
        let browser = try await newCard("ovvi:browser#\(iid)b \(page)", show: false)
        let explorer = try await newCard("ovvi:explorer#\(iid)e /private\(folder)/", cwd: folder, show: false)
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'ovvi-moved.txt'"))
        for ((tab, pane), shown) in [(browser, pageText("ovvi-page-one")), (explorer, file.firstMatch)] {
            // The target's page is kept, hidden, as the card's tab shows.
            try await show(target)
            try await show(tab)
            XCTAssertTrue(shown.exists(within: 10), pane)
            // By keys: a click on the card's menu item moved nothing in 2 of about 45 runs on CI (herdr got no move).
            openPalette()
            app.typeText("move pane to")
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(element("palette.section.beta").exists(within: 2), pane)
            app.typeText("target")
            app.typeKey(.return, modifierFlags: [])
            try await expect("\(pane) right of the target's cards") { try await order(target).last == pane }
            let card = element("pane.\(pane)")
            XCTAssertTrue(until(5) { shown.exists && card.frame.contains(shown.frame) }, "\(pane)'s page in its card")
        }
    }
}

extension OvviUITests {
    /// A local page shows media from a sibling folder and its link to another folder opens in the same card.
    func testALocalPageReadsAndOpensOtherFolders() async throws {
        let (tab, shell) = try await newTab("folders")
        try await waitForPrompt(shell)
        let folder = "/tmp/ovvi-e2e-folders"
        try await send("""
        mkdir -p \(folder)/page \(folder)/media \(folder)/other && printf '<svg \
        xmlns="http://www.w3.org/2000/svg" width="8" height="8"/>' >\(folder)/media/dot.svg && printf '<p \
        id="s">ovvi-waiting</p><img src="../media/dot.svg" onload="s.textContent=\\x27ovvi-media-loaded\\x27" \
        onerror="s.textContent=\\x27ovvi-media-blocked\\x27"><a href="../other/page.html">Other</a>' \
        >\(folder)/page/index.html && printf '<p>ovvi-other-folder</p>' >\(folder)/other/page.html && clear\r
        """, to: shell)
        sendAfter("rm -rf \(folder)\r", to: shell)
        try await waitFor(shell) { !$0.contains("printf") }
        let pane = try await split(shell)
        try await relabel(pane, "ovvi:browser#e2efld file://\(folder)/page/index.html")
        element("tab.\(tab)").click()
        let tabs = try await tabIDs()
        XCTAssertTrue(pageText("ovvi-media-loaded").exists(within: 10))
        app.webViews.links["Other"].click()
        XCTAssertTrue(pageText("ovvi-other-folder").exists(within: 5))
        let address = element("browser.\(pane).address")
        XCTAssertTrue(until(2) { address.stringValue.hasSuffix("/other/page.html") }, address.stringValue)
        let after = try await tabIDs()
        XCTAssertEqual(after, tabs)
    }
}
