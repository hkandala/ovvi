import Synchronization
import XCTest

/// The runner is sandboxed and cannot reach herdr, so herdr calls go through the e2e helper on localhost
/// (`scripts/e2e-helper.py`). xcodebuild strips the TEST_RUNNER_ prefix from the names.
@MainActor
final class OvviUITests: XCTestCase {
    var one = ""
    var two = ""
    var three = "", four = "", five = "", six = "", seven = "", eight = ""
    let app = XCUIApplication()
    /// The app's first snapshot: login shell, herdr checks and a few herdr runs; slow on CI runners.
    let connect: TimeInterval = 30
    /// The part of the test that runs now (`step`): a failure names it. A Mutex: XCTest records issues off the main
    /// actor too.
    private let part = Mutex("")

    /// Starts one part of a test that walks several flows: an activity in the result, and the part's name before each
    /// failure's message.
    func step(_ name: String) {
        part.withLock { $0 = name }
        XCTContext.runActivity(named: name) { _ in }
    }

    override nonisolated func record(_ issue: XCTIssue) {
        var issue = issue
        let name = part.withLock { $0 }
        if !name.isEmpty {
            issue.compactDescription = "\(name): \(issue.compactDescription)"
        }
        super.record(issue)
    }

    override func setUp() async throws {
        continueAfterFailure = false
        one = try env("OVVI_SESSION")
        two = try env("OVVI_SESSION2")
        three = try env("OVVI_SESSION3")
        four = try env("OVVI_SESSION4")
        five = try env("OVVI_SESSION5")
        six = try env("OVVI_SESSION6")
        seven = try env("OVVI_SESSION7")
        eight = try env("OVVI_SESSION8")
        // Once per session; the runner may restart between tests, so ask herdr, not a static. The check is on
        // the last step, so a setup cut short builds again (and fails loudly) instead of passing half-built.
        let built = try await (Self.snapshot(two)["workspaces"] as? [[String: Any]] ?? [])
            .contains { $0["label"] as? String == "gamma" }
        if !built {
            try await Self.call(one, "workspace.create", ["label": "alpha", "cwd": "/tmp", "focus": false])
            try await Self.call(one, "pane.split", ["target_pane_id": "w1:p1", "direction": "right", "ratio": 0.6,
                                                    "cwd": "/tmp", "focus": false])
            try await Self.call(one, "pane.split", ["target_pane_id": "w1:p2", "direction": "down",
                                                    "cwd": "/tmp", "focus": false])
            try await Self.call(one, "tab.create", ["workspace_id": "w1", "label": "second", "cwd": "/tmp",
                                                    "focus": false])
            try await Self.call(one, "workspace.create", ["label": "beta", "cwd": "/tmp", "focus": false])
            try await Self.call(two, "workspace.create", ["label": "gamma", "cwd": "/tmp", "focus": false])
        }
        // The earlier test's app goes, so nothing sees what such a test sets up before its launch. The name is
        // "-[OvviUITests testName]".
        if !Self.ownLaunch.contains(String(name.split(separator: " ").last?.dropLast() ?? "")) {
            relaunch()
        } else if app.state != .notRunning {
            app.terminate()
        }
    }

    /// The pointer goes off the title row: left on a capsule, it would open a hover card in the next test's launch. Not
    /// async: a failure stops an async test inside the main actor's job, and an async tearDown then waits for the main
    /// actor until the 2-minute allowance runs out. The main window: the first match can be a floating window that a
    /// teardown block's close is closing, with no frame (an INFINITY point, on CI). A warp, not XCUITest's hover: that
    /// first looks for a window over the point, and a floating window gone meanwhile fails the test (on CI). XCTest
    /// runs a sync tearDown on the main thread; a fresh XCUIApplication is the same app, so self stays out.
    override func tearDown() {
        MainActor.assumeIsolated {
            let main = XCUIApplication().windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'"))
                .firstMatch
            if main.exists {
                let frame = main.frame
                CGWarpMouseCursorPosition(CGPoint(
                    x: frame.minX + frame.width * 0.6,
                    y: frame.minY + frame.height * 0.9,
                ))
            }
        }
    }

    func testShowsWorkspacesTabsAndSplits() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        XCTAssertTrue(element("workspace.w2").exists)
        XCTAssertTrue(element("tab.w1:t1").exists)
        XCTAssertTrue(element("tab.w1:t2").exists)
        XCTAssertEqual(app.textFields.matching(NSPredicate(format: "hasKeyboardFocus == true")).count, 0)
        XCTAssertNotEqual(element("sidebar.filter").elementType, .textField)

        let first = element("pane.w1:p1").frame, second = element("pane.w1:p2").frame
        let third = element("pane.w1:p3").frame
        XCTAssertLessThan(first.maxX, second.minX)
        XCTAssertEqual(first.width / (first.width + second.width), 0.6, accuracy: 0.03)
        XCTAssertLessThan(second.maxY, third.minY)
        XCTAssertLessThan(first.maxX, third.minX)
        keepScreenshot("split")

        element("tab.w1:t2").click()
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        XCTAssertTrue(app.windows.firstMatch.has(\.title, "second - \(one)", within: 2))

        element("workspace.w2").click()
        XCTAssertTrue(element("page.w2:t1").exists(within: 2))
        XCTAssertFalse(element("page.w1:t1").exists)
        XCTAssertTrue(element("pane.w2:p1").exists)
        keepScreenshot("second workspace")
    }

    func testSidebarFilterNarrowsTheWorkspaces() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let filter = element("sidebar.filter")
        filter.click()
        XCTAssertTrue(hasKeyboard(filter))
        filter.typeText("bet")
        XCTAssertTrue(element("workspace.w1").vanishes(within: 2))
        XCTAssertTrue(element("workspace.w2").exists)
        keepScreenshot("sidebar filter")
    }
}

extension OvviUITests {
    func expectPTYSize(_ pane: String, in window: XCUIElement? = nil) async throws {
        let terminal = element("terminal.\(pane)", in: window)
        try await waitForPrompt(pane)
        let sizes = { (screen: String) in screen.split(separator: "\n").filter { $0.wholeMatch(of: /\d+ \d+/) != nil } }
        var seen = "no grid"
        do {
            try await poll("stty size in \(pane) to match its card", times: 30) { () async throws -> String? in
                guard terminal.exists, let grid = terminal.value as? String, !grid.isEmpty else { return nil }
                // Cleared first: the last try's size line would read as this one's.
                try await send("clear\r", to: pane)
                try await waitFor(pane, times: 20) { sizes($0).isEmpty }
                try await send("stty size\r", to: pane)
                var screen = ""
                try await waitFor(pane, times: 20) {
                    screen = $0
                    return !sizes($0).isEmpty
                }
                seen = "card \(grid), screen \(screen.split(separator: "\n").suffix(3).joined(separator: " | "))"
                return sizes(screen).contains { $0 == grid } ? grid : nil
            }
        } catch {
            throw Waited(description: "waited for stty size in \(pane) to match its card: \(seen)")
        }
    }

    func waitForPrompt(_ pane: String, in session: String? = nil) async throws {
        try await waitFor(pane, in: session) { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// `done` is escaping: the compiler rejects it otherwise across files.
    func waitFor(_ pane: String, in session: String? = nil, times: Int = 50,
                 _ done: @escaping (String) -> Bool) async throws
    {
        var last = ""
        do {
            try await poll("pane \(pane) to show it", times: times) { () async throws -> String? in
                last = try await read(pane, in: session)
                return done(last) ? last : nil
            }
        } catch is Waited {
            throw Waited(description: "waited for pane \(pane) to show it; it showed:\n\(last)")
        }
    }

    /// `line` may wrap: a row ends where it wraps, and one that wraps at a space drops it.
    func waitFor(_ pane: String, toShow line: String, times: Int = 50) async throws {
        let squeezed = line.filter { !$0.isWhitespace }
        try await waitFor(pane, times: times) { $0.filter { !$0.isWhitespace }.contains(squeezed) }
    }

    func env(_ name: String) throws -> String {
        try XCTUnwrap(ProcessInfo.processInfo.environment[name], "run through make e2e")
    }

    enum Windows {
        case ignored
        /// A launch with -ApplePersistenceIgnoreState saves no state at ⌘Q.
        case saved
        /// `-machines []`: none of the user's machines, whose masters a test must not touch.
        case restored
    }

    /// `pin`: the settings as they ship, whatever the user's Ovvi has (the defaults are shared); off for a test that
    /// changes them in the Settings window, where a pinned key cannot change.
    func relaunch(_ session: String? = nil, _ args: [String] = [], pin: Bool = true, windows: Windows = .ignored) {
        let config = args.contains("-configFolder") ? ["-archivedHome", Self.archivedHome] : Self.noConfig
        let shipped = ["notifyNeedsYou": "YES", "notifyFinished": "YES", "notifyFromAgents": "YES",
                       "terminalFont": "", "cursorStyle": "block", "cursorBlink": "YES", "optionKey": "characters",
                       "copyOnSelect": "NO", "agentView": "terminal", "agentArguments.claude": "",
                       "agentArguments.codex": "", "agentArguments.pi": "", "agentArguments.opencode": "",
                       "showClosedSessions": "YES", "newPaneOpens": "", "spaceOrder": "manual"]
        let pinned = pin ? shipped.sorted { $0.key < $1.key }.filter { !args.contains("-\($0.key)") }
            .flatMap { ["-\($0.key)", $0.value] } : []
        let start = switch windows {
        case .ignored: ["-session", session ?? one, "-ApplePersistenceIgnoreState", "YES"]
        case .saved: ["-session", session ?? one, "-NSQuitAlwaysKeepsWindows", "YES"]
        case .restored: ["-defaultSession", session ?? one, "-machines", "[]"]
        }
        app.launchArguments = start + config + pinned + args
        // The default plugins install from npm's cache (`make web` fills it), never the network.
        app.launchEnvironment["npm_config_offline"] = "true"
        app.launch()
    }

    static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures").path

    /// CI puts both folders on its login shell's PATH.
    static let agents = "\(fixtures)/agents"

    /// In this checkout, which the pane's shell reads: the runner is sandboxed.
    static let scripts = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts")

    static let archivedHome = "/tmp/ovvi-e2e-archived"

    /// A config folder of the tests' own, never the user's. The e2e helper's launches use the same folders (`ISOLATED`
    /// in scripts/e2e-helper.py), and scripts/e2e.sh empties the config folder.
    static let noConfig = ["-configFolder", "/tmp/ovvi-e2e-no-config", "-archivedHome", archivedHome]

    static let keyHost = #"[{"id":"e2e-key","name":"Key Host","target":"ovvi-key","icon":"server.rack"}]"#

    static let onKeyHost = ["-machines", keyHost, "-machine", "e2e-key"]

    /// Which sign goes forward follows the natural scrolling setting (one way here, the other on CI).
    func swipe<Value: Equatable>(_ element: XCUIElement, by distance: Double? = nil, until target: XCUIElement,
                                 _ property: KeyPath<XCUIElement, Value>, _ value: Value) async throws
    {
        var delta = -(distance ?? Double(element.frame.width))
        for _ in 0 ..< 6 {
            element.hover()
            element.scroll(byDeltaX: delta, deltaY: 0)
            delta = -delta
            if target.has(property, value, within: 0.7) {
                return
            }
        }
        throw Waited(description: "waited for the swipe over \(element.identifier)")
    }

    /// Over the header, not the card's center: SwiftUI does not see the pointer jump straight into a terminal view,
    /// which takes the mouse moves.
    func hoverHeader(_ pane: String) {
        element("pane.\(pane)").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 17)).hover()
    }

    func newTab(_ label: String, in workspace: String = "w2") async throws -> (tab: String, pane: String) {
        let (tab, pane) = try await createTab(in: workspace, label: label)
        closeAfter("tab", tab)
        let row = element("workspace.\(workspace)")
        XCTAssertTrue(row.exists(within: connect), "no row for \(workspace)")
        if !row.isSelected {
            row.click()
        }
        // Hittable and at rest: the bar lays out again after a workspace change, and a click on an earlier frame lands
        // beside it (on CI). Up to 10 s, herdr's own bound: right after a launch CI's herdr took 3 s to answer a
        // snapshot read or a `tab.create`, and sent `tab.created` 1.3 s after its reply.
        let capsule = element("tab.\(tab)")
        XCTAssertTrue(capsule.has(\.isHittable, true, within: 10))
        // One query a look: a slow one (over 1 s on a busy CI Mac) makes the two of each look outlast the wait.
        XCTAssertNotNil(steady(5) { capsule.frame }, "\(capsule.frame)")
        return (tab, pane)
    }

    func newWorkspace(_ label: String, tabs count: Int = 1) async throws -> (tabs: [String], pane: String) {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await createWorkspace(label)
        let workspace = workspace(of: tab)
        var tabs = [tab]
        for _ in 1 ..< count {
            try await tabs.append(createTab(in: workspace).tab)
        }
        let row = element("workspace.\(workspace)")
        XCTAssertTrue(row.exists(within: 3))
        row.click()
        XCTAssertTrue(element("tab.\(tabs[0])").exists(within: 3))
        XCTAssertTrue(element("tabs.count").has(\.stringValue, "\(count)", within: 3))
        return (tabs, pane)
    }

    func typeAndRead(_ pane: String) async throws {
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeText("echo ovvi-keys-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor(pane) { $0.contains("\novvi-keys-42") }
    }

    @discardableResult
    func openPalette() -> XCUIElement {
        app.typeKey("k", modifierFlags: .command)
        let filter = element("palette.filter")
        XCTAssertTrue(hasKeyboard(filter), "the keyboard is on \(keyboardOwner())")
        return filter
    }

    func keyboardOwner() -> String {
        let owner = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        return owner.exists ? "\(owner.elementType.rawValue) '\(owner.identifier)' '\(owner.label)'" : "nothing"
    }

    func keepScreenshot(_ name: String, of window: XCUIElement? = nil) {
        if let window {
            raise(window)
        }
        let attachment = XCTAttachment(screenshot: (window ?? app.windows.firstMatch).screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// One query a try: between `exists` and a focus read a terminal can go as its floating window comes forward, which
    /// XCUITest fails the test for (on CI).
    func hasKeyboard(_ identifier: String, in window: XCUIElement? = nil) -> Bool {
        let focused = NSPredicate(format: "identifier == %@ AND hasKeyboardFocus == true", identifier)
        return until(2) { (window ?? app).descendants(matching: .any).matching(focused).firstMatch.exists }
    }

    func hasKeyboard(_ element: XCUIElement) -> Bool {
        let focus = NSPredicate(format: "hasKeyboardFocus == true")
        return until(2) { element.exists && focus.evaluate(with: element) }
    }

    /// By its value: a plain text's label is empty.
    func text(_ value: String, in page: XCUIElement? = nil) -> XCUIElement {
        (page ?? app).staticTexts.matching(NSPredicate(format: "value == %@", value)).firstMatch
    }

    /// The main windows, by identifier: the first window can be a tooltip, a hover card or a floating pane.
    var mainWindows: XCUIElementQuery {
        app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'"))
    }

    func element(_ identifier: String, in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? app).descendants(matching: .any)[identifier]
    }
}
