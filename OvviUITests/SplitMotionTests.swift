import XCTest

extension OvviUITests {
    func testSplitsKeepTheDisplayRate() async throws {
        executionTimeAllowance = 900
        relaunch(one, ["-recordLatency", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("split-setup")
        try await waitForPrompt(shell)
        try await makeTreeRepo(Self.splits, in: shell)
        try await send("""
        { for j in $(seq 300); do echo "- Line $j of the notes, *some* \\`code\\` and words to lay out."; done; } \
        >notes.md && { for j in $(seq 300); do echo "<p>Paragraph $j, words to lay out and paint.</p>"; done; } \
        >page.html && printf '%s\\n' \(Self.redrawing) >redraw.py && clear && echo made-$((2+3))\r
        """, to: shell)
        try await waitFor(shell) { $0.contains("made-5") }
        var records: [String] = []
        for scenario in ["shell", "tui"] + Self.cards.map(\.0) + ["six panes"] {
            let (tab, pane) = try await newTab("split-\(scenario.prefix(3))")
            try await waitForPrompt(pane)
            try await fill(pane, for: scenario)
            try await show(tab)
            try await Task.sleep(for: .seconds(3))
            element("pane.\(pane)").click()
            let splits = try await splitAndClose(tab, scenario)
            XCTAssertEqual(splits.count, 4, "\(scenario): \(splits)")
            records.append("\(scenario): \(splits.joined(separator: ", "))")
            print(records.last ?? "")
        }
        keep(records.joined(separator: "\n"), as: "splits")
    }

    func testAShortChoosersListKeepsTheSelectedRowInView() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, top) = try await newTab("chooser short")
        element("tab.\(tab)").click()
        element("terminal.\(top)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(top)"))
        app.typeKey("d", modifierFlags: [.command, .shift])
        let card = try await replaced(top, in: tab, besides: [top]), last = element("pane.\(card).chooser.git")
        XCTAssertTrue(last.exists(within: 3))
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(last.has(\.isSelected, true, within: 2))
        let frame = element("pane.\(card)")
        for _ in 0 ..< 8 where frame.frame.height >= 150 {
            let count = try await order(tab).count
            app.typeKey("d", modifierFlags: [.command, .shift])
            try await expect("one more split") { try await order(tab).count == count + 1 }
        }
        XCTAssertLessThan(frame.frame.height, 150)
        XCTAssertTrue(last.has(\.isHittable, true, within: 2), "\(last.frame) in \(frame.frame)")
    }

    private static let splits = "/tmp/ovvi-e2e-splits"
    private static let cards = [("explorer", "explorer", "/private\(splits)/"), ("git", "git", "/private\(splits)/"),
                                ("markdown", "explorer", "/private\(splits)/notes.md"),
                                ("browser", "browser", "file://\(splits)/page.html")]

    private func fill(_ pane: String, for scenario: String) async throws {
        func card(_ pane: String, _ kind: String) async throws {
            let (_, plugin, place) = try XCTUnwrap(Self.cards.first { $0.0 == kind })
            let iid = String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(6))
            try await Self.call(one, "pane.rename", ["pane_id": pane, "label": "ovvi:\(plugin)#\(iid) \(place)"])
        }
        func redraw(_ pane: String) async throws {
            try await waitForPrompt(pane)
            try await send("python3 \(Self.splits)/redraw.py\r", to: pane)
        }
        switch scenario {
        case "shell": break
        case "tui": try await redraw(pane)
        case "six panes":
            let right = try await split(pane), last = try await split(right)
            let below = try await [split(pane, "down"), split(right, "down"), split(last, "down")]
            for program in [pane, right, below[0]] {
                try await redraw(program)
            }
            for (other, kind) in zip([last] + below.dropFirst(), ["explorer", "markdown", "browser"]) {
                try await card(other, kind)
            }
        default: try await card(pane, scenario)
        }
    }

    private func splitAndClose(_ tab: String, _ scenario: String) async throws -> [Substring] {
        let start = element("app.latency").stringValue.split(separator: "; ").count
        for flags: XCUIElement.KeyModifierFlags in [.command, .command, [.command, .shift], [.command, .shift]] {
            let before = try await order(tab).count
            app.typeKey("d", modifierFlags: flags)
            // No accessibility query while the meter runs: XCUITest's snapshots take the main thread.
            try await Task.sleep(for: .seconds(1))
            try await expect("\(scenario): the split's pane") { try await order(tab).count == before + 1 }
            // The new pane's program is asked a second late: until then a close waits for herdr's.
            try await Task.sleep(for: .seconds(1.5))
            app.typeKey("w", modifierFlags: .command)
            try await expect("\(scenario): the split's pane closed") { try await order(tab).count == before }
            try await Task.sleep(for: .seconds(0.5))
        }
        return element("app.latency").stringValue.split(separator: "; ").dropFirst(start)
            .filter { $0.hasPrefix("split ") }
    }

    private static let redrawing = [
        "import shutil, sys, time",
        "w = sys.stdout.write",
        #"w("\x1b[?1049h\x1b[?25l")"#,
        "i = 0",
        "while True:",
        "    c, r = shutil.get_terminal_size()",
        "    i += 1",
        #"    lines = (("%06d " % (i * r + k) + "=" * c)[:c] for k in range(r - 1))"#,
        #"    w("\x1b[H" + "\r\n".join("\x1b[3%dm%s\x1b[K" % (1 + (i + k) % 6, t) for k, t in enumerate(lines)))"#,
        "    sys.stdout.flush()",
        "    time.sleep(1 / 30)",
    ].map { "'\($0)'" }.joined(separator: " ")
}
