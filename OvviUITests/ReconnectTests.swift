import XCTest

/// A remote page while its machine reconnects (ui/states): the page says so once, in a capsule at the page's bottom.
extension OvviUITests {
    /// Key Host's master gone and Key Host unreachable. While the app finds out why (a link that is down: ssh waits out
    /// its 10 s ConnectTimeout), and then while it shows Reconnecting with ssh's reason, no card says its terminal
    /// stopped, also on a workspace first shown meanwhile (its cards
    /// try to stream and fail). Back once Key Host answers, with no stopped card between. In both looks.
    func testAReconnectingPageShowsItsStateOnce() async throws {
        try await skipWithoutSSH()
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/ssh-hostname", Data("ovvi-key 127.0.0.1".utf8)) }
        for appearance in ["dark", "light"] {
            relaunch(one, Self.onKeyHost + ["-appearance", appearance])
            let stopped = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pane.' AND identifier "
                    + "ENDSWITH '.retry'")).firstMatch
            let reconnecting = element("detail.reconnecting")
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
            XCTAssertFalse(reconnecting.descendants(matching: .any)["notice.detail"].stringValue.isEmpty)
            XCTAssertFalse(element("detail.reconnecting.detail").exists, "the centered loader over the cards")
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

    /// A tab kept out of view while Key Host's master drops: its stream ends with the connection. Shown once the page
    /// is back, while herdr holds its new stream (paused, as a slow link would), it loads and never says its terminal
    /// stopped. In both looks.
    func testAKeptTabShownAfterADropNeverSaysStopped() async throws {
        try await skipWithoutSSH()
        // Once for both looks: two more a look overflowed CI's tab bar.
        let (kept, pane) = try await createTab(in: "w2", label: "kept")
        closeAfter("tab", kept)
        let (other, shown) = try await createTab(in: "w2", label: "other")
        closeAfter("tab", other)
        let found = try await order(of: kept)
        let index = try XCTUnwrap(found)
        for appearance in ["dark", "light"] {
            relaunch(one, Self.onKeyHost + ["-appearance", appearance])
            let stopped = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pane.' AND identifier "
                    + "ENDSWITH '.retry'")).firstMatch
            XCTAssertTrue(element("workspace.w2").exists(within: connect))
            element("workspace.w2").click()
            try await show(kept)
            XCTAssertTrue(drawn(pane, within: connect), element("pane.\(pane)").stringValue)
            try await show(other)
            XCTAssertTrue(drawn(shown, within: connect), element("pane.\(shown)").stringValue)
            let (terminal, back) = try await (terminalID(pane), terminalID(shown))

            _ = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
            try await expect("the shown tab to stream again", times: 300) {
                try await streams(one).contains { $0.contains(back) }
            }
            let ended = try await streams(one).allSatisfy { !$0.contains(terminal) }
            XCTAssertTrue(ended, "the kept tab's stream outlived the drop")
            // Asserted after the strip, so that a failing run still takes the strip's screenshots.
            let early = stopped.exists

            // After the tabs' own: their closes call herdr.
            addTeardownBlock { [one] in _ = try? await Self.post("\(one)/resume") }
            _ = try await Self.post("\(one)/pause")
            app.typeKey("\(index + 1)", modifierFlags: .command)
            XCTAssertTrue(element("tab.\(kept)").has(\.isSelected, true, within: 3))
            // A strip while herdr holds the stream, about 2 s.
            var said = false
            for shot in 1 ... 5 {
                said = said || stopped.exists
                keepScreenshot("kept tab opening \(appearance) \(shot)")
            }
            _ = try await Self.post("\(one)/resume")
            XCTAssertFalse(early, "a card says its terminal stopped once back")
            XCTAssertFalse(said, "the kept tab says its terminal stopped as it opens")
            XCTAssertFalse(until(3) { stopped.exists }, "the kept tab says its terminal stopped")
            XCTAssertTrue(drawn(pane, within: connect), element("pane.\(pane)").stringValue)
            try await expect("the kept tab to stream") { try await streams(one).contains { $0.contains(terminal) } }
            keepScreenshot("kept tab back \(appearance)")
        }
    }

    /// Key Host's HostName in CI's ~/.ssh/config.
    private func hostname(_ name: String) async throws {
        _ = try await Self.post("\(one)/ssh-hostname", Data("ovvi-key \(name)".utf8))
    }
}
