import XCTest

extension OvviUITests {
    /// A page's video goes full screen in the browser and in a floating preview card, and comes back to its card.
    func testVideosPlayFullScreenInTheBrowserAndThePreview() async throws {
        let (tab, shell) = try await newTab("full screen")
        try await waitForPrompt(shell)
        let folder = "/tmp/ovvi-e2e-fullscreen"
        try await send("""
        rm -rf \(folder) && mkdir \(folder) && cp '\(Self.fixtures)/video/clip.mp4' \(folder) && printf '<video id=v \
        controls width=320 src=clip.mp4></video><button onclick="v.requestFullscreen()">Full</button><p \
        id=s>ovvi-windowed-0</p><script>let n = 0; document.onfullscreenchange = () => s.textContent = \
        (document.fullscreenElement ? "ovvi-full-" : "ovvi-windowed-") + ++n</script>' >\(folder)/page.html && clear\r
        """, to: shell)
        sendAfter("rm -rf \(folder)\r", to: shell)
        try await waitFor(shell) { !$0.contains("printf") }
        let browser = try await split(shell)
        try await relabel(browser, "ovvi:browser#e2efsb file://\(folder)/page.html")
        try await show(tab)
        XCTAssertTrue(pageText("ovvi-windowed-0").exists(within: 10))

        step("Browser: the page's requestFullscreen fills the screen, Esc brings it back")
        app.webViews.buttons["Full"].click()
        // Only the full-screen player has it; the page's text is out of reach behind the full-screen video.
        let exit = app.webViews.buttons["Exit Full Screen"]
        XCTAssertTrue(exit.exists(within: 5))
        keepScreen("browser video full screen")
        app.typeKey(.escape, modifierFlags: [])
        let back = pageText("ovvi-windowed-2"), card = element("browser.\(browser).card")
        XCTAssertTrue(back.exists(within: 5) && until(3) { card.frame.contains(back.frame) }, "\(card.frame)")

        step("Floating preview: the player's own button, Esc brings it back")
        let preview = try await split(browser)
        try await relabel(preview, "ovvi:explorer#e2efsp /private\(folder)/clip.mp4")
        let window = float(preview), player = window.webViews.firstMatch
        // The first preview card installs the plugin.
        XCTAssertTrue(player.buttons["Play"].exists(within: 30))
        player.buttons["Play"].click()
        // The bar hides about when the 4 s clip ends, and stays once it ended.
        XCTAssertTrue(player.buttons["Pause"].exists(within: 3) && player.buttons["Play"].exists(within: 10))
        let enter = player.buttons["Enter Full Screen"]
        XCTAssertTrue(enter.exists(within: 3))
        keepScreen("preview video and its full-screen button")
        enter.click()
        XCTAssertTrue(exit.exists(within: 5))
        keepScreen("preview video full screen")
        // Esc: WebKit's own Exit Full Screen ignored clicks at times in the VM, in Safari too.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(exit.vanishes(within: 5))
        XCTAssertTrue(until(3) { window.frame.contains(player.frame) && player.frame.width > 100 }, "\(player.frame)")
        keepScreen("preview back in its floating window")
    }
}
