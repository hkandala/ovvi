import XCTest

/// A remote page while its machine reconnects (ui/states): the page says so once, over its cards.
extension OvviUITests {
    /// Key Host unreachable (its name does not resolve, as with no network) after its master went: Reconnecting with
    /// ssh's reason, and no card that says its terminal stopped, also on a workspace first shown meanwhile (its cards
    /// try to stream and fail). Back once the name resolves, with no stopped card between. In both looks.
    func testAReconnectingPageShowsItsStateOnce() async throws {
        try await skipWithoutSSH()
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/ssh-resolve", Data("ovvi-key".utf8)) }
        for appearance in ["dark", "light"] {
            relaunch(one, Self.onKeyHost + ["-appearance", appearance])
            XCTAssertTrue(drawn("w1:p2", within: connect), element("pane.w1:p2").stringValue)
            _ = try await Self.post("\(one)/ssh-unresolve", Data("ovvi-key".utf8))
            _ = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
            let reconnecting = element("detail.reconnecting")
            XCTAssertTrue(reconnecting.exists(within: connect))
            XCTAssertTrue(until(connect) { (element("detail.reconnecting.detail").value as? String ?? "")
                    .contains("Could not resolve hostname")
            })
            let stopped = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pane.' AND identifier "
                    + "ENDSWITH '.retry'")).firstMatch
            XCTAssertFalse(until(4) { stopped.exists }, "a card says its terminal stopped")
            element("workspace.w2").click()
            XCTAssertFalse(until(8) { stopped.exists }, "a card first shown says its terminal stopped")
            keepScreenshot("reconnecting \(appearance)")
            element("workspace.w1").click()
            _ = try await Self.post("\(one)/ssh-resolve", Data("ovvi-key".utf8))
            XCTAssertTrue(reconnecting.vanishes(within: connect))
            XCTAssertFalse(until(6) { stopped.exists }, "a card says its terminal stopped once back")
            XCTAssertTrue(drawn("w1:p2", within: connect), element("pane.w1:p2").stringValue)
            keepScreenshot("back \(appearance)")
        }
    }
}
