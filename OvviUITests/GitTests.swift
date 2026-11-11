import XCTest

extension OvviUITests {
    func testGitCardCommitsPushesAndOpensDiffs() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("git")
        try await waitForPrompt(left)
        let repo = "/tmp/ovvi-e2e-git", root = "/private/tmp/ovvi-e2e-git"
        let hash = try await makeRepo(repo, in: left)
        try await show(tab)
        let card = try await split(left)
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "ovvi:git#e2egit \(root)/"])

        let home = element("git.\(card).page")
        XCTAssertTrue(commit("on the side", in: home).exists(within: 10))
        XCTAssertTrue(commit("second", in: home).exists)
        XCTAssertTrue(home.buttons["Untracked: b.md"].exists)
        keepScreenshot("git home")
        try await commitAndPush(home, card: card, shell: left, repo: repo)

        commit("second", in: home).click()
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "e2e commit", within: 10))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(commit("second", in: home).has(\.isHittable, true, within: 10))
        commit("second", in: home).doubleClick()
        try await expect("the label names the commit") { try await paneLabel(card).hasSuffix(" \(root)/ \(hash)") }
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "second", within: 10))
        let page = element("git.\(card).page")
        XCTAssertTrue(page.buttons["Open a.txt"].exists(within: 10))
        XCTAssertFalse(page.buttons["Open b.md"].exists)
        element("pane.\(card).go-back").click()
        try await expect("back home") { try await paneLabel(card).hasSuffix("e2egit \(root)/") }
        element("pane.\(card).go-forward").click()
        try await expect("forward to the commit") { try await paneLabel(card).hasSuffix(" \(root)/ \(hash)") }
        try await diff(page, card: card, tab: tab, root: root)
        try await workingTree(home, page, card: card, root: root, shell: left)
        element("pane.\(card).diff.home").click()
        let branch = element("pane.\(card).git.branch")
        XCTAssertTrue(branch.has(\.isHittable, true, within: 5))
        branch.click()
        branch.menuItems["side"].click()
        let toast = element("pane.\(card).toast")
        XCTAssertTrue(until(10) { toast.stringValue.contains("overwritten") })
        element("pane.\(card).toast.main").click()
        try await revert(home, page, card: card, shell: left, repo: repo)
        branch.click()
        branch.menuItems["side"].click()
        try await expectGit("branch --show-current", "side", in: left, repo: repo)
        try await send("cd / && rm -rf \(repo) \(repo).git\r", to: left)
    }

    func testGitHomeInitializesCommitsAllAndShowsMore() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("git-new")
        try await waitForPrompt(left)
        let folder = "/tmp/ovvi-e2e-git-new", root = "/private/tmp/ovvi-e2e-git-new"
        try await send(
            "rm -rf \(folder) && mkdir \(folder) && cd \(folder) && clear && echo ready-$((6*7))\r",
            to: left,
        )
        try await waitFor(left) { $0.contains("ready-42") }
        try await show(tab)
        let card = try await split(left)
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "ovvi:git#e2enew \(root)/"])
        let home = element("git.\(card).page")
        let initialize = home.buttons["Initialize Repository"]
        XCTAssertTrue(initialize.has(\.isHittable, true, within: 10))
        XCTAssertTrue(text("Not a Git repository", in: home).exists)
        initialize.click()
        XCTAssertTrue(text("No changes", in: home).exists(within: 10))
        XCTAssertFalse(home.textViews["Message"].exists)
        try await expectGit("rev-parse --is-inside-work-tree", "true", in: left, repo: folder)

        try await send("git config user.name e2e && git config user.email e2e@ovvi && git config commit.gpgsign false "
            + "&& seq 501 | awk -v ref=$(git symbolic-ref HEAD) '{printf \"commit %s\\n"
            + "committer e2e <e2e@ovvi> %d +0000\\ndata <<E\\nc%d\\nE\\n\\n\", ref, 1000000000+$1, $1}' "
            + "| git fast-import --quiet && echo a >a.txt && clear\r",
            to: left)
        let message = home.textViews["Message"]
        XCTAssertTrue(message.has(\.isHittable, true, within: 10))
        message.click()
        message.typeText("all of it")
        home.buttons["Commit All"].click()
        try await expectGit("log -1 --format=%s", "all of it", in: left, repo: folder)
        XCTAssertTrue(text("No changes", in: home).exists(within: 10))

        let more = home.buttons["Show More"], first = commit("c1", in: home)
        XCTAssertTrue(more.exists(within: 10))
        XCTAssertFalse(first.exists)
        more.click()
        XCTAssertTrue(first.exists(within: 10))
        XCTAssertFalse(more.exists)
        try await send("cd / && rm -rf \(folder)\r", to: left)
    }

    private func workingTree(_ home: XCUIElement, _ page: XCUIElement, card: String, root: String,
                             shell left: String) async throws
    {
        element("pane.\(card).diff.home").click()
        XCTAssertTrue(home.buttons["Modified: a.txt"].exists(within: 10))
        home.buttons["Modified: a.txt"].click()
        try await expect("the label is Working Tree's") { try await paneLabel(card).hasSuffix(" \(root)/ uncommitted") }
        XCTAssertTrue(page.buttons["Open a.txt"].exists(within: 10))
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "Working Tree", within: 3))
        try await send("seq 300 | sed 's/^/new /' >c.txt\r", to: left)
        XCTAssertTrue(page.buttons["Open c.txt"].exists(within: 10))
        try await send("sed -i '' 's/^changed 200$/live 200/' a.txt\r", to: left)
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'live 200'")).firstMatch
            .exists(within: 10))
        try await holdsItsPlace(page, card: card, shell: left)
        stepsByFile(page)

        element("pane.\(card).diff.home").click()
        try await expect("back home") { try await paneLabel(card).hasSuffix("e2egit \(root)/") }
        element("pane.\(card).git.working").click()
        try await expect("Working Tree from row 2") { try await paneLabel(card).hasSuffix(" \(root)/ uncommitted") }
    }

    private func holdsItsPlace(_ page: XCUIElement, card: String, shell left: String) async throws {
        let list = element("pane.\(card).diff.file-list")
        list.click()
        XCTAssertTrue(page.buttons["c.txt"].has(\.isHittable, true, within: 3))
        page.buttons["c.txt"].click()
        let header = page.buttons["Open c.txt"]
        XCTAssertTrue(header.exists(within: 3))
        let top = header.frame.minY
        XCTAssertLessThan(top, page.frame.minY + 50, "c.txt is not at the top: \(top), page \(page.frame)")
        try await send("sed -i '' 's/^line 250$/x250/' a.txt\r", to: left)
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'x250'")).firstMatch.exists(within: 10))
        XCTAssertEqual(header.frame.minY, top, accuracy: 2, "c.txt moved")
        list.click()
    }

    private func stepsByFile(_ page: XCUIElement) {
        let header = page.buttons["Open c.txt"], top = page.frame.minY + 50
        XCTAssertLessThan(header.frame.minY, top, "c.txt is not at the top: \(header.frame), page \(page.frame)")
        page.staticTexts.matching(NSPredicate(format: "value == 'new 3'")).firstMatch.click()
        app.typeKey("[", modifierFlags: .shift)
        XCTAssertTrue(until(3) { header.frame.minY > top }, "⇧[ left c.txt at \(header.frame)")
        app.typeKey("]", modifierFlags: .shift)
        XCTAssertTrue(until(3) { header.frame.minY < top }, "⇧] put c.txt at \(header.frame)")
    }

    private func revert(_ home: XCUIElement, _ page: XCUIElement, card: String, shell left: String,
                        repo: String) async throws
    {
        let toast = element("pane.\(card).toast"), yes = element("pane.\(card).toast.main")
        try await send("echo d >d.txt\r", to: left)
        XCTAssertTrue(home.buttons["Untracked: d.txt"].exists(within: 10))
        home.buttons["Modified: a.txt"].hover()
        keepScreenshot("git home, revert")
        home.buttons["Revert a.txt"].click()
        XCTAssertTrue(until(5) { toast.stringValue.contains("Revert changes to a.txt?") }, toast.stringValue)
        yes.click()
        XCTAssertTrue(home.buttons["Modified: a.txt"].vanishes(within: 10))
        XCTAssertTrue(home.buttons["Untracked: c.txt"].exists)
        home.buttons["Revert All Changes"].click()
        XCTAssertTrue(
            until(5) { toast.stringValue.contains("Revert all 2 files? This deletes the new files c.txt, d.txt.") },
            toast.stringValue,
        )
        yes.click()
        XCTAssertTrue(text("No changes", in: home).exists(within: 10))
        try await expectGit("status --porcelain | wc -l", "0", in: left, repo: repo)

        element("pane.\(card).git.working").click()
        XCTAssertTrue(element("pane.\(card).diff.file-list").has(\.isEnabled, false, within: 10))
        XCTAssertTrue(text("No changes", in: page).exists)
        keepScreenshot("working tree, no changes")
        element("pane.\(card).diff.home").click()
    }

    private func commitAndPush(_ home: XCUIElement, card: String, shell left: String, repo: String) async throws {
        home.buttons["Untracked: b.md"].hover()
        home.buttons["Stage b.md"].click()
        XCTAssertTrue(home.buttons["Added: b.md"].exists(within: 5))
        home.buttons["Unstage b.md"].click()
        XCTAssertTrue(home.buttons["Untracked: b.md"].exists(within: 5))
        home.buttons["Stage b.md"].click()
        XCTAssertTrue(home.buttons["Added: b.md"].exists(within: 5))
        try await expectGit("diff --cached --name-only", "b.md", in: left, repo: repo)
        let message = home.textViews["Message"]
        message.click()
        message.typeText("e2e commit")
        home.buttons["Commit"].click()
        try await expectGit("log -1 --format=%s", "e2e commit", in: left, repo: repo)
        XCTAssertTrue(commit("e2e commit", in: home).exists(within: 5))
        XCTAssertTrue(element("pane.\(card).git.push").has(\.label, "Push, 1 ahead", within: 5))
        element("pane.\(card).git.push").click()
        try await expectGit("--git-dir \(repo).git log -1 --format=%s main", "e2e commit", in: left, repo: repo)
    }

    private func diff(_ page: XCUIElement, card: String, tab: String, root: String) async throws {
        let surface = element("pane.\(card)"), title = element("pane.\(card).title")
        XCTAssertTrue(surface.has(\.label, "second", within: 10), surface.label)
        // XCUITest sees no blank frame: Parent's draw in one step goes unchecked here.
        page.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Parent '")).firstMatch.click()
        XCTAssertTrue(title.has(\.stringValue, "first", within: 10), title.stringValue)
        element("pane.\(card).go-back").click()
        XCTAssertTrue(title.has(\.stringValue, "second", within: 10), title.stringValue)
        // Clicks in the page wait for what it draws: its layout comes back late after the card hides.
        let open = page.buttons["Open a.txt"]
        XCTAssertTrue(open.has(\.isHittable, true, within: 3))
        _ = try await opens("\(root)/a.txt", beside: tab) { open.click() }
        try await show(tab)
        let viewed = page.checkBoxes["Viewed a.txt"], line = page.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH 'line'"),
        ).firstMatch
        XCTAssertTrue(viewed.has(\.isHittable, true, within: 3) && line.exists)
        viewed.click()
        XCTAssertTrue(line.vanishes(within: 3))
        viewed.click()
        XCTAssertTrue(line.exists(within: 3))

        let far = page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'far290'")).firstMatch
        XCTAssertFalse(far.exists)
        element("pane.\(card).diff.next").click()
        element("pane.\(card).diff.next").click()
        XCTAssertTrue(far.has(\.isHittable, true, within: 3))
        try await commandClick(far, behind: tab, root: root)
        try await show(tab)
        try await sideBySide(card, page, far)
        XCTAssertTrue(far.has(\.isHittable, true, within: 3), "far \(far.frame), page \(page.frame)")
        try await commandClick(far, behind: tab, root: root)
        try await show(tab)
    }

    private func commit(_ subject: String, in home: XCUIElement) -> XCUIElement {
        home.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", subject + ",")).firstMatch
    }

    /// Within a few tries: the app's write may still run.
    private func expectGit(_ command: String, _ expected: String, in pane: String, repo: String) async throws {
        try await expect("git \(command) gives \(expected)", times: 10) {
            try await send("clear && git -C \(repo) \(command); echo done-$((6*7))\r", to: pane)
            try await waitFor(pane) { $0.contains("done-42") }
            return try await read(pane).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .contains(expected)
        }
    }

    private func commandClick(_ line: XCUIElement, behind tab: String, root: String) async throws {
        let file = try await opens("\(root)/a.txt", beside: tab, behind: true) {
            XCUIElement.perform(withKeyModifiers: .command) { line.click() }
        }
        let editor = element("file.\(file).page").textViews.firstMatch
        XCTAssertTrue(until(5) { (editor.value as? String)?.contains("far290") == true })
    }

    private func sideBySide(_ card: String, _ page: XCUIElement, _ far: XCUIElement) async throws {
        let wrap = element("pane.\(card).diff.wrap")
        let wide = page.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'wide292'")).firstMatch
        let next = page.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'line 293'")).firstMatch
        XCTAssertTrue(wide.exists && next.exists)
        let gap = { next.frame.minY - wide.frame.minY }, row = gap()
        wrap.click()
        XCTAssertTrue(until(3) { gap() > row * 2 }, "one row \(row), wrapped \(gap())")
        wrap.click()
        XCTAssertTrue(until(3) { gap() < row * 1.5 }, "one row \(row), now \(gap())")
        element("pane.\(card).diff.layout.side by side").click()
        XCTAssertTrue(wrap.has(\.isEnabled, false, within: 3))
        let old = page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'line 290'")).firstMatch
        XCTAssertTrue(until(3) {
            old.exists && abs(old.frame.minY - far.frame.minY) < 2 && old.frame.maxX < far.frame.minX
        }, "old \(old.exists ? old.frame : .zero), new \(far.exists ? far.frame : .zero)")
        keepScreenshot("diff card, side by side")
        XCTAssertFalse(page.buttons["a.txt"].exists)
        element("pane.\(card).diff.file-list").click()
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 3))
        element("pane.\(card).diff.file-list").click()
        XCTAssertTrue(page.buttons["a.txt"].vanishes(within: 3))
    }

    private func makeRepo(_ repo: String, in pane: String) async throws -> String {
        try await send("rm -rf \(repo) \(repo).git && git init -q --bare -b main \(repo).git && mkdir \(repo) "
            + "&& cd \(repo) && git init -q -b main && git config user.name e2e && git config user.email e2e@ovvi "
            + "&& git config commit.gpgsign false && git remote add origin \(repo).git "
            + "&& seq 300 | sed 's/^/line /' >a.txt && git add a.txt "
            + "&& git commit -qm first && git switch -qc side && echo s >s.txt && git add s.txt "
            + "&& git commit -qm 'on the side' && git switch -q main "
            + "&& sed -i '' '1,150s/line/LINE/; s/^line 292$/wide292\(String(repeating: " wrap", count: 60))/; "
            + "s/^line 290$/far290/' a.txt "
            + "&& git commit -qam second && git push -qu origin main && echo new >b.md "
            + "&& sed -i '' 's/^line 200$/changed 200/' a.txt && clear && echo ready-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("ready-42") }
        try await send("clear && git -C \(repo) rev-parse HEAD\r", to: pane)
        return try await poll("HEAD's hash") {
            try await read(pane).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }
        }
    }

    private func opens(_ path: String, beside tab: String, behind: Bool = false,
                       _ action: () -> Void) async throws -> String
    {
        let before = try await tabIDs()
        action()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        try await expectBeside(opened, tab)
        if behind {
            XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected }, "\(opened) took the selection")
            try await show(opened)
        } else {
            XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 5))
        }
        let pane = try await pane(of: opened), label = try await paneLabel(pane)
        XCTAssertTrue(label.hasPrefix("ovvi:explorer#") && label.hasSuffix(" \(path)"), label)
        return pane
    }
}
