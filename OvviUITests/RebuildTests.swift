import XCTest

extension OvviUITests {
    /// Settings ▸ General ▸ Rebuild, in a repo whose make install fails: the log's window quits the app, runs make
    /// install once the app is gone, and stays on its log, with no new app. The reopen after a good make install opens
    /// the app without the tests' arguments: the user checks it by hand. A pane's shell makes the repo and stops the
    /// log's window: the runner is sandboxed. It runs the script once first: a runner's first Swift script compiles
    /// AppKit's modules (26 s in the VM), which is no part of what the test checks.
    func testRebuildQuitsTheAppAndStaysOnAFailedLog() async throws {
        executionTimeAllowance = 300
        let repo = "/tmp/ovvi-e2e-rebuild-\(UUID().uuidString.prefix(8))", script = "\(repo)/scripts/rebuild.swift"
        let (tab, pane) = try await createTab(in: "w1", label: "rebuild")
        closeAfter("tab", tab)
        sendAfter("kill $(pgrep -f '\(script)'); rm -rf \(repo)\r", to: pane)
        try await waitForPrompt(pane)
        try await send("mkdir -p \(repo)/scripts && cp \(Self.scripts.path)/rebuild.swift \(repo)/scripts/ && "
            + "printf 'install:\\n\\t@echo making the stand-in\\n\\t@touch ran\\n\\t@exit 3\\n' >\(repo)/Makefile && "
            + "s=$SECONDS; swift \(script) 2>/dev/null; echo compiled in $((SECONDS-s)) s, made-$((6*7))\r", to: pane)
        try await waitFor(pane, toShow: "made-42", times: 1200)
        relaunch(one, ["-OvviRepo", repo])
        openSettings("general")
        element("settings.general.rebuild", in: settingsWindow).click()
        let quit = app.wait(for: .notRunning, timeout: 60)
        keep(XCTAttachment(screenshot: XCUIScreen.main.screenshot()), as: "after Rebuild")
        XCTAssertTrue(quit, "the app did not quit")

        try await send("until [ -e \(repo)/ran ]; do sleep 0.1; done; echo ran-$((6*7))\r", to: pane)
        try await waitFor(pane, toShow: "ran-42", times: 600)
        XCTAssertFalse(app.wait(for: .runningForeground, timeout: 3), "a failed make install opened the app")
        try await send("pgrep -f '\(script)' >/dev/null && echo kept-$((6*7))\r", to: pane)
        try await waitFor(pane, toShow: "kept-42")
        try await keep(read(pane), as: "the pane")
        keep(XCTAttachment(screenshot: XCUIScreen.main.screenshot()), as: "a failed rebuild")
    }
}
