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

    /// Scrolled up, the next block comes above once the view's top nears the stack's, again and again, and the rows in
    /// view stay where they are: each swipe up (with its momentum) moves them as far as the first did, or less at the
    /// top, never a block more.
    func testALongChatLoadsEarlierRowsAsItScrollsUp() async throws {
        // A swipe and a look take about 3 s in the VM, and the chat is about 15 long swipes tall.
        executionTimeAllowance = 300
        let pane = try await startChat().pane
        app.typeText("many 25\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))
        let chat = element("chat.\(pane)"), loader = element("chat.\(pane).earlier")
        let first = row(pane, "user", "many 25"), bottom = element("chat.\(pane).bottom")
        XCTAssertFalse(first.exists)
        let kinds = ["user", "reply"].map { "chat.\(pane).\($0)" }
        let shown = { (try? self.nodes(of: chat).count { kinds.contains($0.identifier) }) ?? 0 }
        // One block at the open, at the bottom: no load before a scroll.
        let opened = shown()
        XCTAssertFalse(until(1) { shown() != opened }, "\(opened) \(shown())")
        XCTAssertLessThan(opened, 40)
        let point = "\(chat.frame.midX) \(chat.frame.midY)"
        func swipe(_ step: Int) async throws {
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(step) 20 0 1".utf8))
        }
        var upward = 0
        for step in [25, -25] where upward == 0 {
            try await swipe(step)
            if bottom.exists(within: 2) {
                upward = step
            }
        }
        var counts: [Int] = [], moves: [Int] = []
        for _ in 0 ..< 60 where !first.isHittable {
            let found = try nodes(of: chat), view = found[0].frame
            counts.append(found.count { kinds.contains($0.identifier) })
            let shown = try XCTUnwrap(found.first { kinds.contains($0.identifier) && view.contains($0.frame) })
            let (kind, text, place) = (shown.identifier, shown.value as? String ?? "", shown.frame.minY)
            try await swipe(upward)
            let same = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND value == %@", kind, text)).firstMatch
            try moves.append(Int(XCTUnwrap(steady(3) { same.frame.minY }) - place))
        }
        // A block is hundreds of points; a swipe's momentum varies by tens.
        XCTAssertFalse(moves.contains { $0 > moves[0] + 100 || $0 < -40 }, "a jump: \(moves) at \(counts)")
        XCTAssertTrue(first.isHittable, "\(counts)")
        XCTAssertFalse(loader.exists)
        staysAtTheBottom(pane, first) { element("chat.\(pane).bottom").click() }
        for _ in 0 ..< 5 where !first.isHittable {
            chat.scroll(byDeltaX: 0, deltaY: 5000)
        }
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

    /// A divider drag holds the messages' width until the drag ends, and the reply box's with it: both take the new one
    /// in the same frame.
    func testADividerDragMovesTheMessagesWithTheReplyBox() async throws {
        let (tab, pane) = try await startChat()
        try await say("many 6", in: pane)
        XCTAssertTrue(row(pane, "reply", "Last.").exists(within: 10))
        _ = try await splitByButton(pane, in: tab)
        let card = element("pane.\(pane)"), chat = element("chat.\(pane)"), box = element("chat.\(pane).composer")
        let divider = element("divider.\(tab).root")
        XCTAssertTrue(divider.exists(within: 3))
        let rest = try XCTUnwrap(steady(3) {
            [card.frame.width - chat.frame.width, chat.frame.width - box.frame.width]
        })
        let (inset, gap) = (Int(rest[0]), Int(rest[1]))
        let wide = card.frame.width
        let from = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).screenPoint
        let path = (1 ... 6).map { "\(from.x - CGFloat($0) * 10) \(from.y)" }.joined(separator: " 0.05 ")
        let drag = Task.detached { [one] in
            try await Self.post("\(one)/press", Data("\(from.x) \(from.y) \(path)".utf8))
        }
        // Each look is one snapshot: the card's width, the messages' and the reply box's.
        var looks: [[Int]] = []
        func look() -> [Int] {
            guard let seen = try? nodes(of: mainWindows.firstMatch) else { return [0, 0, 0] }
            let widths = ["pane.\(pane)", "chat.\(pane)", "chat.\(pane).composer"].map { id in
                Int(seen.first { $0.identifier == id }?.frame.width ?? 0)
            }
            looks.append(widths)
            return widths
        }
        // The app follows a busy runner's drag seconds late.
        XCTAssertTrue(until(30) {
            let widths = look()
            return widths[0] > 0 && CGFloat(widths[0]) < wide - 50 && abs(widths[0] - widths[1] - inset) <= 1
        }, "\(looks)")
        _ = try await drag.value
        try await release()
        XCTAssertNotNil(steady(3) { look() }, "\(looks)")
        XCTAssertTrue(looks.contains { abs($0[0] - $0[1] - inset) > 1 }, "the messages followed the drag: \(looks)")
        // One at most: a snapshot is many reads, and a frame can come between two.
        let apart = looks.count { abs($0[1] - $0[2] - gap) > 1 }
        XCTAssertLessThanOrEqual(apart, 1, "the box and the messages apart: \(looks)")
        XCTAssertEqual(looks.last.map { $0[0] - $0[1] } ?? 0, inset, accuracy: 1, "\(looks)")
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
