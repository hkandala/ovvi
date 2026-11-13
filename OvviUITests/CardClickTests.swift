import XCTest

extension OvviUITests {
    /// A click gives a card the keyboard wherever it lands: on a view that takes no keys (a plugin's error, a missing
    /// plugin, a header button) as on a terminal, a web page, a field or a chat.
    func testAClickAnywhereOnACardGivesItTheKeyboard() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("clicks")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-clicks", root = "/private/tmp/ovvi-e2e-clicks"
        let packages = #"{"packages":["\#(Self.fixtures)/plugin-api"]}"#
        try await send("rm -rf \(config) && mkdir -p \(config) && echo '\(packages)' > \(config)/settings.json && "
            + "echo '[\"plugin-api\"]' > \(config)/trust.json && printf '<p>ovvi-click-page</p>' > \(config)/page.html "
            + "&& clear && echo made-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
        sendAfter("rm -rf \(config) ~/.local/state/ovvi/\(one)/plugin-api\r", to: shell)
        relaunch(one, ["-configFolder", config, "-recordMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()

        try await show(tab)
        let browser = try await split(shell), plugin = try await split(browser, "down")
        let failing = try await split(plugin, "down"), missing = try await split(shell, "down")
        // Drawn as a terminal first, as when the tab shows: its card keeps that terminal after the relabel.
        XCTAssertTrue(element("terminal.\(missing)").exists(within: 5))
        try await relabel(browser, "ovvi:browser#e2ecbr file://\(root)/page.html")
        try await relabel(plugin, "ovvi:plugin-api#e2ecpg \(root)/plain/")
        try await relabel(failing, "ovvi:plugin-api#e2ecfl \(root)/fail/")
        try await relabel(missing, "ovvi:ovvi-e2e-gone#e2ecms \(root)")
        try await show(tab)
        let error = element("pane.\(failing).failure")
        XCTAssertTrue(error.has(\.stringValue, "Plugin API stopped", within: 10))
        // A card too short for its error shows it compact under its two header rows (70 pt), never over them: at
        // least the compact error's padding (12) and symbol (20) above its title stay below the header.
        let header = element("pane.\(failing)").frame.minY + 70
        XCTAssertGreaterThan(error.frame.minY, header + 12 + 20, "\(error.frame) under a header to \(header)")
        let page = pageText("ovvi-click-page"), plain = text("ovvi-plain-page")
        XCTAssertTrue(page.exists(within: 10) && plain.exists(within: 10))
        let gone = element("pane.\(missing).missing")
        XCTAssertTrue(gone.exists(within: 5))
        keepScreenshot("cards to click")
        for (card, view) in [(failing, error), (missing, gone), (browser, page), (plugin, plain)] {
            element("terminal.\(shell)").click()
            XCTAssertTrue(hasKeyboard("terminal.\(shell)"), "the keyboard is on \(keyboardOwner())")
            view.click()
            // XCUITest sees no focus in a web view: the card's border, and the terminal lost the keys.
            XCTAssertTrue(element("pane.\(card).border").exists(within: 2), "\(card) is not lit")
            XCTAssertTrue(lostKeyboard(shell), "the keyboard stayed on \(shell)")
            if card == failing {
                keepScreenshot("the plugin's error, clicked")
            }
        }

        try await keepsAFieldsKeys(shell, browser: browser, plugin: plugin)
        try await chatTakesTheKeys()
    }

    private func keepsAFieldsKeys(_ shell: String, browser: String, plugin: String) async throws {
        // The keys stay in a field the click went to: the card's own view takes them only when no view did.
        element("terminal.\(shell)").click()
        let address = element("browser.\(browser).address")
        address.click()
        XCTAssertTrue(hasKeyboard(address), "the keyboard is on \(keyboardOwner())")
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertFalse(until(1) { !focused.evaluate(with: address) }, "the page took the keys from its address")
        XCTAssertTrue(element("pane.\(browser).border").exists(within: 2), "\(browser) is not lit")
        element("terminal.\(shell)").click()
        element("pane.\(plugin).again").click()
        XCTAssertTrue(element("pane.\(plugin).border").exists(within: 2), "\(plugin) is not lit")
        XCTAssertTrue(lostKeyboard(shell), "the keyboard stayed on \(shell)")
    }

    private func chatTakesTheKeys() async throws {
        let chat = try await startChat().pane
        try await say("hello", in: chat)
        let reply = row(chat, "reply", "Echo: **hello**")
        XCTAssertTrue(reply.exists(within: 5))
        let beside = try await split(chat)
        try await waitForPrompt(beside)
        element("terminal.\(beside)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(beside)"), "the keyboard is on \(keyboardOwner())")
        reply.click()
        XCTAssertTrue(hasKeyboard(element("chat.\(chat).composer")), "the keyboard is on \(keyboardOwner())")
        // A drag that starts on an inactive chat selects its text: the reply box takes no keys from the selection.
        element("terminal.\(beside)").click()
        keepClipboard()
        NSPasteboard.general.clearContents()
        let start = reply.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        start.withOffset(CGVector(dx: 1, dy: 0)).click(forDuration: 0.2,
                                                       thenDragTo: start.withOffset(CGVector(dx: 30, dy: 0)))
        app.typeKey("c", modifierFlags: .command)
        let copied = { NSPasteboard.general.string(forType: .string) ?? "" }
        XCTAssertTrue(until(2) { copied().hasPrefix("Ech") }, "copied '\(copied())'")
    }

    private func lostKeyboard(_ pane: String) -> Bool {
        let focused = NSPredicate(format: "hasKeyboardFocus == true"), terminal = element("terminal.\(pane)")
        return until(2) { !focused.evaluate(with: terminal) }
    }
}
