import XCTest

/// 400 panes: 600 took CI two minutes to make, and a Mac gives all its programs 511 terminals.
extension OvviUITests {
    func testHundredsOfPanesStayQuick() async throws {
        executionTimeAllowance = 600
        addTeardownBlock { [eight] in _ = try? await Self.post("\(eight)/stress") }
        let made = try await String(decoding: Self.post("\(eight)/stress", Data("300 30 400 100".utf8)), as: UTF8.self)
        print(made)
        // From the launch to the first card drawn: 7–8 s on CI.
        let launched = Date.now
        relaunch(eight, ["-recordLatency", "YES"])
        addTeardownBlock { @MainActor in self.note(self.element("app.latency").stringValue) }
        XCTAssertTrue(element("pane.w1:p1").exists(within: 20))
        note("connect \(Int(Date.now.timeIntervalSince(launched) * 1000))ms")
        try await Task.sleep(for: .seconds(10))

        let palette = element("palette.filter"), openSession = element("open-session.filter")
        let escape = XCUIKeyboardKey.escape.rawValue
        quietKey("k", .command) { palette.exists }
        quietKey(escape, []) { !palette.exists }
        quietKey("t", [.command, .option]) { openSession.exists }
        quietKey(escape, []) { !openSession.exists }
        quietKey("2", .command) { self.element("tab.w1:t2").isSelected }
        quietKey("1", .command) { self.element("tab.w1:t1").isSelected }
        quietKey("]", [.command, .control]) { self.element("workspace.w2").isSelected }
        quietKey("[", [.command, .control]) { self.element("workspace.w1").isSelected }
        quietKey("s", [.command, .control]) { !self.element("sidebar").exists }
        quietKey("s", [.command, .control]) { self.element("sidebar").exists }
        try await typeInPalette()

        unfold("w1")
        try await scroll(over: element("sidebar").frame, vertical: true)
        fold("w1")
        try await scroll(over: element("sidebar").frame, vertical: true)
        try await scroll(over: element("tab.w1:t1").frame, vertical: false)

        try await newTabSplitAndCloses(in: eight)

        quietKey("1", .command) { self.element("tab.w1:t1").isSelected }
        let busy = try await measure("busy tab", seconds: 5, session: eight)
        // 15 % on CI.
        let cpu = busy.split(separator: "\n")[0].split(separator: " ")
        XCTAssertLessThan(Double(cpu[1].dropLast()) ?? 100, 50, busy)
        try await sample("busy tab", in: eight)
        try await keep(String(decoding: Self.post("\(eight)/heap"), as: UTF8.self), as: "heap, busy tab")

        openPage(one)
        quietKey("[", [.command, .option]) { self.header == eight }
        quietKey("]", [.command, .option]) { self.header == self.one }
        quietKey("[", [.command, .option]) { self.header == eight }

        let keys = recorded().filter { $0.name.first.map("⌘⌃⇧⌥".contains) == true }
        for entry in keys {
            XCTAssertLessThanOrEqual(entry.turns, 1, entry.name)
        }
        // A snapshot's apply on the main thread ("main … <snapshots> <their ms>", its own time): about 11 ms on CI.
        let main = element("app.latency").stringValue.split(separator: "; ").filter { $0.hasPrefix("main ") }
            .map { $0.split(separator: " ") }
        let applies = main.reduce(0) { $0 + (Int($1[3]) ?? 0) }
        let applied = main.reduce(0) { $0 + (Int($1[4].dropLast(2)) ?? 0) }
        XCTAssertLessThan(applied, 25 * max(applies, 1), "\(applied) ms for \(applies) snapshots")
    }

    private func typeInPalette() async throws {
        let palette = element("palette.filter")
        quietKey("k", .command) { palette.exists }
        try await scroll(over: element("palette.tab.w1:t1").frame, vertical: true)
        var typed = ""
        for letter in "split" {
            typed.append(letter)
            quietKey(String(letter), []) { palette.value as? String == typed }
        }
        XCTAssertTrue(element("palette.command.Split Right").exists)
        for _ in typed {
            typed.removeLast()
            quietKey(XCUIKeyboardKey.delete.rawValue, []) {
                typed.isEmpty ? self.element("palette.section.Tabs").exists : palette.value as? String == typed
            }
        }
        quietKey(XCUIKeyboardKey.escape.rawValue, []) { !palette.exists }
        let keys = recorded().filter { ["S", "P", "L", "I", "T", "\u{7F}"].contains($0.name) }
        XCTAssertEqual(keys.count, 10)
        for entry in keys {
            XCTAssertLessThanOrEqual(entry.turns, 1, entry.name)
            XCTAssertLessThanOrEqual(entry.lists, 3, entry.name)
        }
    }

    private func newTabSplitAndCloses(in eight: String) async throws {
        let before = try await tabIDs(in: eight)
        quietKey("t", .command) { !self.element("page.w1:t1").exists }
        let new = try await newTabID(after: before, in: eight)
        XCTAssertTrue(element("tab.\(new)").has(\.isSelected, true, within: 10))
        _ = try await measure("quiet tab, 100 agents elsewhere", seconds: 5, session: eight)
        try await sample("quiet tab", in: eight)
        let cards = element("page.\(new)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        // herdr's own pane, not the stand-in (`pane.new.…`): a starved runner's herdr took over 6 s to answer.
        quietKey("d", .command, within: 15, until: { cards.count == 2 }, saw: {
            cards.allElementsBoundByIndex.map(\.identifier).joined(separator: " ")
        })
        try await Task.sleep(for: .seconds(2.5))
        quietKey("w", .command) { cards.count == 1 }
        quietKey("w", [.command, .shift]) { !self.element("tab.\(new)").exists }
    }

    /// XCUITest's queries take the main thread, for seconds at this size, and would be counted as the key's time.
    private func quietKey(_ key: String, _ flags: XCUIElement.KeyModifierFlags, within timeout: TimeInterval = 5,
                          until done: () -> Bool, saw: () -> String = { "" })
    {
        app.typeKey(key, modifierFlags: flags)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(until(timeout, done), "after \(key): \(saw())")
    }

    func note(_ text: String) {
        print(text)
        keep(text, as: "stress")
    }

    private func scroll(over frame: CGRect, vertical: Bool) async throws {
        for sign in [-1.0, 1.0] {
            let body = "\(frame.midX) \(frame.midY) \(20 * sign) 30 0 \(vertical ? 1 : 0)"
            try await Self.post("\(one)/swipe", Data(body.utf8))
            try await Task.sleep(for: .seconds(0.5))
        }
    }

    private func sample(_ name: String, in session: String) async throws {
        let profile = try await Self.post("\(session)/sample", Data("3".utf8))
        keep(String(decoding: profile, as: UTF8.self), as: "sample, \(name)")
    }
}
