import XCTest

extension OvviUITests {
    func testFileExplorerBrowsesOpensAndGoesBack() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-files", root = "/private/tmp/ovvi-e2e-files"
        try await makeTreeRepo(repo, in: shell)
        let card = try await newCard("ovvi:explorer#e2efil \(root)/", cwd: repo).pane

        let tree = element("files.\(card).page")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        let back = element("pane.\(card).go-back").frame
        XCTAssertEqual(row("..", in: tree).frame.minY - back.maxY, 11, accuracy: 1, "\(back)")
        XCTAssertTrue(row("build", in: tree).exists)
        XCTAssertFalse(row("main.swift", in: tree).exists)
        XCTAssertTrue(hasKeyboard(row("..", in: tree)))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(row("..", in: tree)))
        openAndCollapse(card, tree)
        try await send("touch new.md src/deep/a.swift\r", to: shell)
        XCTAssertTrue(row("new.md", in: tree).exists(within: 5))
        keepScreenshot("file explorer home")
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, "explorer", within: 3))
        app.typeKey(.escape, modifierFlags: [])

        app.typeText("main")
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 5))
        XCTAssertFalse(row("a.txt", in: tree).exists)
        let tabs = try await tabIDs()
        row("main.swift", in: tree).doubleClick()
        let file = element("file.\(card).page")
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        try await labelEnds(card, " \(root)/src/deep/main.swift")
        let after = try await tabIDs()
        XCTAssertEqual(after, tabs)
        keepScreenshot("file explorer file")

        try await backAndForward(card, tree, file, root)
        // Each folder in the path is a button; the file's name is not.
        XCTAssertTrue(element("pane.\(card).jump.2").exists(within: 3))
        XCTAssertFalse(element("pane.\(card).jump.3").exists)
        element("pane.\(card).jump.1").hover()
        keepScreenshot("a folder in the path, under the pointer")
        element("pane.\(card).jump.1").click()
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 10))
        XCTAssertTrue(until(3) { hasKeyboard(row("main.swift", in: tree)) })
        XCTAssertTrue(element("pane.\(card).go-forward").has(\.isEnabled, false, within: 3))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        element("pane.\(card).go-back").click()
        try await labelEnds(card, " \(root)/")

        try await moveRoot(card, tree, root)
        floatsWithRoomUnderTheRow(card) { self.row("..", in: self.element("files.\(card).page", in: $0)) }
        try await send("rm -rf \(repo)\r", to: shell)
    }

    func testFileExplorerShowsTheTreeBesideAFile() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files side")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-side", root = "/private/tmp/ovvi-e2e-side"
        try await makeTreeRepo(repo, in: shell)
        let card = try await newCard("ovvi:explorer#e2esid \(root)/", cwd: repo).pane
        let tree = element("files.\(card).page"), file = element("file.\(card).page")
        let toggle = element("pane.\(card).tree")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        row("a.txt", in: tree).doubleClick()
        try await labelEnds(card, " \(root)/a.txt")
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        // A run that failed midway left the card's choice in its state file.
        if toggle.isSelected {
            toggle.click()
        }
        XCTAssertFalse(until(1) { self.row("src", in: file).exists }, "the tree shows with Show only the file")

        step("The tree beside the file: a click selects, a double-click shows the file")
        toggle.click()
        XCTAssertTrue(toggle.has(\.isSelected, true, within: 3))
        XCTAssertTrue(row("src", in: file).exists(within: 10))
        XCTAssertLessThan(row("src", in: file).frame.maxX, file.textViews.firstMatch.frame.minX)
        row("build", in: file).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("out.o", in: file).exists(within: 3))
        row("src", in: file).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("deep", in: file).exists(within: 3))
        row("deep", in: file).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("main.swift", in: file).exists(within: 3))
        row("main.swift", in: file).click()
        XCTAssertFalse(until(1) { file.textViews.firstMatch.stringValue.contains("print(1)") }, "a click opened it")
        row("main.swift", in: file).doubleClick()
        try await labelEnds(card, " \(root)/src/deep/main.swift")
        XCTAssertTrue(until(5) { file.textViews.firstMatch.stringValue.contains("print(1)") })
        XCTAssertTrue(row("out.o", in: file).exists && toggle.isSelected, "the tree kept its open folders")
        keepScreenshot("file explorer, the tree beside a file")
        try await upCollapseAndClose(card, tree: tree, file: file, root: root)
        try await send("rm -rf \(repo)\r", to: shell)
    }

    /// The tree's page and the tree beside a file are one tree: its scroll and its open folders go both ways.
    func testFileExplorerKeepsOneTreeForItsPageAndItsFiles() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files one")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-one", root = "/private/tmp/ovvi-e2e-one"
        try await makeTreeRepo(repo, in: shell)
        try await send("touch \(repo)/f{10..49}.txt && echo made-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
        let card = try await newCard("ovvi:explorer#e2eone \(root)/", cwd: repo).pane
        let tree = element("files.\(card).page"), file = element("file.\(card).page")
        let toggle = element("pane.\(card).tree")
        XCTAssertTrue(row("build", in: tree).exists(within: 10))
        row("build", in: tree).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("out.o", in: tree).exists(within: 3))
        // Part of the way: at its end the tree beside the file, with no status bar under it, would scroll less.
        tree.scroll(byDeltaX: 0, deltaY: -240)
        // A row in the middle: one under the status bar would scroll fully into view as it opens.
        let last = row("f20.txt", in: tree)
        let scrolled = until(3) {
            last.isHittable && !self.row("build", in: tree).isHittable && !self.row("f49.txt", in: tree).isHittable
        }
        XCTAssertTrue(scrolled, "the tree did not scroll")
        let top = last.frame.minY
        last.doubleClick()
        try await labelEnds(card, " \(root)/f20.txt")
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        // A run that failed midway left the card's choice in its state file.
        if toggle.isSelected {
            toggle.click()
        }

        step("Beside the file: the page's tree, where it was scrolled, with its open folders")
        toggle.click()
        let beside = row("f20.txt", in: file)
        XCTAssertTrue(beside.exists(within: 3))
        XCTAssertEqual(beside.frame.minY, top, accuracy: 1, "the tree beside the file scrolled elsewhere")
        beside.scroll(byDeltaX: 0, deltaY: 2000)
        XCTAssertTrue(row("out.o", in: file).exists(within: 3), "a new tree, with only the file's folders open")
        row("src", in: file).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("deep", in: file).exists(within: 3))

        step("Back on the tree's page: the folder opened beside the file is open")
        toggle.click()
        element("pane.\(card).jump.0").click()
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("f20.txt", in: tree).exists(within: 5))
        tree.scroll(byDeltaX: 0, deltaY: 2000)
        XCTAssertTrue(row("deep", in: tree).exists(within: 3))
        XCTAssertTrue(row("out.o", in: tree).exists)
        try await send("rm -rf \(repo)\r", to: shell)
    }

    private func upCollapseAndClose(_ card: String, tree: XCUIElement, file: XCUIElement, root: String) async throws {
        let toggle = element("pane.\(card).tree")
        step("Up past the root and back, with the file where it was")
        row("..", in: file).doubleClick()
        XCTAssertTrue(row("ovvi-e2e-side", in: file).exists(within: 10))
        row("ovvi-e2e-side", in: file).doubleClick()
        XCTAssertTrue(row("a.txt", in: file).exists(within: 10))
        try await labelEnds(card, " \(root)/src/deep/main.swift")

        step("Collapse the tree, the keys going to the file, then close the file")
        row("a.txt", in: file).click()
        toggle.click()
        XCTAssertTrue(row("a.txt", in: file).vanishes(within: 3))
        app.typeText("z")
        XCTAssertTrue(
            until(3) { file.textViews.firstMatch.stringValue.contains("z") },
            file.textViews.firstMatch.stringValue,
        )
        app.typeKey("z", modifierFlags: .command)
        toggle.click()
        XCTAssertTrue(row("a.txt", in: file).exists(within: 3))
        element("pane.\(card).jump.2").click()
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 10))
        row("a.txt", in: tree).doubleClick()
        try await labelEnds(card, " \(root)/a.txt")
        XCTAssertTrue(row("src", in: file).exists(within: 10), "the card's choice shows the tree again")
        toggle.click()
    }

    private func floatsWithRoomUnderTheRow(_ pane: String, first: (XCUIElement) -> XCUIElement) {
        let window = float(pane)
        let surface = element("float.\(pane)", in: window).frame
        let back = element("pane.\(pane).go-back", in: window).frame, row = first(window)
        XCTAssertTrue(row.exists(within: 5))
        XCTAssertEqual(row.frame.minY - back.maxY, back.minY - surface.minY, accuracy: 1, "\(back) over \(row.frame)")
        element("float.\(pane).detach").click()
        XCTAssertTrue(window.vanishes(within: 3))
    }

    private func backAndForward(_ card: String, _ tree: XCUIElement, _ file: XCUIElement, _ root: String) async throws {
        file.textViews.firstMatch.click()
        app.typeKey("[", modifierFlags: .command)
        XCTAssertFalse(until(1) { element("pane.\(card).go-forward").isEnabled }, "⌘[ went Back")
        file.textViews.firstMatch.click()
        app.typeKey("-", modifierFlags: .control)
        try await backToTheKeptTree(card, tree, root)
        row("out.o", in: tree).click()
        app.typeKey(.rightArrow, modifierFlags: .command)
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        file.textViews.firstMatch.click()
        app.typeKey(.leftArrow, modifierFlags: .command)
        XCTAssertFalse(until(1) { element("pane.\(card).go-forward").isEnabled }, "⌘← in the text went Back")
    }

    private func backToTheKeptTree(_ card: String, _ tree: XCUIElement, _ root: String) async throws {
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 10))
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(tree.textFields["Filter"].has(\.stringValue, "main", within: 3))
        XCTAssertFalse(row("a.txt", in: tree).exists)
        tree.buttons["Close Filter"].click()
        XCTAssertTrue(row("out.o", in: tree).exists(within: 5))
        XCTAssertFalse(tree.textFields["Filter"].exists)
    }

    private func openAndCollapse(_ card: String, _ tree: XCUIElement) {
        row("src", in: tree).click()
        XCTAssertTrue(hasKeyboard(row("src", in: tree)))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("deep", in: tree).exists(within: 3))
        element("pane.\(card).collapse").click()
        XCTAssertTrue(row("deep", in: tree).vanishes(within: 3))
        row("build", in: tree).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("out.o", in: tree).exists(within: 3))
    }

    private func moveRoot(_ card: String, _ tree: XCUIElement, _ root: String) async throws {
        row("src", in: tree).rightClick()
        app.menuItems["Open as Root"].click()
        try await labelEnds(card, " \(root)/src/")
        XCTAssertTrue(row("a.txt", in: tree).vanishes(within: 10))
        XCTAssertTrue(row("deep", in: tree).exists(within: 5))
        row("..", in: tree).doubleClick()
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        element("pane.\(card).collapse").click()
        XCTAssertTrue(row("deep", in: tree).vanishes(within: 3))
        row("src", in: tree).doubleClick()
        try await labelEnds(card, " \(root)/src/")
        app.typeKey(.leftArrow, modifierFlags: .command)
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        XCTAssertFalse(row("deep", in: tree).exists)
        element("pane.\(card).go-forward").click()
        try await labelEnds(card, " \(root)/src/")

        let field = element("pane.\(card).root")
        XCTAssertTrue(field.has(\.stringValue, "\(root)/src", within: 5))
        field.click()
        app.typeText("\(root)/none\r")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.has(\.stringValue, "\(root)/src", within: 3))
        field.click()
        app.typeText("\(root)/src/..\r")
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        element("pane.\(card).go-back").click()
        try await labelEnds(card, " \(root)/src/")
    }

    func testFileExplorerLeavesTheKeyboardToThePaneInUse() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (shellTab, shell) = try await newTab("files-keyboard")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-files-keyboard", root = "/private/tmp/ovvi-e2e-files-keyboard"
        try await makeTreeRepo(repo, in: shell)
        let (tab, card) = try await newCard("ovvi:explorer#e2efil \(root)/", cwd: repo, show: false)
        let beside = try await split(card)
        try await show(tab)
        let tree = element("files.\(card).page")
        row("a.txt", in: tree).click()
        XCTAssertTrue(hasKeyboard(row("a.txt", in: tree)))
        element("terminal.\(beside)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(beside)"))
        try await send("touch \(repo)/0.txt\r", to: shell)
        XCTAssertTrue(row("0.txt", in: tree).exists(within: 5))
        app.typeText("echo kept-$((6*7))\r")
        try await waitFor(beside) { $0.contains("kept-42") }
        try await show(shellTab)
        try await show(tab)
        XCTAssertTrue(row("0.txt", in: tree).exists(within: 5))
        app.typeText("echo back-$((6*7))\r")
        try await waitFor(beside) { $0.contains("back-42") }
        try await send("rm -rf \(repo)\r", to: shell)
    }

    func testFileExplorerOpensInNewTabsAndToTheSide() async throws {
        step("A folder of six files in an explorer card")
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files-open")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-files-open", root = "/private/tmp/ovvi-e2e-files-open"
        let names = ["two.txt", "three.txt", "four.txt", "five.txt", "six.txt"], all = names.joined(separator: " ")
        try await send("rm -rf \(repo) && mkdir -p \(repo) && cd \(repo) && touch one.txt \(all) "
            + "&& clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let (tab, card) = try await newCard("ovvi:explorer#e2efio \(root)/", cwd: repo)
        let tree = element("files.\(card).page")
        XCTAssertTrue(row("four.txt", in: tree).exists(within: 10))

        step("⌥-click opens a file to the side")
        XCUIElement.perform(withKeyModifiers: .option) { row("one.txt", in: tree).click() }
        let side = try await sidePane(in: tab, besides: [card])
        try await labelEnds(side, " \(root)/one.txt")
        XCTAssertTrue(element("file.\(side).page").exists(within: 10))
        XCTAssertTrue(hasKeyboard(row("one.txt", in: tree)))

        // Five in a row: an open's tab is made last, then moved beside its card, and each must still show its own
        // page; a page that follows the tab's old place shows only from the fifth on.
        for name in names {
            step("⌘-click opens \(name) in a new tab beside, with its own page")
            XCTAssertTrue(row(name, in: tree).exists(within: 10), name)
            let before = try await tabIDs()
            XCUIElement.perform(withKeyModifiers: .command) { row(name, in: tree).click() }
            let opened = try await newTabID(after: before)
            closeAfter("tab", opened)
            XCTAssertTrue(element("tab.\(opened)").exists(within: 5), name)
            let pane = try await pane(of: opened)
            try await labelEnds(pane, " \(root)/\(name)")
            try await expectBeside(opened, tab)
            XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected }, name)
            XCTAssertTrue(hasKeyboard(row(name, in: tree)), name)
            try await show(opened)
            XCTAssertTrue(element("page.\(opened)").has(\.isHittable, true, within: 5), name)
            try await show(tab)
        }
        try await send("rm -rf \(repo)\r", to: shell)
    }

    func row(_ name: String, in page: XCUIElement) -> XCUIElement {
        page.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    func labelEnds(_ pane: String, _ end: String) async throws {
        _ = try await poll("the label ending in \(end)") { () async throws -> String? in
            let label = try await paneLabel(pane)
            return label.hasPrefix("ovvi:explorer#") && label.hasSuffix(end) ? label : nil
        }
    }

    func makeTreeRepo(_ repo: String, in shell: String) async throws {
        let commit = "git -c user.name=e2e -c user.email=e2e@ovvi commit -q"
        try await send("""
        rm -rf \(repo) && mkdir -p \(repo)/src/deep \(repo)/build && cd \(repo) && git init -q && \
        echo build/ >.gitignore && echo one >a.txt && echo 'print(1)' >src/deep/main.swift && git add -A && \
        \(commit) -m first && echo two >>a.txt && \(commit) -am second-commit && echo three >>a.txt && \
        touch build/out.o && clear && echo ready-$((6*7))\r
        """, to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
    }
}
