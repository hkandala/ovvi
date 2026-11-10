import XCTest

extension OvviUITests {
    func testAPinchMagnifiesABrowserPage() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("pinch")
        try await waitForPrompt(shell)
        let page = try await writePages(from: shell)
        let browser = try await split(shell)
        try await Self.call(one, "pane.rename", ["pane_id": browser, "label": "ovvi:browser#e2epin \(page)"])
        try await show(tab)
        let text = pageText("ovvi-page-one")
        XCTAssertTrue(text.exists(within: 15))
        let before = text.frame
        _ = try await Self.post("\(one)/pinch", Data("\(before.minX) \(before.midY) 0.05 20".utf8))
        XCTAssertTrue(until(5) { text.frame.height > before.height * 1.5 }, "\(before) then \(text.frame)")
        text.click()
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(until(5) { abs(text.frame.height - before.height) < 1 }, "\(before) then \(text.frame)")
    }
}
