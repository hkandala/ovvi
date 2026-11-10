import XCTest

extension OvviUITests {
    func testHoverCardShowsABlockedAgentsScreenAndEscClosesIt() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("deploy")
        try await split(split(pane))
        try await send("echo hover-$((6*7)); echo waiting\r", to: pane)
        try await waitFor(pane) { $0.contains("\nhover-42") }
        try await report(pane, "blocked", agent: "claude")
        try await waitForValue("tab.\(tab)", containing: "claude, needs you")

        element("tab.\(tab)").hover()
        let card = element("hovercard")
        XCTAssertTrue(card.exists(within: 2))
        XCTAssertEqual(rows(of: card).count, 3)
        try await waitForValue("hovercard.\(pane)", containing: "hover-42")
        XCTAssertTrue((element("hovercard.\(pane)").value as? String)?.hasPrefix("Needs you") == true)
        XCTAssertEqual(element("hovercard.\(pane).state").stringValue, "Needs you")
        let states = card.descendants(matching: .any).matching(NSPredicate(format: "identifier ENDSWITH '.state'"))
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(card.frame.midX, element("tab.\(tab)").frame.midX, accuracy: 2)
        XCTAssertEqual(card.frame.minY - element("tab.\(tab)").frame.maxY, 12, accuracy: 1.5)
        keepScreenshot("hover card")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(card.vanishes(within: 2))
    }

    func testHoverCardRowGoesToItsPane() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("peek")
        let second = try await split(pane)
        XCTAssertFalse(element("tab.\(tab)").isSelected)

        element("tab.\(tab)").hover()
        let card = element("hovercard")
        XCTAssertTrue(card.exists(within: 2))
        XCTAssertEqual(rows(of: card).count, 2)
        element("hovercard.\(second)").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard("terminal.\(second)"))
        XCTAssertTrue(card.vanishes(within: 2))

        element("tab.\(tab)").hover()
        XCTAssertTrue(card.exists(within: 2))
        element("workspace.w1").hover()
        XCTAssertTrue(card.vanishes(within: 2))
    }

    func testAPluginPanesRowNamesThePlugin() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        let (tab, pane) = try await newCard("ovvi:explorer#e2ehov /tmp/")
        element("tab.\(tab)").hover()
        XCTAssertTrue(element("hovercard").exists(within: 3))
        let row = element("hovercard.\(pane)")
        XCTAssertTrue(row.exists(within: 2))
        XCTAssertTrue(row.label.hasPrefix("File Explorer, "), row.label)
        XCTAssertFalse(row.label.contains("cat"), row.label)
        keepScreenshot("plugin pane's hover card")
        element("workspace.w1").hover()
    }

    func testAgentsRowShowsItsTabsCard() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let (tab, pane) = try await newTab("build")
        try await split(pane)
        element("workspace.w1").click()
        try await report(pane, "working")
        unfold("w2")
        let row = element("agent.\(pane)")
        XCTAssertTrue(row.exists(within: 3))

        row.hover()
        let card = element("hovercard")
        XCTAssertTrue(card.exists(within: 2))
        XCTAssertEqual(rows(of: card).count, 2)
        XCTAssertEqual(card.label, "Panes of build")
        XCTAssertEqual(card.frame.minY, row.frame.minY, accuracy: 1.5)
        XCTAssertEqual(card.frame.minX - element("sidebar").frame.maxX, 6, accuracy: 1.5)
        element("hovercard.title").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(card.vanishes(within: 2))
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 2))
    }

    /// On a Mac Liquid Glass alone lets the text behind read clearly; CI's VM draws glass with no backdrop, so on CI
    /// this guards only against a see-through panel.
    func testHoverCardBlursTheTextBehindIt() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("busy")
        element("tab.\(tab)").click()
        let line = String(repeating: "@#W", count: 60)
        try await send("clear; yes '\(line)' | head -300\r", to: pane)
        try await waitFor(pane) { $0.components(separatedBy: "@#W@#W@#W").count > 50 }
        pick("Interface Style", "Glass")
        addTeardownBlock { @MainActor [self] in
            pick("Interface Style", "Glass")
            pick("Appearance", "Dark")
        }
        let card = element("hovercard")
        for (menu, item, look) in [("Appearance", "Dark", "glass dark"), ("Appearance", "Light", "glass light"),
                                   ("Interface Style", "Classic", "classic light"),
                                   ("Appearance", "Dark", "classic dark")]
        {
            pick(menu, item)
            element("workspace.w1").hover()
            XCTAssertTrue(card.vanishes(within: 2), look)
            element("tab.\(tab)").hover()
            XCTAssertTrue(card.exists(within: 2), look)
            let row = element("hovercard.\(pane)").frame
            let empty = CGRect(x: row.midX, y: row.minY + 3, width: row.width / 2 - 10, height: 20)
            var sharp = (card: 0.0, bare: 0.0)
            let blurred = until(2) {
                sharp = (sharpness(empty), sharpness(empty.offsetBy(dx: 0, dy: 100)))
                return sharp.bare > 4 && sharp.card < sharp.bare * 0.3
            }
            keepScreenshot("\(look): card \(sharp.card), bare \(sharp.bare)")
            XCTAssertTrue(blurred, "\(look): card \(sharp.card), bare \(sharp.bare)")
        }
    }

    private func sharpness(_ rect: CGRect) -> Double {
        let window = app.windows.firstMatch
        let shot = window.screenshot().image
        guard let full = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        let scale = Double(full.width) / shot.size.width
        let box = rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        guard let crop = full.cropping(to: CGRect(x: box.minX * scale, y: box.minY * scale,
                                                  width: box.width * scale, height: box.height * scale))
        else { return 0 }
        let brightness = Self.brightness(NSImage(cgImage: crop, size: .zero))
        let steps = zip(brightness, brightness.dropFirst()).map { abs($0 - $1) }
        return steps.isEmpty ? 0 : Double(steps.reduce(0, +)) / Double(steps.count)
    }

    /// macOS gives the help tag's text to no accessibility attribute, and on CI the tag shows in one run of two, so the
    /// label stands in for it.
    func testChromeButtonsNameTheirShortcuts() {
        let button = element("titlebar.new-tab")
        XCTAssertTrue(button.exists(within: connect))
        XCTAssertEqual(button.label, "New Tab ⌘T")
        XCTAssertEqual(element("titlebar.palette").label, "Command Palette ⌘K")
        XCTAssertEqual(element("sidebar.open-session").label, "Open Session ⌥⌘T")
    }

    private func rows(of card: XCUIElement) -> [XCUIElement] {
        card.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hovercard.' AND identifier != 'hovercard.title'"))
            .allElementsBoundByIndex
    }
}
