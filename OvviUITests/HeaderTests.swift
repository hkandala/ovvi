import XCTest

extension OvviUITests {
    func testAPluginsHeaderDrawsItsManifestsControls() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("header")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-header"
        try await send(fixture(in: config) + "\r", to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
        relaunch(one, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        let card = try await newCard("ovvi:fixture#e2ehdr /tmp/notes.md").pane

        let control = { (id: String) in self.element("pane.\(card).\(id)") }
        XCTAssertTrue(control("root").exists(within: 5))
        XCTAssertEqual(control("root").value as? String, "ovvi")
        XCTAssertFalse(control("go-back").isEnabled)
        XCTAssertEqual(control("jump").value as? String, "Sources › App.swift › body")
        XCTAssertEqual(control("push").label, "Push, 2")
        XCTAssertTrue(control("open-with").exists)
        XCTAssertFalse(control("gone").exists)
        let page = element("fixture.\(card).card").frame
        XCTAssertEqual(control("go-back").frame.minX - page.minX, 1, accuracy: 1, "\(page)")
        // Past its prompt's own width (about 70 pt), with the room of a card on CI's 1024 pt screen without the
        // sidebar: beside a 300 pt sidebar the row's other controls leave the field about 55 pt.
        element("titlebar.sidebar").click()
        XCTAssertTrue(until(2) { control("filter").frame.width > 100 }, "\(control("filter").frame)")
        XCTAssertEqual(control("mode.read").frame.minX - control("rows").frame.maxX, 6 + 2, accuracy: 1)
        XCTAssertEqual(control("push").frame.minX, control("outline").frame.maxX, accuracy: 0.5)
        keepScreenshot("plugin header")

        XCTAssertTrue(control("outline").isSelected)
        control("outline").click()
        XCTAssertTrue(control("outline").has(\.isSelected, false, within: 2))
        control("mode.edit").click()
        XCTAssertTrue(control("mode.edit").has(\.isSelected, true, within: 2))
        control("root").click()
        for item in ["Places", "tmp", "Choose…"] {
            XCTAssertTrue(control("root").menuItems[item].exists(within: 2), item)
        }
        control("root").menuItems["tmp"].click()
        XCTAssertTrue(control("root").menuItems["tmp"].vanishes(within: 2))
        XCTAssertFalse(until(0.5) { control("root").stringValue != "ovvi" }, control("root").stringValue)

        floatsTheSameRow(card)

        let bare = try await newCard("ovvi:bare#e2ebar /tmp").pane
        XCTAssertTrue(element("bare.\(bare).card").exists(within: 5))
        XCTAssertLessThan(element("bare.\(bare).card").frame.minY - element("pane.\(bare)").frame.minY, 50)
        try await send("rm -rf \(config) /tmp/notes.md\r", to: shell)
    }

    private func floatsTheSameRow(_ card: String) {
        let window = float(card)
        let floating = { (id: String) in self.element("pane.\(card).\(id)", in: window) }
        XCTAssertTrue(floating("mode.edit").has(\.isSelected, true, within: 3))
        XCTAssertFalse(floating("outline").isSelected)
        let content = element("fixture.\(card).card", in: window).frame
        XCTAssertEqual(floating("go-back").frame.minX - content.minX, 1, accuracy: 1, "\(content)")
        let surface = element("float.\(card)", in: window).frame
        let back = floating("go-back").frame
        XCTAssertEqual(back.minY - surface.minY, back.minX - surface.minX, accuracy: 0.5, "\(back) in \(surface)")
        XCTAssertEqual(content.minY - surface.minY, 4 + 36, accuracy: 1, "\(content) in \(surface)")
        keepScreen("plugin header floating")
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.vanishes(within: 3))
    }

    private func fixture(in config: String) -> String {
        let header = [
            #"{"id":"root","type":"menu","symbol":"folder","title":"ovvi","items":[{"title":"Places"},"#
                + #"{"value":"/tmp","title":"tmp","symbol":"folder"},"-",{"value":"choose","title":"Choose…"}]}"#,
            #"{"id":"filter","type":"field","placeholder":"Filter"}"#,
            #"{"id":"jump","type":"text","style":"path","symbol":"curlybraces","#
                + #""value":["Sources","App.swift","body"]}"#,
            #"{"id":"rows","type":"text","style":"dim","digits":"mono","value":"3 of 12"}"#,
            #"{"id":"mode","type":"segmented","options":[{"value":"read","title":"Read"},"#
                + #"{"value":"edit","title":"Edit"}],"value":"read"}"#,
            #"{"id":"outline","type":"toggle","symbol":"sidebar.left","title":"Outline","value":true}"#,
            #"{"id":"push","type":"button","symbol":"arrow.up","title":"Push","badge":"2","gap":0}"#,
            #"{"id":"gone","type":"button","symbol":"trash","title":"Gone","hidden":true}"#,
            #"{"id":"open-with","type":"openWith","value":"/tmp/notes.md"}"#,
        ].joined(separator: ",")
        let json = #"{"version":"1.0.0","ovvi":{"id":"fixture","name":"Fixture","api":1,"entry":"main.js","#
            + #""icon":"testtube.2","history":true,"header":[\#(header)]}}"#
        let bare = #"{"version":"1.0.0","ovvi":{"id":"bare","name":"Bare","api":1,"entry":"main.js","icon":"leaf"}}"#
        return "rm -rf \(config) && mkdir -p \(config)/plugins/fixture \(config)/plugins/bare && touch /tmp/notes.md"
            + " && echo '\(json)' > \(config)/plugins/fixture/package.json"
            + " && echo '\(bare)' > \(config)/plugins/bare/package.json && clear && echo made-$((6*7))"
    }
}
