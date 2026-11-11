import XCTest

/// A remote page while its machine reconnects (ui/states): the page says so once, over its cards.
extension OvviUITests {
    /// Key Host's master gone and Key Host unreachable. While the app finds out why (a link that is down: ssh waits out
    /// its 10 s ConnectTimeout), and then while it shows Reconnecting with ssh's reason, no card says its terminal
    /// stopped, also on a workspace first shown meanwhile (its cards
    /// try to stream and fail). Back once Key Host answers, with no stopped card between. In both looks.
    func testAReconnectingPageShowsItsStateOnce() async throws {
        try await skipWithoutSSH()
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/ssh-hostname", Data("ovvi-key 127.0.0.1".utf8)) }
        let stopped = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pane.' AND identifier "
                + "ENDSWITH '.retry'")).firstMatch
        let reconnecting = element("detail.reconnecting")
        for appearance in ["dark", "light"] {
            relaunch(one, Self.onKeyHost + ["-appearance", appearance])
            XCTAssertTrue(drawn("w1:p2", within: connect), element("pane.w1:p2").stringValue)
            // The link down only once: the light pass goes straight to a name that does not resolve.
            try await hostname(appearance == "dark" ? "192.0.2.1" : "ovvi-key.invalid")
            _ = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
            // The whole time until Reconnecting shows, however long ssh takes to say why.
            var early = false
            XCTAssertTrue(until(connect) {
                early = stopped.exists
                return early || reconnecting.exists
            }, "no Reconnecting")
            XCTAssertFalse(early, "a card says its terminal stopped before Reconnecting")
            XCTAssertFalse(element("detail.reconnecting.detail").stringValue.isEmpty)
            try await hostname("ovvi-key.invalid")
            element("workspace.w2").click()
            XCTAssertFalse(until(6) { stopped.exists }, "a card first shown says its terminal stopped")
            keepScreenshot("reconnecting \(appearance)")
            element("workspace.w1").click()
            try await hostname("127.0.0.1")
            XCTAssertTrue(reconnecting.vanishes(within: 45))
            XCTAssertFalse(until(4) { stopped.exists }, "a card says its terminal stopped once back")
            XCTAssertTrue(drawn("w1:p2", within: connect), element("pane.w1:p2").stringValue)
            keepScreenshot("back \(appearance)")
        }
    }

    /// Key Host's HostName in CI's ~/.ssh/config.
    private func hostname(_ name: String) async throws {
        _ = try await Self.post("\(one)/ssh-hostname", Data("ovvi-key \(name)".utf8))
    }
}
