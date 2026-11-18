import XCTest

extension OvviUITests {
    func testTheSessionTitleListsTheWindowsSessions() async throws {
        relaunch(one, ["-forceMotion", "YES"]) // the shelf's slide (CI has Reduce Motion on)
        try await running(five)
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        let title = element("sidebar.header"), mine = element("sidebar.session.\(one)")
        let theirs = element("sidebar.session.\(two)"), opener = element("sidebar.open-session")
        let filter = element("sidebar.filter"), row = element("workspace.w1")
        XCTAssertTrue(title.has(\.stringValue, two, within: 3))
        let keys = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'terminal.' AND hasKeyboardFocus == true")).firstMatch
        XCTAssertTrue(keys.exists(within: 3))
        let card = keys.identifier
        let buttons = ["sidebar.header", "sidebar.overview", "sidebar.sort", "sidebar.new-workspace"]
            .map { element($0) }
        let still = buttons.map(\.frame)
        // The list under the filter, not scrolled: a slide that resized it by a fraction of a pixel left it scrolled.
        let listTop = row.frame.minY - filter.frame.maxY
        title.click()
        XCTAssertTrue(mine.exists(within: 2))
        XCTAssertEqual(buttons.map(\.frame), still, "the header moved")
        // The dropdown sits 8 pt under the header, then its 4 pt inset.
        XCTAssertTrue(until(2) { abs(mine.frame.minY - title.frame.maxY - 12) < 0.5 }, "\(mine.frame) \(title.frame)")
        XCTAssertTrue(until(2) { !keys.exists }, "the shelf took no keys")
        // This window's pages in its order, the one in view marked; not a stopped one or a running one not open here.
        XCTAssertEqual(theirs.frame.minY, mine.frame.maxY, accuracy: 0.5)
        XCTAssertTrue(theirs.isSelected)
        XCTAssertFalse(mine.isSelected)
        for session in [three, five] {
            XCTAssertFalse(element("sidebar.session.\(session)").exists, session)
        }
        // Over the filter: its 4 pt inset, then 16 pt, as far as the header's glyphs are over the dropdown.
        XCTAssertNotNil(steady(2) { filter.frame })
        XCTAssertLessThan(theirs.frame.maxY, opener.frame.minY)
        XCTAssertEqual(filter.frame.minY - opener.frame.maxY, 20, accuracy: 0.5)
        XCTAssertEqual(row.frame.minY - filter.frame.maxY, listTop, accuracy: 0.01, "the list is scrolled")
        keepScreenshot("session shelf")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(mine.vanishes(within: 2))
        XCTAssertTrue(hasKeyboard(card))
        XCTAssertNotNil(steady(2) { filter.frame })
        XCTAssertEqual(row.frame.minY - filter.frame.maxY, listTop, accuracy: 0.01, "the list is scrolled")

        expectTheShelfStaysOpen()
        try await expectOnlyTheSpacesSlide()
        expectARowDetachesItsSession()
    }

    /// Open after a pick, Open Session, a click in the filter, typing and a click on a space; folded by the title.
    private func expectTheShelfStaysOpen() {
        let title = element("sidebar.header"), mine = element("sidebar.session.\(one)")
        let theirs = element("sidebar.session.\(two)"), filter = element("sidebar.filter")
        let keys = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'terminal.' AND hasKeyboardFocus == true")).firstMatch
        step("The arrows and Return pick a session; the shelf stays open, its rows still, the mark moves")
        title.click()
        let rows = steady(2) { mine.exists ? [mine.frame, theirs.frame] : nil }
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.has(\.stringValue, one, within: 3))
        XCTAssertTrue(mine.has(\.isSelected, true, within: 2))
        XCTAssertFalse(theirs.isSelected)
        XCTAssertEqual([mine.frame, theirs.frame], rows, "the rows moved")
        XCTAssertTrue(keys.exists(within: 3), "the new page's card has the keys")

        step("A click on a session picks it; the shelf stays open")
        theirs.click()
        XCTAssertTrue(title.has(\.stringValue, two, within: 3))
        XCTAssertTrue(theirs.has(\.isSelected, true, within: 2))
        mine.click()
        XCTAssertTrue(title.has(\.stringValue, one, within: 3))
        XCTAssertTrue(mine.has(\.isSelected, true, within: 2))

        step("Open Session leaves it open")
        element("sidebar.open-session").click()
        let panel = element("open-session.filter")
        XCTAssertTrue(hasKeyboard(panel))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.vanishes(within: 2))
        XCTAssertTrue(theirs.exists)

        step("The filter, clicked once the shelf is open and typed into, and a space leave it open; the title folds it")
        title.click()
        XCTAssertTrue(theirs.vanishes(within: 2))
        title.click()
        XCTAssertTrue(theirs.exists(within: 2))
        XCTAssertNotNil(steady(2) { filter.frame })
        filter.click()
        XCTAssertTrue(hasKeyboard(filter))
        app.typeText("zz")
        XCTAssertTrue(filter.has(\.stringValue, "zz", within: 2))
        XCTAssertTrue(hasKeyboard(filter), "the shelf took the keys back")
        XCTAssertTrue(theirs.exists)
        app.typeKey(.escape, modifierFlags: [])
        element("workspace.w2").click()
        XCTAssertTrue(keys.exists(within: 3))
        XCTAssertTrue(theirs.exists)
        title.click()
        XCTAssertTrue(theirs.vanishes(within: 2))
    }

    /// Held a third of the way to the next page: the rows follow the fingers, the header and the filter stay.
    private func expectOnlyTheSpacesSlide() async throws {
        step("Held mid-swipe, only the spaces move")
        let title = element("sidebar.header"), filter = element("sidebar.filter"), sidebar = element("sidebar").frame
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.'"))
            .firstMatch
        let (titleX, filterX, rowX) = (title.frame.minX, filter.frame.minX, row.frame.minX)
        let path = "\(one)/swipe"
        var moved = false
        // The other way if natural scrolling is off.
        for sign in [-1.0, 1.0] where !moved {
            let swipe = Data("\(sidebar.midX) \(sidebar.midY) \(10 * sign) \(Int(sidebar.width / 30)) 3000".utf8)
            async let swiped = Self.post(path, swipe)
            try await Task.sleep(for: .seconds(1.5))
            moved = abs(row.frame.minX - rowX) > 20
            if moved {
                XCTAssertEqual(title.frame.minX, titleX, accuracy: 0.5)
                XCTAssertEqual(filter.frame.minX, filterX, accuracy: 0.5)
                keepScreenshot("held mid-swipe")
            }
            _ = try await swiped
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertTrue(moved, "no swipe moved the rows")
        XCTAssertEqual(title.stringValue, one)
    }

    private func expectARowDetachesItsSession() {
        step("A hovered session row shows Detach Session, Open Session none; with one page left, no row has it")
        let mine = element("sidebar.session.\(one)"), theirs = element("sidebar.session.\(two)")
        let detach = element("sidebar.session.\(two).detach")
        let any = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.detach'")).firstMatch
        element("sidebar.header").click()
        XCTAssertNotNil(steady(2) { theirs.exists ? theirs.frame : nil })
        element("sidebar.open-session").hover()
        XCTAssertFalse(until(1) { any.exists })
        theirs.hover()
        XCTAssertTrue(detach.exists(within: 2))
        XCTAssertEqual(detach.label, "Detach Session")
        // Its right edge as far in as the row's symbol is from its left.
        XCTAssertEqual(theirs.frame.maxX - detach.frame.maxX, 4, accuracy: 0.5)
        detach.click()
        XCTAssertTrue(until(3) { !pageList().contains(two) })
        XCTAssertTrue(theirs.vanishes(within: 2))
        XCTAssertTrue(mine.exists, "the shelf folded")
        mine.hover()
        XCTAssertFalse(until(1) { any.exists }, "the last page detaches")
    }
}
