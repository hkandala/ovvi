import XCTest

extension OvviUITests {
    /// Settings ▸ General ▸ Balance splits automatically, on by default: a card opened beside one, a close in the app,
    /// another client's split and a shell's exit each even the row. Off: herdr's halves, and a close leaves herdr's
    /// layout.
    func testBalanceSplitsEvensOpensAndClosesUnlessOff() async throws {
        relaunch(one, Self.agentHold)
        let (tab, panes) = try await balanceTab("balance")
        let (first, second) = (panes[0], panes[1])

        step("A card opened beside a pane evens the row")
        let card = try await openBeside(second, "/tmp", in: tab)
        try await expectWidths(tab, [first: 1 / 3, second: 1 / 3, card: 1 / 3])

        step("A close in the app evens the row")
        hoverHeader(second)
        element("pane.\(second).close").click()
        try await expectWidths(tab, [first: 0.5, card: 0.5])

        step("Another client's split and a pane whose shell exits even the row")
        let third = try await split(first)
        try await expectWidths(tab, [first: 1 / 3, third: 1 / 3, card: 1 / 3])
        try await send("exit\r", to: third)
        try await expectWidths(tab, [first: 0.5, card: 0.5])

        step("Off: a card beside a pane halves it, and a close leaves herdr's layout")
        relaunch(one, Self.agentHold + ["-balanceSplits", "NO"])
        let (offTab, halves) = try await balanceTab("halves")
        let (left, right) = (halves[0], halves[1])
        let half = try await openBeside(right, "/usr", in: offTab)
        try await expectWidths(offTab, [left: 0.5, right: 0.25, half: 0.25])
        pick("Pane", "Balance Splits")
        try await expectWidths(offTab, [left: 1 / 3, right: 1 / 3, half: 1 / 3])
        hoverHeader(right)
        element("pane.\(right).close").click()
        try await expect("\(right) closed") { try await order(offTab) == [left, half] }
        try await expectWidths(offTab, [left: 1 / 3, half: 2 / 3])
        element("pane.\(left)").click()
        app.typeKey("d", modifierFlags: .command)
        try await expect("the split of \(left)") { try await order(offTab).count == 3 }
        let split = try await order(offTab).first { ![left, half].contains($0) } ?? ""
        try await expectWidths(offTab, [left: 1 / 6, split: 1 / 6, half: 2 / 3])
    }

    /// A shown tab of two panes, split by herdr: halves, already even.
    private func balanceTab(_ label: String) async throws -> (tab: String, panes: [String]) {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, first) = try await newTab(label)
        let second = try await split(first)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
        try await waitForPrompt(second)
        try await expectOpen("w2")
        return (tab, [first, second])
    }

    /// A folder of its own each time: `ovvi open` reuses a card that shows it.
    private func openBeside(_ pane: String, _ folder: String, in tab: String) async throws -> String {
        let before = try await order(tab)
        try await run("clear; \(Self.ovviCommand) open explorer \(folder)", in: pane, "opened", 0, "kind: explorer")
        try await expect("a third pane in \(tab)") { try await order(tab).count == 3 }
        return try await order(tab).first { !before.contains($0) } ?? ""
    }
}
