import XCTest

extension OvviUITests {
    /// ⇧⌘C copies the keyboard card's address: a terminal's folder, a browser's URL, File Explorer's open file, Git's
    /// commit and an agent's session id.
    func testCopyAddressCopiesEachCardsAddress() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("copy")
        try await waitForPrompt(shell)
        let folder = "/tmp/ovvi-e2e-copy", root = "/private/tmp/ovvi-e2e-copy"
        try await send("rm -rf \(folder) && mkdir \(folder) && cd \(folder) && git init -q -b main "
            + "&& git config user.name e2e && git config user.email e2e@ovvi && git config commit.gpgsign false "
            + "&& echo a >a.txt && printf '<p>ovvi-copy-page</p>' >page.html && git add a.txt && git commit -qm one "
            + "&& clear && git rev-parse HEAD\r", to: shell)
        sendAfter("cd / && rm -rf \(folder)\r", to: shell)
        let hash = try await poll("HEAD's hash") {
            try await read(shell).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }
        }
        try await show(tab)
        let browser = try await split(shell), explorer = try await split(browser, "down")
        let git = try await split(shell, "down")
        try await relabel(browser, "ovvi:browser#e2ecpb file://\(root)/page.html")
        try await relabel(explorer, "ovvi:explorer#e2ecpe \(root)/a.txt")
        try await relabel(git, "ovvi:git#e2ecpg \(root)/ \(hash)")
        XCTAssertTrue(pageText("ovvi-copy-page").exists(within: 10))

        func copies(_ card: String, _ expected: (String) -> Bool) {
            let target = element(card == shell ? "terminal.\(card)" : "pane.\(card).title")
            XCTAssertTrue(target.has(\.isHittable, true, within: 5), "\(card) is not drawn")
            target.click()
            // Again until it holds: the app's snapshot can still lack a session herdr took.
            XCTAssertTrue(until(10) {
                NSPasteboard.general.clearContents()
                app.typeKey("c", modifierFlags: [.command, .shift])
                return until(1) { NSPasteboard.general.string(forType: .string).map(expected) == true }
            }, "\(card): \(NSPasteboard.general.string(forType: .string) ?? "nothing copied")")
        }
        copies(shell) { $0.hasSuffix("/tmp/ovvi-e2e-copy") }
        copies(browser) { $0 == "file://\(root)/page.html" }
        copies(explorer) { $0 == "\(root)/a.txt" }
        copies(git) { $0 == hash }
        try await relabel(git, "ovvi:git#e2ecpg \(root)/ uncommitted")
        copies(git) { $0 == root }

        let id = UUID().uuidString.lowercased()
        // The state ahead of the session: herdr takes no state report after it.
        try await report(shell, "working", agent: "claude")
        try await Self.call(one, "pane.report_agent_session", ["pane_id": shell, "source": "herdr:claude",
                                                               "agent": "claude", "agent_session_id": id])
        copies(shell) { $0 == id }
    }
}
