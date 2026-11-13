import XCTest

extension OvviUITests {
    func testALongChatKeepsItsPlaceAndScrollsToTheBottom() async throws {
        let (tab, pane) = try await startChat()
        app.typeText("many\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        let bottom = element("chat.\(pane).bottom")
        XCTAssertFalse(bottom.exists)
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))
        let composer = element("chat.\(pane).composer"), gap = composer.frame.minY - last.frame.maxY

        let chat = element("chat.\(pane)")
        let point = "\(chat.frame.midX) \(chat.frame.midY)"
        var upward = 0
        for step in [10, -10] where upward == 0 {
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(step) 20 100 1".utf8))
            if bottom.exists(within: 2) {
                upward = step
            }
        }
        XCTAssertTrue(bottom.exists)
        for _ in 0 ..< 5 where last.exists && last.isHittable {
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(upward) 20 100 1".utf8))
        }
        XCTAssertFalse(last.exists && last.isHittable)
        let top = try XCTUnwrap(steady(3) {
            let seen = atTop(of: chat, pane)
            return seen.isEmpty ? nil : seen
        })

        let other = try await splitByButton(pane, in: tab)
        keepsTop(top, of: chat, pane, narrow: true)
        _ = try await Self.call(one, "pane.close", ["pane_id": other])
        keepsTop(top, of: chat, pane, narrow: false)

        bottom.click()
        XCTAssertTrue(until(3) { abs(composer.frame.minY - last.frame.maxY - gap) < 2 },
                      "\(gap) \(composer.frame.minY - last.frame.maxY)")
        XCTAssertTrue(bottom.vanishes(within: 2))
        let beside = try await splitByButton(pane, in: tab)
        XCTAssertTrue(until(3) { chat.frame.width < 600 && last.exists && last.isHittable }, "\(chat.frame)")
        _ = try await Self.call(one, "pane.close", ["pane_id": beside])
        XCTAssertTrue(until(3) { chat.frame.width > 600 && last.exists && last.isHittable }, "\(chat.frame)")
        XCTAssertFalse(bottom.exists)

        relaunch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(pane).view.tui").has(\.isSelected, true, within: 10))
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
    }

    func testALongChatShowsEarlierRowsInPlace() async throws {
        let pane = try await startChat().pane
        app.typeText("many 25\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        let chat = element("chat.\(pane)"), earlier = element("chat.\(pane).earlier")
        let first = row(pane, "user", "many 25")
        XCTAssertFalse(first.exists)
        func up() {
            for _ in 0 ..< 5 where !earlier.isHittable && !first.isHittable {
                chat.scroll(byDeltaX: 0, deltaY: 5000)
            }
        }
        var clicks = 0
        while !first.exists, clicks < 5 {
            up()
            clicks += 1
            guard clicks <= 2 else {
                earlier.click()
                continue
            }
            let found = try nodes(of: chat), tree = found[0]
            let button = try XCTUnwrap(found.first { $0.identifier == "chat.\(pane).earlier" }).frame
            let kinds = ["user", "reply", "stack", "worked"].map { "chat.\(pane).\($0)" }
            let under = try XCTUnwrap(found.filter { kinds.contains($0.identifier) && $0.frame.maxY > button.minY }
                .min { $0.frame.minY < $1.frame.minY })
            XCTAssertGreaterThanOrEqual(under.frame.minY - button.maxY, 10, "\(button) \(under.frame)")
            let top = try XCTUnwrap(found.filter {
                $0.identifier == "chat.\(pane).user" && $0.frame.minY >= tree.frame.minY - 1
            }.min { $0.frame.minY < $1.frame.minY })
            let (text, place) = (top.value as? String ?? "", top.frame.minY)
            earlier.click()
            let same = row(pane, "user", text)
            XCTAssertTrue(until(3) { abs(same.frame.minY - place) < 2 }, "\(text) \(place) \(same.frame)")
        }
        XCTAssertGreaterThanOrEqual(clicks, 2)
        up()
        XCTAssertTrue(first.isHittable)
        XCTAssertFalse(earlier.exists)
        staysAtTheBottom(pane, first) { element("chat.\(pane).bottom").click() }
        up()
        staysAtTheBottom(pane, first) {
            for _ in 0 ..< 5 where !last.isHittable {
                chat.scroll(byDeltaX: 0, deltaY: -5000)
            }
        }
    }

    func testTheChatsEndMovesWithTheFingers() async throws {
        let pane = try await startChat().pane
        app.typeText("many 25\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))
        let chat = element("chat.\(pane)")
        let point = "\(chat.frame.midX) \(chat.frame.midY)"
        func swipe(_ step: Int, _ steps: Int) async throws -> CGFloat {
            let before = last.frame.minY
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(step * 2) \(steps) 150 1".utf8))
            // Once it rests: the bottom's rubber band springs back.
            return (steady(2) { last.frame.minY } ?? last.frame.minY) - before
        }
        var upward = 1
        var left = try await swipe(upward, 15)
        if abs(left) < 2 {
            upward = -1
            left = try await swipe(upward, 15)
        }
        // 6 pt: AppKit can draw a frame or two of its own momentum ahead of the lift's empty one, which stops it (3.5
        // pt here).
        XCTAssertEqual(left, 30, accuracy: 6, "leaving the bottom")
        for (direction, steps) in [(upward, 25), (-upward, 25), (-upward, 5), (upward, 10)] {
            let moved = try await swipe(direction, steps)
            XCTAssertEqual(moved, CGFloat(direction * upward * steps * 2), accuracy: 6, "\(direction) × \(steps)")
        }
        let stacks = app.descendants(matching: .any).matching(identifier: "chat.\(pane).stack")
        let stack = stacks.element(boundBy: stacks.count - 1), user = row(pane, "user", "Question 25")
        stack.click()
        let tool = app.descendants(matching: .any).matching(identifier: "chat.\(pane).tool").firstMatch
        XCTAssertTrue(tool.exists(within: 3))
        XCTAssertEqual(stack.frame.minX, last.frame.minX - 18, accuracy: 1, "\(stack.frame) \(last.frame)")
        XCTAssertEqual(stack.frame.maxX, user.frame.maxX - 48, accuracy: 1, "\(stack.frame) \(user.frame)")
        XCTAssertEqual(tool.frame.maxX, stack.frame.maxX, accuracy: 1, "\(tool.frame) \(stack.frame)")

        let place = user.frame.minY
        app.typeText("many 3\r")
        let lasts = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "chat.\(pane).reply", "Last."))
        XCTAssertTrue(until(10) { lasts.count == 2 })
        XCTAssertEqual(user.frame.minY, place, accuracy: 1)
    }

    /// A split gives the card its final size once: the messages take it in the same frame as the reply box, which
    /// follows the card at once.
    func testASplitMovesTheMessagesWithTheReplyBox() async throws {
        let (tab, pane) = try await startChat()
        try await say("many 6", in: pane)
        XCTAssertTrue(row(pane, "reply", "Last.").exists(within: 10))
        let wide = element("pane.\(pane)").frame.width, inset = Int(wide - element("chat.\(pane)").frame.width)
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()
        // Each look is one snapshot: the card's width and the messages'.
        var looks: [String] = []
        XCTAssertTrue(until(5) {
            let seen = (try? nodes(of: mainWindows.firstMatch)) ?? []
            let card = seen.first { $0.identifier == "pane.\(pane)" }?.frame.width ?? 0
            let messages = seen.first { $0.identifier == "chat.\(pane)" }?.frame.width ?? 0
            looks.append("\(Int(card)) \(Int(messages))")
            return card < wide - 100 && abs(card - messages - CGFloat(inset)) < 2
        }, "\(looks)")
        XCTAssertFalse(looks.contains { look in
            let widths = look.split(separator: " ").compactMap { Int($0) }
            return widths[0] < Int(wide) - 100 && abs(widths[0] - widths[1] - inset) > 1
        }, "the messages kept their old width after the card's changed: \(looks)")
        _ = try await poll("a pane beside the chat") { try await order(tab).first { $0 != pane } }
    }

    private func keepsTop(_ top: Set<String>, of chat: XCUIElement, _ pane: String, narrow: Bool) {
        XCTAssertTrue(until(3) { (chat.frame.width < 600) == narrow && !atTop(of: chat, pane).isDisjoint(with: top) },
                      "\(top) \(atTop(of: chat, pane))")
        let last = row(pane, "reply", "Last.")
        XCTAssertFalse(last.exists && last.isHittable)
    }

    private func splitByButton(_ pane: String, in tab: String) async throws -> String {
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()
        return try await poll("a pane beside the chat") { try await order(tab).first { $0 != pane } }
    }

    private func staysAtTheBottom(_ pane: String, _ first: XCUIElement, _ scroll: () -> Void) {
        let bottom = element("chat.\(pane).bottom"), last = row(pane, "reply", "Last.")
        scroll()
        XCTAssertTrue(bottom.vanishes(within: 3))
        XCTAssertTrue(until(3) { last.isHittable })
        XCTAssertFalse(bottom.exists)
        XCTAssertTrue(first.exists)
    }

    func atTop(of chat: XCUIElement, _ pane: String) -> Set<String> {
        guard let found = try? nodes(of: chat) else { return [] }
        let kinds = ["chat.\(pane).reply", "chat.\(pane).user"], top = found[0].frame.minY
        return Set(found.compactMap { node in
            kinds.contains(node.identifier) && node.frame.maxY > top && node.frame.minY < top + 100
                ? node.value as? String : nil
        })
    }

    func nodes(of element: XCUIElement) throws -> [XCUIElementSnapshot] {
        var queue = try [element.snapshot()], nodes: [XCUIElementSnapshot] = []
        while let node = queue.popLast() {
            queue += node.children
            nodes.append(node)
        }
        return nodes
    }
}
