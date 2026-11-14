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
        XCTAssertTrue(element("pane.\(pane).view.chat").has(\.isSelected, true, within: 10))
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
    }

    /// Scrolled up, the next block comes above once the view's top nears the stack's, again and again, and the rows in
    /// view stay where they are: each swipe up (with its momentum) moves them at most its own travel, never a block
    /// more.
    func testALongChatLoadsEarlierRowsAsItScrollsUp() async throws {
        // A swipe and a look take about 3 s in the VM, and the chat is about 15 long swipes tall.
        executionTimeAllowance = 300
        let pane = try await startChat(["-chatDropSeconds", "10"]).pane
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
        let place = try XCTUnwrap(steady(3) { last.frame.minY })
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
        // A swipe's travel: 20 moves of 25 pt and a momentum of 25 pt × 0.9ⁿ, about 750 pt; less where it meets the
        // loaded rows' top before the next block comes (the first swipe too). A block is thousands of points.
        XCTAssertFalse(moves.contains { $0 > 790 || $0 < -40 }, "a jump: \(moves) at \(counts)")
        XCTAssertTrue(first.isHittable && !loader.exists, "\(counts) \(loader.exists)")
        // After 10 s at the exact bottom, the stack is the newest block again, and the bottom row stays where it was. A
        // scroll up meanwhile starts the wait again.
        try await dropsToOneBlock(pane, opened, at: place, leaving: true) { bottom.click() }
        // Up with the wheel, which has no phases, until a block comes; down with swipes, whose momentum ends at the
        // bottom.
        for _ in 0 ..< 5 where !until(2, { shown() > opened }) {
            chat.scroll(byDeltaX: 0, deltaY: 5000)
        }
        XCTAssertTrue(until(2) { shown() > opened }, "\(shown()) \(opened)")
        try await dropsToOneBlock(pane, opened, at: place) {
            for _ in 0 ..< 30 where !last.isHittable {
                try await swipe(-upward)
            }
            try await swipe(-upward)
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
    /// follows the card at once. Narrower than the chat's minimum, the messages keep the minimum.
    func testASplitMovesTheMessagesWithTheReplyBox() async throws {
        let (tab, pane) = try await startChat()
        try await say("many 6", in: pane)
        XCTAssertTrue(row(pane, "reply", "Last.").exists(within: 10))
        let wide = element("pane.\(pane)").frame.width, inset = Int(wide - element("chat.\(pane)").frame.width)
        let expected = { (card: CGFloat) in max(Int(card) - inset, 360) }
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()
        // Each look is one snapshot: the card's width and the messages'.
        var looks: [String] = []
        XCTAssertTrue(until(5) {
            let seen = (try? nodes(of: mainWindows.firstMatch)) ?? []
            let card = seen.first { $0.identifier == "pane.\(pane)" }?.frame.width ?? 0
            let messages = seen.first { $0.identifier == "chat.\(pane)" }?.frame.width ?? 0
            looks.append("\(Int(card)) \(Int(messages))")
            return card < wide - 100 && abs(expected(card) - Int(messages)) < 2
        }, "\(looks)")
        XCTAssertFalse(looks.contains { look in
            let widths = look.split(separator: " ").compactMap { Int($0) }
            return widths[0] < Int(wide) - 100 && abs(expected(CGFloat(widths[0])) - widths[1]) > 1
        }, "the messages kept their old width after the card's changed: \(looks)")
        _ = try await poll("a pane beside the chat") { try await order(tab).first { $0 != pane } }
    }

    /// A divider drag holds the messages' width until the drag ends, and the reply box's with it: both take the new one
    /// in the same frame. The drag widens the chat: a split leaves it near its minimum, which the messages keep.
    func testADividerDragMovesTheMessagesWithTheReplyBox() async throws {
        let (tab, pane) = try await startChat()
        try await say("many 6", in: pane)
        XCTAssertTrue(row(pane, "reply", "Last.").exists(within: 10))
        let card = element("pane.\(pane)"), chat = element("chat.\(pane)"), box = element("chat.\(pane).composer")
        let inset = Int(card.frame.width - chat.frame.width)
        let expected = { (card: Int) in max(card - inset, 360) }
        _ = try await splitByButton(pane, in: tab)
        let divider = element("divider.\(tab).root")
        XCTAssertTrue(divider.exists(within: 3))
        let rest = try XCTUnwrap(steady(3) { [card.frame.width, chat.frame.width - box.frame.width] })
        let (narrow, gap) = (Int(rest[0]), Int(rest[1]))
        let from = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).screenPoint
        let path = (1 ... 6).map { "\(from.x + CGFloat($0) * 10) \(from.y)" }.joined(separator: " 0.05 ")
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
            return widths[0] > narrow + 50 && abs(expected(widths[0]) - widths[1]) <= 1
        }, "\(looks)")
        _ = try await drag.value
        try await release()
        XCTAssertNotNil(steady(3) { look() }, "\(looks)")
        XCTAssertTrue(looks.contains { abs(expected($0[0]) - $0[1]) > 1 }, "the messages followed the drag: \(looks)")
        // One at most: a snapshot is many reads, and a frame can come between two.
        let apart = looks.count { abs($0[1] - $0[2] - gap) > 1 }
        XCTAssertLessThanOrEqual(apart, 1, "the box and the messages apart: \(looks)")
        XCTAssertEqual(looks.last.map { expected($0[0]) - $0[1] } ?? 1, 0, accuracy: 1, "\(looks)")
    }

    /// Narrower than its minimum width, the chat keeps that width and scrolls sideways to its reply box's Send.
    func testANarrowChatScrollsSideways() async throws {
        let pane = try await startChat(["-balanceSplits", "NO"]).pane
        try await say("steps", in: pane)
        XCTAssertTrue(row(pane, "reply", "Done.").exists(within: 10))
        let card = element("pane.\(pane)"), chat = element("chat.\(pane)"), send = element("chat.\(pane).send")
        XCTAssertTrue(send.exists(within: 5))
        _ = try await Self.call(one, "pane.split", ["target_pane_id": pane, "direction": "right",
                                                    "ratio": 280 / card.frame.width, "cwd": "/tmp", "focus": false])
        XCTAssertTrue(until(5) { card.frame.width < 340 }, "\(card.frame)")
        XCTAssertNotNil(steady(3) { [card.frame, send.frame] })
        XCTAssertEqual(chat.frame.width, 360, accuracy: 1)
        XCTAssertGreaterThan(send.frame.maxX, card.frame.maxX)
        XCTAssertTrue([-600.0, 600].contains { step in
            chat.scroll(byDeltaX: step, deltaY: 0)
            return until(2) { send.frame.maxX <= card.frame.maxX }
        }, "\(send.frame) \(card.frame)")
    }

    private func keepsTop(_ top: Set<String>, of chat: XCUIElement, _ pane: String, narrow: Bool) {
        XCTAssertTrue(until(3) { (chat.frame.width < 600) == narrow && !atTop(of: chat, pane).isDisjoint(with: top) },
                      "\(top) \(atTop(of: chat, pane))")
        let last = row(pane, "reply", "Last.")
        XCTAssertFalse(last.exists && last.isHittable)
    }

    /// `leaving`: during the wait, a scroll up and back, after which the drop waits its whole time again.
    private func dropsToOneBlock(_ pane: String, _ opened: Int, at place: CGFloat, leaving: Bool = false,
                                 _ scroll: () async throws -> Void) async throws
    {
        let chat = element("chat.\(pane)"), last = row(pane, "reply", "Last."), bottom = element("chat.\(pane).bottom")
        let kinds = ["user", "reply"].map { "chat.\(pane).\($0)" }
        let shown = { (try? self.nodes(of: chat).count { kinds.contains($0.identifier) }) ?? 0 }
        try await scroll()
        XCTAssertTrue(bottom.vanishes(within: 3))
        let rested = Date.now
        XCTAssertFalse(until(2) { shown() == opened }, "dropped before its wait")
        if leaving {
            chat.scroll(byDeltaX: 0, deltaY: 200)
            XCTAssertTrue(bottom.exists(within: 2))
            bottom.click()
            XCTAssertTrue(bottom.vanishes(within: 3))
            // Until a second past the first wait's end, within the new one's.
            XCTAssertFalse(until(rested.addingTimeInterval(11).timeIntervalSinceNow) { shown() == opened },
                           "the scroll up did not start the wait again")
        }
        var looks: [CGFloat] = []
        XCTAssertTrue(until(14) {
            looks.append(last.frame.minY)
            return shown() == opened
        }, "\(shown()) \(opened)")
        XCTAssertFalse(until(1) {
            looks.append(last.frame.minY)
            return shown() != opened
        }, "\(shown()) \(opened)")
        // From its first look there: a swipe's bounce at the end settles first.
        let settled = looks.drop { abs($0 - place) > 1 }
        XCTAssertFalse(settled.isEmpty || settled.contains { abs($0 - place) > 1 }, "\(place): \(looks)")
        XCTAssertFalse(row(pane, "user", "many 25").exists)
    }

    private func splitByButton(_ pane: String, in tab: String) async throws -> String {
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()
        return try await poll("a pane beside the chat") { try await order(tab).first { $0 != pane } }
    }

    func row(_ pane: String, _ kind: String, _ value: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "chat.\(pane).\(kind)", value)).firstMatch
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
