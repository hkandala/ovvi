import XCTest

/// The pixels of a terminal are the only place an empty card shows, so these tests read its screenshot.
extension OvviUITests {
    func testCardsShowTheirTextOnEveryPath() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        for pane in ["w1:p1", "w1:p2", "w1:p3", "w1:p4", "w2:p1"] {
            try await fill(pane)
        }
        try await expectText(["w1:p1", "w1:p2", "w1:p3"], "launch")
        element("tab.w1:t2").click()
        try await expectText(["w1:p4"], "second tab")
        element("tab.w1:t1").click()
        try await expectText(["w1:p1", "w1:p2", "w1:p3"], "first tab again")
        element("workspace.w2").click()
        try await expectText(["w2:p1"], "second workspace")
        element("workspace.w1").click()
        try await expectText(["w1:p1", "w1:p2", "w1:p3"], "first workspace again")

        let (tab, pane) = try await newTab("reveal")
        try await fill(pane)
        element("tab.\(tab)").click()
        try await expectText([pane], "new tab")
        let right = try await split(pane)
        try await fill(right)
        try await expectText([pane, right], "split")
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").exists(within: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 5))
        try await expectText([pane, right], "overview and back")
        element("titlebar.sidebar").click()
        try await expectText([pane, right], "sidebar hidden")
        element("titlebar.sidebar").click()
        try await expectText([pane, right], "sidebar shown")
    }

    func testCardKeepsItsGridUntilItsSizeSettles() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await expectPTYSize("w1:p1")
        try await send("trap 'echo winch' WINCH\r", to: "w1:p1")
        try await waitFor("w1:p1") { $0.contains("WINCH") }
        let before = terminal.stringValue
        element("titlebar.sidebar").click()
        var grids = [before]
        let end = Date.now + 1.5
        while Date.now < end {
            if terminal.stringValue != grids.last {
                grids.append(terminal.stringValue)
            }
        }
        // The check that tells this from a resize at every frame: herdr's one resize (the winch count). A stall over
        // 150 ms inside the slide would give a real third grid.
        XCTAssertEqual(grids.count, 2, "grids while the sidebar slid: \(grids)")
        // bash prints it after its prompt, on the prompt's line.
        let winches = { (screen: String) in screen.split(separator: "\n").count { $0.hasSuffix("winch") } }
        try await waitFor("w1:p1") { winches($0) > 0 }
        try await Task.sleep(for: .milliseconds(500))
        let screen = try await read("w1:p1")
        XCTAssertEqual(winches(screen), 1, screen)
        try await expectPTYSize("w1:p1")
        try await fill("w1:p1")
        try await expectText(["w1:p1"], "after the resize")
    }

    func testResizeNeverBlanksTheText() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        addTeardownBlock { @MainActor [self] in app.typeKey("0", modifierFlags: .command) }
        try await fill("w1:p1")
        try await expectText(["w1:p1"], "filled")
        let steps: [(String, () -> Void)] = [
            ("sidebar hidden", { self.element("titlebar.sidebar").click() }),
            ("sidebar shown", { self.element("titlebar.sidebar").click() }),
            ("bigger text", { self.app.typeKey("+", modifierFlags: .command) }),
            ("smaller text", { self.app.typeKey("-", modifierFlags: .command) }),
        ]
        for (step, act) in steps {
            let grid = terminal.stringValue
            act()
            // Screenshots as fast as they come through the resize and herdr's redraw; read after, not in between.
            var shots: [NSImage] = []
            let end = Date.now + 1.5
            while Date.now < end {
                shots.append(terminal.screenshot().image)
            }
            let inks = shots.map(Self.ink)
            XCTAssertGreaterThan(inks.min() ?? 0, 0.01, "\(step): ink of \(inks.count) screenshots: \(inks)")
            XCTAssertNotEqual(terminal.stringValue, grid, "\(step): the grid changed")
            try await expectText(["w1:p1"], step)
        }
    }

    /// CI has Reduce Motion on, so this forces motion.
    func testLayoutMotionAnimatesWithoutBlanking() async throws {
        relaunch(one, ["-recordMotion", "YES"])
        // Split Left swaps, and herdr focuses the swapped pane's tab: the next test's launch would show w2.
        restoreHerdrFocusAfter()
        let (tab, pane) = try await newTab("motion")
        element("tab.\(tab)").click()
        let host = element("host.\(pane)"), terminal = element("terminal.\(pane)"), card = element("motion.\(pane)")
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try await expectJump(tab, pane)
        }
        XCTAssertTrue(drawn(pane))
        try await fill(pane)
        try await expectText([pane], "filled")
        let steps: [(String, () async throws -> Void)] = [
            ("split left", { self.paneMenu(pane, "Split Left") }),
            ("zoom", {
                self.hoverHeader(pane)
                self.element("pane.\(pane).zoom").click()
            }),
            ("restore", { self.app.typeKey(.return, modifierFlags: [.command, .shift]) }),
            ("close", {
                let other = try await self.order(tab).first { $0 != pane } ?? ""
                _ = try await Self.call(self.one, "pane.close", ["pane_id": other])
            }),
            ("sidebar hidden", { self.element("titlebar.sidebar").click() }),
            ("sidebar shown", { self.element("titlebar.sidebar").click() }),
            ("split down", { self.paneMenu(pane, "Split Down") }),
        ]
        var sampled = 0
        for (step, act) in steps {
            XCTAssertTrue(host.exists(within: 3), step)
            let sizes = Self.motion(host).sizes, slides = Self.slides(card), place = card.frame
            let band = band(through: terminal), before = Self.ink(Self.crop(XCUIScreen.main.screenshot().image, band))
            try await act()
            var inks: [Double] = []
            let end = Date.now + 1
            while Date.now < end {
                inks.append(Self.ink(Self.crop(XCUIScreen.main.screenshot().image, band)))
            }
            if step != "split down" {
                XCTAssertGreaterThan(inks.min() ?? 0, before / 3, "\(step): ink \(before) before, then \(inks)")
            }
            if step.hasPrefix("sidebar") {
                XCTAssertGreaterThanOrEqual(Self.motion(host).sizes - sizes, 4,
                                            "\(step): sizes from \(sizes) to \(host.label)")
            } else {
                XCTAssertGreaterThan(Self.slides(card), slides, "\(step): \(card.label)")
                sampled += Self.expectBetween(card, from: place, step) ? 1 : 0
            }
            try await expectText([pane], step)
        }
        XCTAssertGreaterThan(sampled, 0, "no motion sampled while it ran")
    }

    func testAVisitedCardComesBackAtOnce() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await fill("w1:p1")
        try await expectText(["w1:p1"], "filled")
        let filled = Self.ink(terminal.screenshot().image), id = try await terminalID("w1:p1")
        let lines = max((Int(terminal.stringValue.split(separator: " ").first ?? "") ?? 0) / 3, 3)
        try await showNewTabs(6)
        let streams = try await streams(one)
        XCTAssertTrue(streams.contains { $0.contains(id) }, "w1:p1 kept its stream: \(streams)")
        try await send("clear; for i in $(seq 1 \(lines)); do echo ovvi-away-$i-ovvi-away; done\r", to: "w1:p1")
        try await waitFor("w1:p1") { $0.contains("ovvi-away-\(lines)-ovvi-away") }
        let card = element("pane.w1:p1")
        app.typeKey("1", modifierFlags: .command)
        // From the key on: a rebuilt surface shows loading for about 100 ms.
        var inks: [Double] = [], loading = false
        let end = Date.now + 1.5
        while Date.now < end {
            loading = loading || card.exists && card.stringValue.contains("loading")
            if terminal.exists, terminal.isHittable {
                inks.append(Self.ink(terminal.screenshot().image))
            }
        }
        XCTAssertFalse(loading, "loading after the key")
        XCTAssertGreaterThan(inks.min() ?? 0, filled * 0.15, "\(filled) before, then \(inks)")
        XCTAssertLessThan(inks.max() ?? 1, filled * 0.6, "\(filled) before, then \(inks)")
    }

    private func showNewTabs(_ count: Int) async throws {
        for index in 0 ..< count {
            let (tab, pane) = try await createTab(in: "w1")
            closeAfter("tab", tab)
            XCTAssertTrue(element("tabs.count").has(\.stringValue, "\(index + 3)", within: 3))
            app.typeKey("\(index + 3)", modifierFlags: .command)
            XCTAssertTrue(element("pane.\(pane)").exists(within: 3))
        }
    }

    func testAnEvictedCardComesBackWithItsPicture() async throws {
        relaunch(one, ["-spareTerminals", "4"])
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await fill("w1:p1")
        try await expectText(["w1:p1"], "filled")
        let id = try await terminalID("w1:p1")
        try await showNewTabs(5)
        try await expect("w1:p1's stream to end") { try await !streams(one).contains { $0.contains(id) } }
        let streams = try await streams(one)
        XCTAssertLessThanOrEqual(streams.count, 5, "\(streams)")
        app.typeKey("1", modifierFlags: .command)
        let start = Date.now, card = element("pane.w1:p1")
        XCTAssertTrue(terminal.has(\.isHittable, true, within: 3))
        var shots: [NSImage] = []
        var times: [String] = []
        while Date.now < start + 1.5 {
            shots.append(terminal.screenshot().image)
            let loading = card.stringValue.contains("loading")
            times.append("\(Int(Date.now.timeIntervalSince(start) * 1000))\(loading ? "L" : "")")
        }
        print("evicted card, ms after the key (L: loading): \(times)")
        let inks = shots.map(Self.ink)
        XCTAssertGreaterThan(inks.min() ?? 0, 0.01, "ink of \(inks.count) screenshots: \(inks)")
        try await expectText(["w1:p1"], "back")
        try await expect("w1:p1's stream again") { try await self.streams(one).contains { $0.contains(id) } }
        try await send("clear\r", to: "w1:p1")
        try await expect("the cleared screen drawn") { Self.ink(terminal.screenshot().image) < (inks.min() ?? 0) / 3 }
    }

    /// The largest window: a tooltip or a hover card is a window too.
    private func band(through terminal: XCUIElement) -> CGRect {
        let frame = terminal.frame, window = app.windows.allElementsBoundByIndex.map(\.frame)
            .max { $0.width * $0.height < $1.width * $1.height } ?? .zero
        return CGRect(x: window.minX, y: frame.minY + frame.height * 0.45, width: window.width,
                      height: frame.height * 0.2)
    }

    /// A sample a busy main thread took after the motion (0.13 s) tests nothing: false then.
    @discardableResult
    private static func expectBetween(_ card: XCUIElement, from old: CGRect, _ step: String) -> Bool {
        let numbers = card.label.split(separator: " ").compactMap { Double($0) }.map { CGFloat($0) }
        guard numbers.count == 14 else {
            XCTFail("\(step): \(card.label)")
            return false
        }
        let mid = CGRect(x: numbers[1], y: numbers[2], width: numbers[3], height: numbers[4])
        let end = CGRect(x: numbers[6], y: numbers[7], width: numbers[8], height: numbers[9]), new = card.frame
        XCTAssertEqual(end.minX, new.minX, accuracy: 2, "\(step): \(card.label) at \(new)")
        XCTAssertEqual(end.minY, new.minY, accuracy: 2, "\(step): \(card.label) at \(new)")
        // The surface (`CardChrome`) moves with the card.
        let surface = CGRect(x: numbers[10], y: numbers[11], width: numbers[12], height: numbers[13])
        for (edge, name) in [(\CGRect.minX, "left"), (\.maxX, "right"), (\.minY, "top"), (\.maxY, "bottom")] {
            XCTAssertEqual(
                surface[keyPath: edge],
                mid[keyPath: edge],
                accuracy: 3,
                "\(step): the surface's \(name) edge",
            )
        }
        for (edge, name) in [(\CGRect.minX, "left"), (\.maxX, "right"), (\.minY, "top"), (\.maxY, "bottom")] {
            let (low, high) = (min(old[keyPath: edge], new[keyPath: edge]), max(old[keyPath: edge], new[keyPath: edge]))
            XCTAssertTrue((low - 3 ... high + 3).contains(mid[keyPath: edge]),
                          "\(step): the \(name) edge at \(mid[keyPath: edge]), not from \(old) to \(new)")
        }
        return numbers[5] < 130
    }

    private static func slides(_ card: XCUIElement) -> Int {
        let words = card.label.split(separator: " ")
        return words.firstIndex(of: "slides").flatMap { Int(words[min($0 + 1, words.count - 1)]) } ?? 0
    }

    private static func motion(_ host: XCUIElement) -> (sizes: Int, ms: Int) {
        let words = host.label.split(separator: " ").compactMap { Int($0) }
        return (words.first ?? 0, words.dropFirst().first ?? 0)
    }

    /// One that still attaches resizes the pane after a fill's lines, and bash redraws its prompt over the last one
    /// (CI: 59, then the prompt).
    func drawn(_ pane: String, within timeout: TimeInterval = 5) -> Bool {
        let card = element("pane.\(pane)")
        return until(timeout) { card.exists && card.stringValue != "loading" }
    }

    /// Under Reduce Motion (CI's Mac) the card jumps to its new size in one step.
    private func expectJump(_ tab: String, _ pane: String) async throws {
        let host = element("host.\(pane)")
        XCTAssertTrue(host.exists(within: 3))
        let sizes = Self.motion(host).sizes
        let other = try await split(pane)
        XCTAssertTrue(until(3) { Self.motion(host).sizes == sizes + 1 }, "Reduce Motion")
        _ = try await Self.call(one, "pane.close", ["pane_id": other])
        XCTAssertTrue(element("pane.\(other)").vanishes(within: 3))
        relaunch(one, ["-recordMotion", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isHittable, true, within: 3))
        element("tab.\(tab)").click()
    }

    private static func crop(_ image: NSImage, _ rect: CGRect) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        // The screen shot's size is in pixels, not points.
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale,
                            height: rect.height * scale)
        return cgImage.cropping(to: pixels).map { NSImage(cgImage: $0, size: rect.size) } ?? image
    }

    func fill(_ pane: String) async throws {
        try await waitForPrompt(pane)
        try await send("clear; for i in $(seq 1 60); do echo ovvi-reveal-$i-ovvi-reveal; done\r", to: pane)
        try await waitFor(pane) { $0.contains("ovvi-reveal-60-ovvi-reveal") }
    }

    func expectText(_ panes: [String], _ step: String) async throws {
        keepScreenshot(step)
        for pane in panes {
            let card = element("pane.\(pane)"), terminal = element("terminal.\(pane)")
            var ink = 0.0
            do {
                try await expect("text", times: 30) {
                    guard card.exists, card.stringValue != "loading",
                          terminal.isHittable else { return false }
                    ink = Self.ink(terminal.screenshot().image)
                    return ink > 0.01
                }
            } catch is Waited {
                throw Waited(description: "\(pane) shows no text after \(step): \(card.stringValue), ink \(ink)")
            }
        }
    }

    private static func ink(_ image: NSImage) -> Double {
        let brightness = brightness(image)
        guard !brightness.isEmpty else { return 0 }
        let median = brightness.sorted()[brightness.count / 2]
        return Double(brightness.count { abs($0 - median) > 60 }) / Double(brightness.count)
    }

    static func brightness(_ image: NSImage) -> [Int] {
        let pixels = pixels(image)
        return stride(from: 0, to: pixels.count, by: 4).map {
            (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3
        }
    }

    static func pixels(_ image: NSImage) -> [UInt8] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                .map { $0.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height)) } != nil
        }
        return drawn ? pixels : []
    }
}
