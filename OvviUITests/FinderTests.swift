import XCTest

extension OvviUITests {
    func testFileExplorerFindBarAndFinderKeys() async throws {
        step("A repository in an explorer card")
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files-finder")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-files-finder", root = "/private/tmp/ovvi-e2e-files-finder"
        try await makeTreeRepo(repo, in: shell)
        let card = try await newCard("ovvi:explorer#e2efil \(root)/", cwd: repo).pane
        let tree = element("files.\(card).page"), field = tree.textFields["Filter"]
        // The first card of a run waits for the default plugins to install and build.
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 30))
        XCTAssertFalse(row(".gitignore", in: tree).exists)
        XCTAssertFalse(field.exists)
        // The fresh card's keys first: they start on "..".
        try await keysHiddenFilesAndFind(card, tree, repo, root, shell)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 3))
        // Gone, or selection()'s click under the rows lands on its row.
        try await send("rm -r \(repo)/empty\r", to: shell)
        XCTAssertTrue(row("empty", in: tree).vanishes(within: 5))

        step("Find bar: the filter button and typing filter the rows")
        let filter = element("pane.\(card).filter")
        filter.click()
        XCTAssertTrue(field.exists(within: 3))
        app.typeText("a.t")
        XCTAssertTrue(row("out.o", in: tree).vanishes(within: 5))
        XCTAssertTrue(row("a.txt", in: tree).exists)
        filter.click()
        XCTAssertTrue(field.vanishes(within: 3))
        XCTAssertTrue(row("build", in: tree).exists(within: 5))

        row("src", in: tree).click()
        app.typeText("mai")
        XCTAssertTrue(field.has(\.stringValue, "mai", within: 3))
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 3))
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 5))
        keepScreenshot("file explorer find bar closed")

        step("Explorer: the selection's ⌘O, Back and Forward")
        try await selection(card, tree, root)
        step("Explorer: renames")
        try await renames(card, tree, shell)

        step("Explorer: ⌘↓ and ⌘↑ move the root")
        row("src", in: tree).click()
        app.typeKey(.downArrow, modifierFlags: .command)
        try await labelEnds(card, " \(root)/src/")
        XCTAssertTrue(row("deep", in: tree).exists(within: 10))
        app.typeKey(.upArrow, modifierFlags: .command)
        try await labelEnds(card, " \(root)/")
        try await send("rm -rf \(repo)\r", to: shell)
    }

    private func keysHiddenFilesAndFind(_ card: String, _ tree: XCUIElement, _ repo: String, _ root: String,
                                        _ shell: String) async throws
    {
        step("Explorer: arrow keys wrap, open and close folders, ⌘O opens")
        XCTAssertTrue(hasKeyboard(row("..", in: tree)))
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(row("a.txt", in: tree)))
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(row("..", in: tree)))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(row("build", in: tree)))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("deep", in: tree).exists(within: 5))
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(row("deep", in: tree).vanishes(within: 5))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey("o", modifierFlags: .command)
        try await labelEnds(card, " \(root)/a.txt")
        element("pane.\(card).go-back").click()
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))

        step("Explorer: hidden files, an empty folder, ⌘F")
        let eye = element("pane.\(card).hidden-files")
        eye.click()
        XCTAssertTrue(row(".gitignore", in: tree).exists(within: 5))
        eye.click()
        XCTAssertTrue(row(".gitignore", in: tree).vanishes(within: 5))

        try await send("mkdir \(repo)/empty\r", to: shell)
        XCTAssertTrue(row("empty", in: tree).exists(within: 5))
        row("empty", in: tree).doubleClick()
        try await labelEnds(card, " \(root)/empty/")
        let empty = tree.staticTexts.matching(NSPredicate(format: "value == 'This folder is empty'")).firstMatch
        XCTAssertTrue(empty.exists(within: 10))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))

        app.typeKey("f", modifierFlags: .command)
        app.typeText("main")
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 5))
        XCTAssertFalse(row("..", in: tree).exists)
    }

    private func renames(_ card: String, _ tree: XCUIElement, _ shell: String) async throws {
        row("a.txt", in: tree).click()
        app.typeKey(.return, modifierFlags: [])
        let rename = tree.textFields.matching(NSPredicate(format: "value == 'a.txt'")).firstMatch
        XCTAssertTrue(rename.exists(within: 3))
        app.typeText("b\r")
        XCTAssertTrue(row("b.txt", in: tree).exists(within: 5))
        row("b.txt", in: tree).click()
        app.typeKey(.return, modifierFlags: [])
        app.typeText("x/y\r")
        XCTAssertTrue(element("pane.\(card).toast").exists(within: 3))
        element("pane.\(card).toast.main").click()
        XCTAssertTrue(row("b.txt", in: tree).exists)
        row("build", in: tree).rightClick()
        app.menuItems["Rename"].click()
        XCTAssertTrue(tree.textFields.matching(NSPredicate(format: "value == 'build'")).firstMatch.exists(within: 3))
        app.typeText("built\r")
        XCTAssertTrue(row("built", in: tree).exists(within: 5))
        // The row moves ahead of the folder.
        try await send("clear; test -d built || sleep 1; test -f b.txt && test ! -e a.txt && test -d built && " +
            "echo renamed-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("renamed-42") }
    }

    private func selection(_ card: String, _ tree: XCUIElement, _ root: String) async throws {
        row("src", in: tree).click()
        tree.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).click()
        app.typeKey("o", modifierFlags: .command)
        row("src", in: tree).click()
        element("pane.\(card).collapse").click()
        app.typeKey("o", modifierFlags: .command)
        row("..", in: tree).click()
        app.typeKey("o", modifierFlags: .command)
        try await labelEnds(card, " /private/tmp/")
        XCTAssertEqual(element("pane.\(card).go-back").label, "Back ⌃-")
        app.typeKey("-", modifierFlags: .control)
        try await labelEnds(card, " \(root)/")
        app.typeKey("-", modifierFlags: [.control, .shift])
        try await labelEnds(card, " /private/tmp/")
        app.typeKey("-", modifierFlags: .control)
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
    }

    /// In its first 24 pt: a folder row's frame reaches into the next row. A row is one button to accessibility, its
    /// dot no element of its own, so this reads the picture. Nil where screenshots draw no web content (CI's machines).
    private func dot(_ row: XCUIElement) -> Bool? {
        guard let full = row.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              row.frame.width > 0
        else { return nil }
        let scale = Double(full.width) / row.frame.width
        guard let crop = full.cropping(to: CGRect(x: 0, y: 0, width: Double(full.width), height: 24 * scale))
        else { return nil }
        let pixels = Self.pixels(NSImage(cgImage: crop, size: .zero)), width = crop.width
        guard pixels.count >= 4, stride(from: 0, to: pixels.count, by: 4).contains(where: { index in
            (0 ..< 3).map { abs(Int(pixels[index + $0]) - Int(pixels[$0])) }.reduce(0, +) > 90
        })
        else { return nil }
        let end = max(width - Int(30 * scale), 0)
        return stride(from: 0, to: pixels.count, by: 4).contains { index in
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            return (index / 4) % width >= end && red > 170 && blue < 110 && red - green > 40
        }
    }

    func testFileExplorerChangeDotsAndGitBar() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files-dots")
        try await waitForPrompt(shell)
        let repo = "/tmp/ovvi-e2e-files-dots", root = "/private/tmp/ovvi-e2e-files-dots"
        try await makeTreeRepo(repo, in: shell)
        try await send("""
        mkdir -p web/node_modules/x && echo node_modules/ >>.gitignore && touch web/index.ts && git add -A && \
        git -c user.name=e2e -c user.email=e2e@ovvi commit -qm third && clear && echo dots-$((6*7))\r
        """, to: shell)
        try await waitFor(shell) { $0.contains("dots-42") }
        let (tab, card) = try await newCard("ovvi:explorer#e2efil \(root)/", cwd: repo)
        let tree = element("files.\(card).page")
        // The first card of a run waits for the default plugins to install and build.
        XCTAssertTrue(row("web", in: tree).exists(within: 30))

        row("web", in: tree).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("node_modules", in: tree).exists(within: 5))
        XCTAssertTrue(tree.buttons["Open in Git"].exists(within: 5))
        XCTAssertTrue(text("3 folders, 1 file · 1 hidden", in: tree).exists)
        // CI's screenshots draw no web content: there the dots go unchecked (make e2e on a Mac checks them).
        let draws = dot(row("web", in: tree)) != nil
        XCTAssertFalse(draws && until(1) { dot(row("web", in: tree)) == true }, "a clean folder shows a change dot")

        try await send("touch src/deep/new.swift web/node_modules/x/y.js && echo four >>a.txt\r", to: shell)
        XCTAssertTrue(!draws || until(10) { dot(row("src", in: tree)) == true })
        XCTAssertFalse(draws && dot(row("web", in: tree)) == true)
        try await statusBar(tree, shell, repo)

        let before = try await tabIDs()
        tree.buttons["Open in Git"].click()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        let pane = try await pane(of: opened)
        let label = try await paneLabel(pane)
        XCTAssertTrue(label.hasPrefix("ovvi:git#") && label.hasSuffix(" \(root)/"), label)

        try await send("mkdir -p /tmp/ovvi-e2e-files-plain && touch /tmp/ovvi-e2e-files-plain/x\r", to: shell)
        try await show(tab)
        element("pane.\(card).root").click()
        app.typeText("/private/tmp/ovvi-e2e-files-plain\r")
        XCTAssertTrue(row("x", in: tree).exists(within: 10))
        XCTAssertFalse(until(2) { tree.buttons["Open in Git"].exists })
        try await send("rm -rf \(repo) \(repo)-remote \(repo)-other /tmp/ovvi-e2e-files-plain\r", to: shell)
    }

    private func statusBar(_ tree: XCUIElement, _ shell: String, _ repo: String) async throws {
        XCTAssertTrue(text("+1", in: tree).exists(within: 5))
        keepScreenshot("file explorer status bar")
        try await send("""
        git init -q --bare \(repo)-remote && git remote add origin \(repo)-remote && git push -qu origin HEAD && \
        git -c user.name=e2e -c user.email=e2e@ovvi commit -qam four && touch web/b.ts\r
        """, to: shell)
        let push = tree.buttons["Push, 1 ahead"]
        XCTAssertTrue(push.exists(within: 10))
        XCTAssertFalse(text("+1", in: tree).exists)
        push.click()
        XCTAssertTrue(push.vanishes(within: 10))
        try await send("""
        git clone -q \(repo)-remote \(repo)-other && cd \(repo)-other && touch c && git add c && \
        git -c user.name=e2e -c user.email=e2e@ovvi commit -qm c && git push -q && cd \(repo) && echo pushed-$((6*7))\r
        """, to: shell)
        try await waitFor(shell) { $0.contains("pushed-42") }
        let pull = tree.buttons["Pull, 1 behind"]
        XCTAssertFalse(until(1) { pull.exists })
        tree.buttons["Fetch"].click()
        XCTAssertTrue(pull.exists(within: 10))
        pull.click()
        XCTAssertTrue(pull.vanishes(within: 10))
    }
}
