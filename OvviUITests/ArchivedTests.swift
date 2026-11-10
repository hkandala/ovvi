import XCTest

extension OvviUITests {
    /// The resume only past a check for Claude Code: the new pane's shell would start the real one.
    func testArchivedListsClosedSessionsFiltersAndResumes() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let id = UUID().uuidString.lowercased()
        // herdr names /tmp by its real path.
        let folder = "/private/tmp/ovvi-e2e-archived-cwd/\(id.prefix(8))"
        let (_, shell) = try await newTab("archived")
        try await waitForPrompt(shell)
        try await writeSessions(id, in: folder, shell)
        openArchived()
        let first = element("agents.archived.claude.\(id)"), second = element("agents.archived.pi.2026_\(id).jsonl")
        XCTAssertTrue(first.exists(within: 5))
        XCTAssertTrue(second.exists(within: 2))
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        XCTAssertEqual(first.label, "Rename the CLI, \(folder)")
        XCTAssertEqual(second.label, "Trip notes, \(folder)")
        keepScreenshot("archived shelf")

        filters(first, second)
        try await resumes(first, id, in: folder, shell)
    }

    func testArchivedReadsTheNextPageAtItsEnd() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        try await writePages()
        let shelf = openArchived()
        let first = element("agents.archived.pi.page-1.jsonl"), last = element("agents.archived.pi.page-55.jsonl")
        XCTAssertTrue(first.exists(within: 5))
        XCTAssertEqual(first.label, "Page 1, /tmp")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'agents.archived.pi.page-'"))
        XCTAssertLessThan(rows.count, 20, "the lazy shelf built every row")
        let inside = shelf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 100))
        XCTAssertTrue(until(20) {
            inside.scroll(byDeltaX: 0, deltaY: -2000)
            return last.exists
        }, "the 55th session never came")
    }

    func testArchivedSearchSaysWhenNothingMatchesAndEscReturnsToThePane() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let (tab, shell) = try await writePages()
        element("tab.\(tab)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(shell)")))
        openArchived()
        XCTAssertTrue(element("agents.archived.pi.page-1.jsonl").exists(within: 5))
        let search = element("agents.archived.search"), window = app.windows.firstMatch
        let shelf = element("agents.shelf.Archived Sessions"), top = shelf.frame.minY
        search.typeText("no such session")
        XCTAssertTrue(window.staticTexts["No sessions found."].exists(within: 10))
        XCTAssertEqual(shelf.frame.minY, top, "no match moved the header")
        keepScreenshot("archived search, no match")
        search.typeKey("a", modifierFlags: .command)
        search.typeText("Page 55")
        XCTAssertTrue(element("agents.archived.pi.page-55.jsonl").exists(within: 10))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("agents.shelf.Archived Sessions").has(\.stringValue, "collapsed", within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.\(shell)")))
    }

    @discardableResult
    func writePages() async throws -> (tab: String, shell: String) {
        let (tab, shell) = try await newTab("archived-pages")
        try await waitForPrompt(shell)
        let dir = "\(Self.archivedHome)/.pi/agent/sessions/--p--"
        let line = #"{"type":"session","version":3,"cwd":"/tmp"}"#
        let prompt = #"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"Page '$i'"}]}}"#
        let write = "f=\(dir)/page-$i.jsonl; printf '%s\\n' '\(line)' '\(prompt)' >$f; "
            + "touch -t $(date -v-${i}H +%Y%m%d%H%M.%S) $f"
        try await send("rm -rf \(Self.archivedHome) && mkdir -p \(dir) && for i in $(seq 1 55); do \(write); done && "
            + "clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        return (tab, shell)
    }

    func testArchivedShowsTheOthersPastAStuckAgent() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        try await writeStuckStores()
        showsTheOthersPastAStuckAgent(on: "This Mac")
    }

    func writeStuckStores() async throws {
        let (_, shell) = try await newTab("archived-stuck")
        try await waitForPrompt(shell)
        let piStore = "\(Self.archivedHome)/.pi/agent/sessions/--s--"
        let claudeStore = "\(Self.archivedHome)/.claude/projects/s"
        let line = #"{"type":"session","version":3,"cwd":"/tmp"}"#
        let prompt = #"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"Read on"}]}}"#
        try await send("rm -rf \(Self.archivedHome) && mkdir -p \(piStore) \(claudeStore) && "
            + "printf '%s\\n' '\(line)' '\(prompt)' >\(piStore)/stuck.jsonl && mkfifo \(claudeStore)/stuck.jsonl && "
            + "clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
    }

    func showsTheOthersPastAStuckAgent(on machine: String) {
        let shelf = openArchived(), top = shelf.frame.minY, window = app.windows.firstMatch
        let row = element("agents.archived.pi.stuck.jsonl")
        let failure = window.staticTexts["Could not read Claude Code sessions on \(machine)."]
        XCTAssertTrue(row.exists(within: 15))
        XCTAssertEqual(shelf.frame.minY, top, "the rows moved the header")
        XCTAssertFalse(failure.exists, "the rows waited for Claude Code's 10 s")
        XCTAssertTrue(failure.exists(within: 15))
        XCTAssertTrue(window.buttons["Retry"].exists)
        XCTAssertTrue(row.exists)
        XCTAssertEqual(shelf.frame.minY, top, "the failure moved the header")
        keepScreenshot("archived stuck agent")
    }

    @discardableResult
    func openArchived() -> XCUIElement {
        let shelf = element("agents.shelf.Archived Sessions")
        XCTAssertTrue(shelf.exists(within: 3))
        if shelf.value as? String == "expanded" {
            shelf.click()
            XCTAssertTrue(shelf.has(\.stringValue, "collapsed", within: 2))
        }
        shelf.click()
        XCTAssertTrue(hasKeyboard("agents.archived.search"))
        addTeardownBlock { @MainActor [self] in
            let shelf = element("agents.shelf.Archived Sessions")
            if shelf.exists, shelf.value as? String == "expanded" {
                shelf.click()
            }
        }
        XCTAssertTrue(shelf.has(\.stringValue, "expanded", within: 2))
        // A run that stops midway leaves another agent picked.
        let menu = element("agents.archived.filter")
        if menu.value as? String != "All Agents" {
            menu.click()
            menu.menuItems["All Agents"].click()
        }
        return shelf
    }

    private func filters(_ claude: XCUIElement, _ piRow: XCUIElement) {
        let search = element("agents.archived.search")
        search.click()
        search.typeText("trip")
        XCTAssertTrue(claude.vanishes(within: 2))
        XCTAssertTrue(piRow.exists)
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(claude.exists(within: 2))
        let menu = element("agents.archived.filter")
        menu.click()
        menu.menuItems["Pi"].click()
        XCTAssertTrue(claude.vanishes(within: 2))
        XCTAssertTrue(piRow.exists)
        XCTAssertEqual(menu.value as? String, "Pi")
        menu.click()
        menu.menuItems["All Agents"].click()
        XCTAssertTrue(claude.exists(within: 2))
    }

    /// Written by the shell: the test runner may not write to /tmp.
    private func writeSessions(_ id: String, in folder: String, _ shell: String) async throws {
        let home = Self.archivedHome
        let files = [
            (".claude/projects/x/\(id).jsonl", 2 * 3600.0, """
            {"type":"user","message":{"role":"user","content":"rename it"},"cwd":"\(folder)","sessionId":"\(id)"}
            {"type":"custom-title","customTitle":"Rename the CLI","sessionId":"\(id)"}
            """),
            (".pi/agent/sessions/--x--/2026_\(id).jsonl", 2 * 86400.0, """
            {"type":"session","version":3,"id":"\(id)","cwd":"\(folder)"}
            {"type":"message","id":"a","message":{"role":"user","content":[{"type":"text","text":"Trip notes"}]}}
            """),
        ]
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "yyyyMMddHHmm.ss"
        let writes = files.map { path, age, text in
            let file = "\(home)/\(path)", dir = (file as NSString).deletingLastPathComponent
            return "mkdir -p \(dir) && echo \(Data(text.utf8).base64EncodedString()) | base64 -d >\(file) && "
                + "touch -t \(time.string(from: Date(timeIntervalSinceNow: -age))) \(file)"
        }
        try await send("rm -rf \(home) /private/tmp/ovvi-e2e-archived-cwd && mkdir -p \(folder) && "
            + writes.joined(separator: " && ") + " && clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
    }

    /// Not where the new pane's shell would start a real Claude Code; CI's is the stand-in, which only exits.
    private func resumes(_ row: XCUIElement, _ id: String, in folder: String, _ pane: String) async throws {
        try await skipIfThisMacHasClaude(pane, "the resume would start")
        let before = try await workspaceIDs()
        closeNew("workspace", besides: before)
        row.click()
        XCTAssertTrue(row.vanishes(within: 2))
        var resumed: String?
        try await expect("a new workspace in the folder") {
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
            resumed = panes.first { pane in
                !before.contains { pane["workspace_id"] as? String == $0 } && pane["cwd"] as? String == folder
            }?["pane_id"] as? String
            return resumed != nil
        }
        // Wrapped at the pane's width.
        try await waitFor(XCTUnwrap(resumed), toShow: "claude --resume \(id)")
        XCTAssertTrue(row.exists(within: 15))
    }
}
