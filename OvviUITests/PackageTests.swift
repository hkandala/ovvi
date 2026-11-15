import XCTest

extension OvviUITests {
    func testAPluginPackageAsksForTrustBuildsAndReloads() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("packages")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-packages", csv = "/tmp/ovvi-e2e-csv", data = "/tmp/ovvi-e2e-csv-data"
        let fixture = "\(Self.fixtures)/csv-table"
        let log = "\(config)/logs/plugins/ovvi-e2e-csv-table.log"
        try await send("rm -rf \(config) \(csv) \(data) ~/.local/state/ovvi/\(one)/ovvi-e2e-csv-table && "
            + "mkdir -p \(config) \(data) && cp -R \(fixture) \(csv) && (cd \(csv) && npm_config_offline=true npm ci "
            + "--no-audit --no-fund --silent) && printf 'name,count\\nb,2\\na,10\\nc,1\\n' > "
            + "\(data)/a.csv && echo '{\"packages\":[\"\(csv)\"]}' > \(config)/settings.json && clear && "
            + "echo made-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
        sendAfter("rm -rf \(config) \(csv) \(data) /tmp/ovvi-e2e-csv-repo "
            + "~/.local/state/ovvi/\(one)/ovvi-e2e-csv-table\r", to: shell)
        relaunch(one, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()

        let (cardTab, card) = try await newCard("ovvi:ovvi-e2e-csv-table#e2ecsv \(data)/a.csv", cwd: data)

        try await trustsAndBuilds(card, csv: csv, shell: shell, tab: tab, cardTab: cardTab)
        let rows = element("pane.\(card).rows")
        XCTAssertTrue(rows.has(\.stringValue, "3 rows", within: 5))
        element("pane.\(card).first-row").click()
        XCTAssertTrue(rows.has(\.stringValue, "4 rows", within: 5))

        try await reloads(card, in: cardTab, csv: csv, shell: shell, tab: tab)
        element("tab.\(tab)").click()
        try await send("clear; grep -c 'CSV Table did not build' \(log); echo logged-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("1\nlogged-42") }

        try await installFromGit(fixture, config: config, shell: shell)
    }

    private func trustsAndBuilds(_ card: String, csv: String, shell: String, tab: String,
                                 cardTab: String) async throws
    {
        let trust = element("pane.\(card).trust")
        XCTAssertTrue(trust.has(\.stringValue, "Install “CSV Table”?", within: 10))
        XCTAssertFalse(text("CSV Table one").exists)
        keepScreenshot("plugin confirmation")
        let filter = openPalette()
        filter.typeText("reload plugins")
        XCTAssertTrue(element("palette.command.Reload Plugins").exists(within: 2))
        filter.typeText("\r")
        element("tab.\(tab)").click()
        try await send("clear; ls \(csv)/dist || echo unbuilt-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("unbuilt-42") }
        try await show(cardTab)
        element("pane.\(card).trust.install").click()
        XCTAssertTrue(element("pane.\(card).failure").has(\.stringValue, "CSV Table is not built", within: 10))
        XCTAssertEqual(element("pane.\(card).failure.text").stringValue,
                       "dist/main.js is missing. Build runs its build script.")
        keepScreenshot("plugin not built")
        element("pane.\(card).build").click()
        XCTAssertTrue(text("CSV Table one").exists(within: 20))
    }

    private func reloads(_ card: String, in cardTab: String, csv: String, shell: String, tab: String) async throws {
        let rows = element("pane.\(card).rows")
        element("tab.\(tab)").click()
        try await send("mkdir -p \(csv)/node_modules/ovvi-e2e-word && echo '{\"name\":\"ovvi-e2e-word\","
            + "\"version\":\"1.0.0\",\"main\":\"index.js\"}' > \(csv)/node_modules/ovvi-e2e-word/package.json && "
            + "echo 'export const word = \"two\"' > \(csv)/node_modules/ovvi-e2e-word/index.js && "
            + "sed -i '' 's/^const caption = .*/import { word } from \"ovvi-e2e-word\"; const caption = "
            + "`CSV Table ${word}`/' \(csv)/src/main.ts && clear && echo edited-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("edited-42") }
        try await show(cardTab)
        element("ovvi-e2e-csv-table.\(card).card").click()
        app.typeKey("r", modifierFlags: [.command, .option])
        XCTAssertTrue(text("CSV Table two").exists(within: 10))
        XCTAssertTrue(rows.has(\.stringValue, "4 rows", within: 5))

        element("tab.\(tab)").click()
        try await send(
            "echo 'export default {' >> \(csv)/src/main.ts && sed -i '' 's/0.1.0/0.1.1/' \(csv)/package.json "
                + "&& clear && echo broken-$((6*7))\r",
            to: shell,
        )
        try await waitFor(shell) { $0.contains("broken-42") }
        try await show(cardTab)
        element("ovvi-e2e-csv-table.\(card).card").click()
        app.typeKey("r", modifierFlags: [.command, .option])
        let toast = element("pane.\(card).toast")
        XCTAssertTrue(toast.exists(within: 10))
        XCTAssertTrue(toast.stringValue.hasPrefix("CSV Table did not build"), toast.stringValue)
        XCTAssertTrue(text("CSV Table two").exists(within: 10))
    }

    private func installFromGit(_ fixture: String, config: String, shell: String) async throws {
        let repo = "/tmp/ovvi-e2e-csv-repo", git = "git -C \(repo) -c user.name=e2e -c user.email=e2e@e2e"
        try await send(
            "rm -rf \(repo) && cp -R \(fixture) \(repo) && sed -i '' "
                + "'s/\"ovvi-e2e-csv-table\"/\"ovvi-e2e-csv-git\"/; "
                + "s/\"CSV Table\"/\"CSV Git\", \"chooser\": \"CSV Git\"/; s/\"opens\": {/&\"folders\": true, /' "
                + "\(repo)/package.json && git init -q \(repo) && \(git) add . && "
                + "\(git) commit -qm one && \(git) tag v1 && sed -i '' 's/0.1.0/0.2.0/' \(repo)/package.json && "
                + "\(git) commit -qam two && clear && echo repo-$((6*7))\r",
            to: shell,
        )
        try await waitFor(shell) { $0.contains("repo-42") }
        app.menuBars.menuBarItems["Ovvi"].click()
        app.menuBars.menuItems["Plugins…"].click()
        let source = element("plugins.source")
        XCTAssertTrue(source.exists(within: 5))
        source.click()
        source.typeText("git:\(repo)@v1\r")
        let allow = app.sheets.buttons["Install"]
        XCTAssertTrue(allow.exists(within: 10))
        let newPane = app.sheets.checkBoxes["Show in New Pane"]
        XCTAssertEqual(newPane.value as? Int, 0, "Show in New Pane is on for a new plugin")
        allow.click()
        let installed = element("plugins.ovvi-e2e-csv-git")
        XCTAssertTrue(installed.has(\.label, "CSV Git, 0.1.0, git:\(repo)@v1", within: 30), installed.label)
        XCTAssertTrue(element("plugins.ovvi-e2e-csv-table").label.hasSuffix(", /tmp/ovvi-e2e-csv"))
        installed.click()
        // No Update from git: a clone has no newer version to ask for.
        XCTAssertTrue(element("plugins.ovvi-e2e-csv-git.remove").exists(within: 3))
        XCTAssertFalse(element("plugins.ovvi-e2e-csv-git.update").exists)
        // Back to the list: a click on the selected row changes nothing.
        element("settings.page.general").click()
        element("settings.page.plugins").click()
        element("plugins.new").click()
        let name = app.sheets.textFields.firstMatch
        XCTAssertTrue(name.exists(within: 5))
        name.typeText("Ovvi E2E Lines")
        app.sheets.buttons["Create"].click()
        let lines = element("plugins.ovvi-e2e-lines")
        XCTAssertTrue(lines.has(\.label, "Ovvi E2E Lines, 0.1.0, \(config)/plugins/ovvi-e2e-lines", within: 30),
                      lines.label)
        keepScreenshot("plugins page")
        // Reload All builds the plugins with no card too.
        let builds = ["ovvi-e2e-csv-repo", "ovvi-e2e-lines"].map { "\(config)/plugins/\($0)/dist/main.js" }
        try await send("rm \(builds.joined(separator: " ")) && clear && echo removed-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("removed-42") }
        element("plugins.reload-all").click()
        settingsWindow.buttons["_XCUI:CloseWindow"].click()
        XCTAssertTrue(source.vanishes(within: 2))
        try await send("clear; until test -f \(builds[0]) && test -f \(builds[1]); do sleep 0.2; done; "
            + "echo built-$((6*7))\r", to: shell)
        try await waitFor(shell, times: 300) { $0.contains("built-42") }
    }

    func testAnNPMPluginOffersTheUpdateThatNPMHas() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("npm")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-npm", made = "/tmp/ovvi-e2e-npm-made", tarball = "/tmp/ovvi-e2e-npm-csv.tgz"
        // A package with its build in it, as a published plugin ships it: nothing builds or installs.
        let pack = { (version: String, api: Int) in
            "printf '%s' '{\"name\":\"ovvi-e2e-npm-csv\",\"version\":\"\(version)\",\"dependencies\":{\"pad\":"
                + "\"file:nowhere\"},\"ovvi\":{\"id\":\"ovvi-e2e-npm-csv\",\"name\":\"CSV npm\",\"api\":\(api),"
                + "\"entry\":\"dist/main.js\",\"icon\":\"tablecells\"}}' > \(made)/package.json && (cd \(made) && "
                + "npm pack --silent >/dev/null) && mv \(made)/ovvi-e2e-npm-csv-\(version).tgz \(tarball) && clear && "
                + "echo packed-\(version)\r"
        }
        try await send("rm -rf \(config) \(made) \(tarball) && mkdir -p \(config) \(made)/dist && "
            + "echo 'export default () => {}' > \(made)/dist/main.js && " + pack("0.1.0", 3), to: shell)
        try await waitFor(shell) { $0.contains("packed-0.1.0") }
        sendAfter("rm -rf \(config) \(made) \(tarball)\r", to: shell)
        relaunch(one, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let row = installs("npm:\(tarball)", as: "plugins.ovvi-e2e-npm-csv", "CSV npm, 0.1.0, npm:\(tarball)")
        let page = { [self] () -> (update: XCUIElement, current: XCUIElement) in
            element("settings.page.general").click()
            element("settings.page.plugins").click()
            row.click()
            return (element("plugins.ovvi-e2e-npm-csv.update"), element("plugins.ovvi-e2e-npm-csv.up-to-date"))
        }
        var shown = page()
        XCTAssertTrue(shown.current.exists(within: 30))
        XCTAssertFalse(shown.update.exists)
        keepScreenshot("npm plugin up to date dark", of: settingsWindow)
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        pick("Appearance", "Light")
        keepScreenshot("npm plugin up to date light", of: settingsWindow)

        try await send(pack("0.2.0", 3), to: shell)
        try await waitFor(shell) { $0.contains("packed-0.2.0") }
        shown = page()
        XCTAssertTrue(shown.update.has(\.label, "Update to 0.2.0", within: 30), shown.update.label)
        keepScreenshot("npm plugin update light", of: settingsWindow)
        pick("Appearance", "Dark")
        keepScreenshot("npm plugin update dark", of: settingsWindow)
        shown.update.click()
        XCTAssertTrue(shown.current.exists(within: 30))
        try await send("clear; grep -q '\"0.2.0\"' \(config)/plugins/ovvi-e2e-npm-csv/package.json && "
            + "test ! -e \(config)/plugins/ovvi-e2e-npm-csv/node_modules && echo kept-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("kept-42") }

        try await refusesANewerAPI(pack("0.3.0", 99), config: config, shell: shell, page: page)
        settingsWindow.buttons["_XCUI:CloseWindow"].click()
    }

    private func installs(_ typed: String, as id: String, _ label: String) -> XCUIElement {
        openSettings("plugins")
        let source = element("plugins.source", in: settingsWindow)
        XCTAssertTrue(source.exists(within: 5))
        source.click()
        source.typeText("\(typed)\r")
        XCTAssertTrue(app.sheets.buttons["Install"].exists(within: 10))
        app.sheets.buttons["Install"].click()
        let row = element(id, in: settingsWindow)
        XCTAssertTrue(row.has(\.label, label, within: 30), row.label)
        return row
    }

    private func refusesANewerAPI(_ pack: String, config: String, shell: String,
                                  page: () -> (update: XCUIElement, current: XCUIElement)) async throws
    {
        step("A version this Ovvi cannot run is refused")
        try await send(pack, to: shell)
        try await waitFor(shell) { $0.contains("packed-0.3.0") }
        let shown = page()
        XCTAssertTrue(shown.update.has(\.label, "Update to 0.3.0", within: 30), shown.update.label)
        shown.update.click()
        let refused = settingsWindow.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@",
                                                                      "CSV npm 0.3.0 needs a newer Ovvi")).firstMatch
        XCTAssertTrue(refused.exists(within: 30))
        try await send("clear; grep -q '\"0.2.0\"' \(config)/plugins/ovvi-e2e-npm-csv/package.json && "
            + "echo still-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("still-42") }
    }
}
