import XCTest

extension OvviUITests {
    func testAPluginCardAsksAndItsPageSetsItsSettings() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("plugin settings")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-plugin-settings", source = "\(config)/src/ovvi-e2e-shout"
        let card = try await shoutCard(config, shell: shell, extra: "mkdir -p \(config)/src && mv \(config)/plugins/"
            + "ovvi-e2e-shout \(source) && echo '{\"packages\":[\"\(source)\"]}' > \(config)/settings.json && "
            + "sed -i '' 's/\"icon\":\"megaphone\",/&\"chooser\":\"Shout\",/' \(source)/package.json")
        XCTAssertTrue(element("pane.\(card.pane).trust").has(\.stringValue, "Install “Shout”?", within: 10))
        let origin = element("pane.\(card.pane).trust.origin").stringValue
        XCTAssertTrue(origin.hasPrefix("ovvi-e2e-shout 1.0.0 in /") && origin.hasSuffix(source.dropFirst(4)), origin)
        XCTAssertEqual(element("pane.\(card.pane).trust.words").stringValue,
                       "Plugins run code as you on this Mac and on the machines whose cards you open, including "
                           + "their build script. Install plugins only from sources you trust.")
        try await cancelsASecondCard()
        try await show(card.tab)
        XCTAssertEqual(element("pane.\(card.pane).trust.new-pane").value as? Int, 0, "Show in New Pane on at install")
        // Install ahead of Settings, which covers the card on CI's small screen.
        element("pane.\(card.pane).trust.install").click()
        XCTAssertTrue(text("Shout false at load listed").exists(within: 10))

        app.typeKey(",", modifierFlags: .command)
        let page = element("settings.page.plugins")
        XCTAssertTrue(page.exists(within: 5))
        let settings = settingsWindow
        page.click()
        let row = element("plugins.ovvi-e2e-shout")
        XCTAssertTrue(row.exists(within: 5))
        XCTAssertEqual(element("plugins.browser").label, "Browser, Comes with Ovvi")
        keepScreenshot("plugins page dark", of: settings)
        row.click()
        let shout = element("plugins.ovvi-e2e-shout.setting.shout")
        XCTAssertTrue(shout.exists(within: 5))
        let remove = element("plugins.ovvi-e2e-shout.remove")
        XCTAssertTrue(remove.exists)

        shout.click()
        XCTAssertTrue(text("Shout true listed").exists(within: 3))
        try await send("clear; tr -d ' \\n' < \(config)/settings.json | grep -q "
            + "'\"plugins\":{\"ovvi-e2e-shout\":{\"shout\":true}}' && tr -d ' \\n' < \(config)/settings.json | grep -q "
            + "'\"hideInNewPane\":\\[\"ovvi-e2e-shout\"\\]' && grep -qx '\\[\"ovvi-e2e-shout\"\\]' "
            + "\(config)/trust.json && echo kept-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("kept-42") }

        remove.click()
        let sheet = settings.sheets.firstMatch
        XCTAssertTrue(sheet.buttons["Remove"].exists(within: 5))
        sheet.buttons["Remove"].click()
        XCTAssertTrue(element("pane.\(card.pane).missing").exists(within: 10))
        try await send("clear; grep -qx '\\[\\]' \(config)/trust.json && test -f \(source)/package.json && "
            + "echo removed-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("removed-42") }

        defaultPluginPage(page, in: settings)
        settingsWindow.buttons["_XCUI:CloseWindow"].click()
    }

    func testAPluginPageReachesOnlyTheLocalOriginsItDeclares() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("plugin connect")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-connect", folder = "\(config)/plugins/ovvi-e2e-connect"
        let manifest = #"{"version":"1.0.0","ovvi":{"id":"ovvi-e2e-connect","name":"Connect","api":3,"#
            + #""entry":"main.js","icon":"network","connect":["http://127.0.0.1:57931"]}}"#
        // Two servers, one declared; nc, as python3 took over 15 s to start on a cold VM. No CORS headers: a
        // no-cors fetch that gets through is opaque.
        let main = #"export default async function main() { const get = (port) => fetch("#
            + #""http://127.0.0.1:" + port, { mode: "no-cors" }).then((r) => r.type, () => "blocked"); "#
            + #"document.body.appendChild(document.createElement("p")).textContent = "#
            + #""declared " + await get(57931) + " other " + await get(57932) }"#
        try await send("rm -rf \(config) && mkdir -p \(folder) && echo '\(manifest)' > \(folder)/package.json && "
            + "echo '\(main)' > \(folder)/main.js && for p in 57931 57932; do "
            + "(while :; do printf 'HTTP/1.1 204 No Content\\r\\n\\r\\n' | nc -l 127.0.0.1 $p; done) >/dev/null 2>&1 & "
            + "done; "
            + "until curl -sf 127.0.0.1:57931 >/dev/null && curl -sf "
            + "127.0.0.1:57932 >/dev/null; do sleep 0.1; done; clear; echo made-$((6*7))\r", to: shell)
        try await waitFor(shell, times: 150) { $0.contains("made-42") }
        sendAfter("kill %1 %2; rm -rf \(config)\r", to: shell)
        relaunch(one, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        let card = try await newCard("ovvi:ovvi-e2e-connect#e2ecnt")
        XCTAssertTrue(element("pane.\(card.pane).trust.connect")
            .has(\.stringValue, "Its page connects to http://127.0.0.1:57931.", within: 10))
        element("pane.\(card.pane).trust.install").click()
        XCTAssertTrue(text("declared opaque other blocked").exists(within: 10))
    }

    private func cancelsASecondCard() async throws {
        let pane = try await newCard("ovvi:ovvi-e2e-shout#e2eshv /tmp").pane
        let cancel = element("pane.\(pane).trust.cancel")
        XCTAssertTrue(cancel.exists(within: 10))
        cancel.click()
        try await expect("the canceled card's pane to close") {
            do {
                _ = try await self.pane(pane)
                return false
            } catch is Failed {
                return true
            }
        }
    }

    private func defaultPluginPage(_ page: XCUIElement, in settings: XCUIElement) {
        // Back to the list: a click on the selected row changes nothing.
        element("settings.page.general").click()
        page.click()
        element("plugins.explorer").click()
        XCTAssertTrue(element("plugins.explorer.setting.markdown").exists(within: 5))
        XCTAssertTrue(element("plugins.explorer.setting.hidden-files").exists)
        keepScreenshot("plugin page dark", of: settings)
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        pick("Appearance", "Light")
        keepScreenshot("plugin page light", of: settings)
        // Back to the list: a click on the selected row changes nothing.
        element("settings.page.general").click()
        page.click()
        XCTAssertTrue(element("plugins.explorer").exists(within: 3))
        keepScreenshot("plugins page light", of: settings)
    }

    func shoutCard(_ config: String, shell: String, extra: String) async throws
        -> (tab: String, pane: String)
    {
        let folder = "\(config)/plugins/ovvi-e2e-shout"
        let manifest = #"{"version":"1.0.0","description":"Says it.","ovvi":{"id":"ovvi-e2e-shout","#
            + #""name":"Shout","api":3,"entry":"main.js","icon":"megaphone","#
            + #""settings":[{"id":"shout","type":"toggle","title":"Shout","default":false}]}}"#
        let main = #"export default function main(ovvi) { const p = document.body.appendChild("#
            + #"document.createElement("p")); const draw = async (more) => { const listed = await "#
            + #"ovvi.files.list("/tmp").then(() => " listed", (e) => " " + e.code); p.textContent = "Shout " + "#
            + #"ovvi.settings.get("shout") + more + listed }; "#
            + #"draw(" at load"); ovvi.on("settings", () => draw("")) }"#
        try await send("rm -rf \(config) && mkdir -p \(folder) && echo '\(manifest)' > \(folder)/package.json && "
            + "echo '\(main)' > \(folder)/main.js && \(extra) && clear && echo made-$((6*7))\r", to: shell)
        // A long line: a loaded Mac's shell takes seconds to echo it.
        try await waitFor(shell, times: 150) { $0.contains("made-42") }
        sendAfter("rm -rf \(config)\r", to: shell)
        relaunch(one, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        return try await newCard("ovvi:ovvi-e2e-shout#e2eshu /tmp")
    }
}
