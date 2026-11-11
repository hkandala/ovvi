import XCTest

extension OvviUITests {
    /// Launch arguments land in UserDefaults' argument domain, which the settings read. They also pin the look: the
    /// menu then writes the persistent domain, which the argument domain hides.
    func testLaunchesInEachLook() async throws {
        for (appearance, style) in [("light", "glass"), ("dark", "classic"), ("light", "classic"), ("dark", "glass")] {
            relaunch(one, ["-appearance", appearance, "-interfaceStyle", style])
            expectLook("\(style) \(appearance)")
            try await expectPTYSize("w1:p1")
        }
    }

    /// Read from pixels, the one place the look shows. The rim is read on the card without the keyboard: the keyboard
    /// card's active border lies over its rim. Asserted in dark; light's rim and the card both end near white.
    func testCardsLookAlikeWithAndWithoutTheKeyboard() {
        step("Glass: the keyboard card and the other card")
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("terminal.w1:p1").click()
        XCTAssertTrue(hasKeyboard("terminal.w1:p1"))
        let keyboard = element("pane.w1:p1"), other = element("pane.w1:p2")

        // CI's VM draws the glass backdrop opaque whatever the desktop shows (a runner window under Ovvi in black,
        // white and blue changed no pixel of it), so a desktop's effect is not checked here.
        pick("Interface Style", "Glass")
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        for appearance in ["Dark", "Light"] {
            step("Glass \(appearance.lowercased()): the cards look alike")
            pick("Appearance", appearance)
            // The fills follow the look within a frame or two.
            Thread.sleep(forTimeInterval: 0.3)
            let lit = median(keyboard), unlit = median(other)
            keepScreenshot("glass \(appearance.lowercased()): \(lit) / \(unlit)")
            // 0: a screenshot that did not draw.
            XCTAssertTrue(unlit > 0 && (0 ... 6).contains(lit - unlit), "\(appearance): \(lit) / \(unlit)")

            step("Glass \(appearance.lowercased()): the other card's top rim is brighter than its side")
            let rim = rim(other)
            keepScreenshot("glass \(appearance.lowercased()) rim over the fill (top, side): \(rim)")
            // Rex's dark rim: the top line about 40 steps over the fill at 1x, the sides about 10.
            XCTAssertTrue(appearance == "Light" || rim.top - rim.side >= 12 && rim.top >= 25, "\(rim)")
        }
    }

    /// macOS draws Liquid Glass grey and faint in an inactive window.
    func testGlassLooksTheSameInAnInactiveWindow() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        pick("Interface Style", "Glass")
        let row = element("workspace.w2")
        let active = median(row)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.exists(within: 3), "no Settings window")
        addTeardownBlock { @MainActor [self] in settingsWindow.typeKey("w", modifierFlags: .command) }
        // The main window redraws as inactive within a frame or two.
        Thread.sleep(forTimeInterval: 0.3)
        let inactive = median(row)
        keepScreenshot("glass dark, inactive: \(active) / \(inactive)")
        XCTAssertTrue(active > 0 && abs(active - inactive) <= 4, "active \(active), inactive \(inactive)")
    }

    /// herdr drops mouse events for a program without mouse mode, so a drag over a plain shell selects locally.
    func testSelectedTextIsReadable() async throws {
        step("A shell with full blocks and text")
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p1")
        // Full blocks (3 cells in 10) draw the cell's text color edge to edge. printf makes their bytes, so the line
        // editor gets ASCII in any locale.
        try await send(
            "clear; for i in $(seq 600); do printf '\\342\\226\\210\\342\\226\\210\\342\\226\\210 ovvi '; done; "
                + "echo; echo ovvi-$((6*7))\r",
            to: "w1:p1",
        )
        try await waitFor("w1:p1") { $0.contains("\novvi-42") }
        // Settings persist across runs in the app's own defaults: go back to the defaults even when a step fails.
        addTeardownBlock { @MainActor [self] in
            pick("Interface Style", "Glass")
            pick("Appearance", "Dark")
        }
        // One pick a step: each switches the look on its own.
        pick("Interface Style", "Glass")
        let steps = [("Appearance", "Dark", "glass dark"), ("Appearance", "Light", "glass light"),
                     ("Interface Style", "Classic", "classic light"), ("Appearance", "Dark", "classic dark")]
        for (menu, item, look) in steps {
            step("View menu: \(item) makes it \(look), its selected text readable")
            pick(menu, item)
            expectLook(look)
            terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.01))
                .click(
                    forDuration: 0.2,
                    thenDragTo: terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)),
                )
            // WCAG's 4.5 for text; libghostty's default is 1.2 in dark, 1.4 in light. The selection shows on the card
            // (about 1.0 with no selection drawn). The terminal takes the look a frame or two after the window.
            var last = (text: 0.0, selection: 0.0)
            do {
                try await expect("\(look): readable selected text", times: 20) {
                    last = Self.contrast(terminal.screenshot().image)
                    return last.text > 4.5 && last.selection > 1.1
                }
            } catch is Waited {
                throw Waited(description: "\(look): text \(last.text), selection over the card \(last.selection)")
            }
            keepScreenshot("\(look) selection: text \(last.text), selection over the card \(last.selection)")
        }

        step("View menu: the other appearance, then Auto follows the system")
        let (system, other) = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            ? ("dark", "light") : ("light", "dark")
        pick("Appearance", other.capitalized)
        expectLook("classic \(other)")
        pick("Appearance", "Auto")
        expectLook("classic \(system)")
    }

    /// The 85th percentile of contrast: full blocks fill 30 % of the selected rows.
    private static func contrast(_ image: NSImage) -> (text: Double, selection: Double) {
        let pixels = pixels(image)
        guard let width = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, width > 0,
              pixels.count > width * 4 * 30 else { return (0, 0) }
        let rows = pixels.count / 4 / width
        func luminance(_ offset: Int) -> Double {
            let linear = (0 ..< 3).map { channel in
                let value = Double(pixels[offset + channel]) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        func ratio(_ one: Double, _ other: Double) -> Double {
            (max(one, other) + 0.05) / (min(one, other) + 0.05)
        }
        func common(_ offsets: [Int]) -> Int {
            let colors = Dictionary(grouping: offsets) { pixels[$0 ..< $0 + 3].reduce(0) { $0 << 8 | Int($1) } }
            return colors.max { $0.value.count < $1.value.count }?.value.first ?? 0
        }
        let top = (0 ..< rows / 3 * width).map { $0 * 4 }
        let background = luminance(common(top))
        let text = top.map { ratio(luminance($0), background) }.sorted()[top.count * 85 / 100]
        let card = luminance(common(((rows - 1) * width ..< rows * width).map { $0 * 4 }))
        return (text, ratio(background, card))
    }

    private func rim(_ card: XCUIElement) -> (top: Int, side: Int) {
        let image = card.screenshot().image
        let brightness = Self.brightness(image)
        guard let width = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, width > 0,
              brightness.count > width * 40 else { return (0, 0) }
        let height = brightness.count / width
        func mean(_ offsets: [Int]) -> Int {
            offsets.map { brightness[$0] }.reduce(0, +) / offsets.count
        }
        let middle = Array(-10 ..< 10)
        let top = (0 ..< 3).map { row in mean(middle.map { row * width + width / 2 + $0 }) }.max() ?? 0
        let side = (0 ..< 3).map { column in mean(middle.map { (height / 2 + $0) * width + column }) }.max() ?? 0
        let fill = brightness.sorted()[brightness.count / 2]
        return (top - fill, side - fill)
    }

    func median(_ card: XCUIElement) -> Int {
        let brightness = Self.brightness(card.screenshot().image).sorted()
        return brightness.isEmpty ? 0 : brightness[brightness.count / 2]
    }

    func pick(_ menu: String, _ item: String) {
        app.menuBars.menuBarItems["View"].click()
        let submenu = app.menuBars.menuItems[menu]
        submenu.hover()
        submenu.menuItems[item].click()
    }

    private func expectLook(_ look: String) {
        XCTAssertTrue(element("window.look").has(\.stringValue, look, within: connect), look)
    }
}
