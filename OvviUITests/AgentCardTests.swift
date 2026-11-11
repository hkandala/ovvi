import XCTest

extension OvviUITests {
    func testOpenPutsCardsWithoutMovingTheView() async throws {
        relaunch(one, Self.agentHold)
        let (tab, first) = try await newTab("cards")
        try await closeNew("tab", besides: tabIDs())
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        try await waitForPrompt(first)
        try await expectOpen("w2")
        let folder = try await cardsFolder(in: first)
        let focus = try await snapshot()["focused_pane_id"] as? String

        let file = try await open("./notes.md", from: first, "file", ["kind: explorer", "reused: false", "shown: true"])
        let label = try await paneLabel(file)
        XCTAssertTrue(label.hasPrefix("ovvi:explorer#") && label.hasSuffix(" \(folder)/notes.md"), label)
        XCTAssertTrue(element("pane.\(file)").exists(within: 3))
        XCTAssertLessThan(element("pane.\(first)").frame.maxX, element("pane.\(file)").frame.minX)
        let again = try await open("explorer notes.md", from: first, "again", ["reused: true"])
        XCTAssertEqual(again, file)

        let below = try await open("http://127.0.0.1:65530 --beside \(file) --down", from: first, "down",
                                   ["kind: browser"])
        XCTAssertTrue(element("pane.\(below)").exists(within: 3))
        XCTAssertLessThan(element("pane.\(file)").frame.maxY, element("pane.\(below)").frame.minY)

        let (spare, _) = try await createTab(in: "w2")
        closeAfter("tab", spare)
        try await send("clear; \(Self.ovviCommand) open git . --tab; echo tab-$((6*7))-$?\r", to: first)
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts.matching(NSPredicate(format: "value CONTAINS 'opened Git ovvi-e2e-cards'"))
            .firstMatch.exists(within: 10))
        XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected })
        let unmoved = try await snapshot()["focused_pane_id"] as? String
        XCTAssertEqual(unmoved, focus)
        keepScreenshot("open notice")
        notice.buttons["notice.show"].click()
        try await waitFor(first) { $0.contains("tab-42-0") }
        let tabbed = try await answered(first)
        let opened = try await tabOf(tabbed)
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 3))
        try await expectBeside(opened, tab)

        let floated = try await open("explorer notes.md --float --new", from: first, "float", ["reused: false"])
        XCTAssertTrue(app.windows.containing(.any, identifier: "float.\(floated)").firstMatch.exists(within: 5))
        let still = try await snapshot()["focused_pane_id"] as? String
        XCTAssertEqual(still, focus)
        try await run("cd /tmp && rm -rf \(folder)", in: first, "clean", 0)
    }

    /// `ovvi open git .` puts the Git card beside the shell with no tab of its own on the way: herdr makes a labeled
    /// pane only as a new tab, which the app hides until its move.
    func testOpenBesideShowsNoTemporaryTab() async throws {
        let (tab, first) = try await newTab("beside")
        try await closeNew("tab", besides: tabIDs())
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        try await waitForPrompt(first)
        _ = try await cardsFolder(in: first)
        let tabs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES 'tab\\.[^.]+'"))
        let count = tabs.count
        // Sampled until the card shows and 0.5 s more: a late snapshot of the temporary tab lands after the answer.
        // Each card closes after its round, so the shell keeps its width.
        for round in 0 ..< 3 {
            try await send("clear; \(Self.ovviCommand) open git . --new; echo git\(round)-$((6*7))-$?\r", to: first)
            var most = count, drawn: Date?, card: String?
            let end = Date.now + 15
            while drawn.map({ Date.now.timeIntervalSince($0) < 0.5 }) ?? (Date.now < end) {
                most = max(most, tabs.count)
                let text = try await read(first, "recent_unwrapped")
                if card == nil, text.contains("git\(round)-42-0") {
                    card = text.matches(of: /\npane: (\S+)/).last.map { String($0.1) }
                }
                if drawn == nil, let card, element("pane.\(card)").exists {
                    drawn = .now
                }
            }
            XCTAssertNotNil(drawn, "round \(round): no card \(card ?? "named")")
            XCTAssertEqual(most, count, "round \(round): a tab showed on the way")
            if let card {
                _ = try await Self.call(one, "pane.close", ["pane_id": card])
            }
        }
    }

    func testRevealCardShownAndReplace() async throws {
        relaunch(one, Self.agentHold)
        let (tab, first) = try await newTab("reveal")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        try await waitForPrompt(first)
        try await expectOpen("w2")
        let folder = try await cardsFolder(in: first), ovvi = Self.ovviCommand

        let browser = try await open("browser ./one.html", from: first, "web", ["kind: browser"])
        let web = try await paneLabel(browser), iid = web.prefix { $0 != " " }.dropFirst("ovvi:browser".count)
        XCTAssertTrue(web.hasSuffix(" file://\(folder)/one.html"), web)
        XCTAssertTrue(pageText("ovvi-cards-one").exists(within: 10))
        _ = try await open("browser './two.html?v=2#x' --replace \(browser)", from: first, "page", ["kind: browser"])
        XCTAssertTrue(pageText("ovvi-cards-two").exists(within: 10))
        let query = try await paneLabel(browser)
        XCTAssertTrue(query.hasSuffix(" file://\(folder)/two.html?v=2#x"), query)
        XCTAssertTrue(element("browser.\(browser).back").has(\.isEnabled, true, within: 5))
        try await run("\(ovvi) open git . --replace \(first)", in: first, "terminal", 1,
                      "ovvi: pane \(first) is no")
        _ = try await open("git . --replace \(browser)", from: first, "replace", ["kind: git"])
        let label = try await paneLabel(browser)
        XCTAssertEqual(label, "ovvi:git\(iid) /private\(folder)/")
        try await run("clear; \(ovvi) card \(browser)", in: first, "card", 0, "kind: git", "shown: true")
        try await run("clear; \(ovvi) card \(first)", in: first, "terminal-card", 0, "kind: terminal")
        try await run("clear; \(ovvi) shown", in: first, "shown", 0, "windows: 1")
        let shown = try await read(first).split(separator: "\n").first { $0.hasPrefix("shown: ") } ?? ""
        XCTAssertTrue(shown.contains(first) && shown.contains(browser), String(shown))

        try await run("clear; \(ovvi) reveal \(browser)", in: first, "flash", 0, "shown: true")
        XCTAssertTrue(element("pane.\(browser).flash").exists(within: 3))

        // Split, and off balance: the Balance Splits below makes a write that herdr shows.
        let (other, beside) = try await createTab(in: "w2")
        closeAfter("tab", other)
        try await split(beside)
        try await Self.call(one, "layout.set_split_ratio", ["tab_id": other, "path": [Bool](), "ratio": 0.3])
        XCTAssertTrue(element("tab.\(other)").exists(within: 5))
        element("tab.\(other)").click()
        XCTAssertTrue(element("tab.\(other)").has(\.isSelected, true, within: 3))
        try await run("clear; \(ovvi) reveal \(browser)", in: first, "notice", 0, "shown: false")
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts.matching(NSPredicate(format: "value CONTAINS 'points to ovvi-e2e-cards'"))
            .firstMatch.exists(within: 3))
        // Balance Splits: a write of the user's own, which leaves an agent's notice up. By its menu item: a global
        // hotkey on this Mac takes ⌥⌘= ahead of the app.
        pick("Pane", "Balance Splits")
        // A write drops old notices ahead of its herdr call, so once herdr has the balance, any drop has happened.
        try await expect("the balance in herdr") { try await abs((root(other)["ratio"] as? Double ?? 0) - 0.5) < 0.01 }
        XCTAssertFalse(notice.vanishes(within: 0.5))
        notice.buttons["notice.show"].click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))
        try await run("cd /tmp && rm -rf \(folder)", in: first, "clean", 0)
    }

    /// An agent's notices and flashes last 30 s: a query on CI can take seconds.
    static let agentHold = ["-agentHoldSeconds", "30"]

    /// The path as the shell has it: macOS's /tmp, not /private/tmp.
    private func cardsFolder(in pane: String) async throws -> String {
        let folder = "/tmp/ovvi-e2e-cards"
        try await run("rm -rf \(folder) && mkdir \(folder) && cd \(folder) && git init -q && echo hi >notes.md "
            + "&& echo '<p>ovvi-cards-one</p>' >one.html && echo '<p>ovvi-cards-two</p>' >two.html",
            in: pane, "folder", 0)
        return folder
    }

    private func open(_ args: String, from pane: String, _ marker: String, _ lines: [String]) async throws -> String {
        try await run("clear; \(Self.ovviCommand) open \(args)", in: pane, marker, 0)
        let text = try await read(pane)
        for line in lines {
            XCTAssertTrue(text.contains("\n\(line)"), "\(line) in:\n\(text)")
        }
        return try await answered(pane)
    }

    private func answered(_ pane: String) async throws -> String {
        let text = try await read(pane)
        guard let match = text.firstMatch(of: /\npane: (\S+)/)
        else { throw Failed(description: "no pane in:\n\(text)") }
        return String(match.1)
    }
}
