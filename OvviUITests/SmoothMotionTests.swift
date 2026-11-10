import XCTest

extension OvviUITests {
    /// Every card's place at each display frame (`MovingCard`'s track): ⌘D, ⇧⌘D, zoom and back, a divider drag, a
    /// close, Split Left and Up, on a terminal, File Explorer and a browser, in each look. Each edge goes one way to
    /// its place, never past it, in steps the curve allows, and lands once; the surface goes with the card; the content
    /// lays out once.
    func testSplitsMoveEachCardOnceToItsPlace() async throws {
        executionTimeAllowance = 600
        // Split Left and Up swap, which moves herdr's focus.
        restoreHerdrFocusAfter()
        var problems: [String] = []
        for (look, kinds) in [("glass dark", ["terminal", "explorer", "browser"]), ("glass light", ["explorer"]),
                              ("classic dark", ["explorer"]), ("classic light", ["terminal"])]
        {
            let words = look.split(separator: " ").map(String.init)
            relaunch(one, ["-recordMotion", "YES", "-forceMotion", "YES", "-interfaceStyle", words[0],
                           "-appearance", words[1]])
            XCTAssertTrue(element("workspace.w2").exists(within: connect))
            for kind in kinds {
                try await problems += splits("\(look) \(kind)", kind)
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    private func splits(_ name: String, _ kind: String) async throws -> [String] {
        let (tab, pane) = try await newTab("smooth \(kind)")
        element("tab.\(tab)").click()
        switch kind {
        case "explorer": try await rename(pane, "ovvi:explorer#\(Self.iid()) /private\(Self.smooth)/")
        case "browser": try await rename(pane, "ovvi:browser#\(Self.iid()) file://\(Self.smooth)/page.html")
        default:
            // The runner is sandboxed: the shell makes the browser's page.
            try await waitForPrompt(pane)
            try await send("mkdir -p \(Self.smooth) && echo '<p>A page.</p>' >\(Self.smooth)/page.html && clear && "
                + "echo made-$((2+3))\r", to: pane)
            try await waitFor(pane) { $0.contains("made-5") }
        }
        guard element("motion.\(pane)").exists(within: 10) else { return ["\(name): no card"] }
        // Its page and its web view settle first.
        try await Task.sleep(for: .seconds(2))
        hoverHeader(pane)
        element("pane.\(pane)").click()
        var problems: [String] = [], known: [String: String] = [:]
        let keys: [(String, XCUIElement.KeyModifierFlags)] = [("⌘D", .command), ("⇧⌘D", [.command, .shift])]
        for (step, flags) in keys + [("Split Left", []), ("Split Up", [])] {
            try await problems += moves("\(name) \(step)", in: tab, known: &known) {
                if flags.isEmpty {
                    paneMenu(pane, step)
                } else {
                    app.typeKey("d", modifierFlags: flags)
                }
                try await expect("\(name) \(step): the split") { try await order(tab).count == 2 }
            }
            let new = try await order(tab).first { $0 != pane } ?? ""
            // Its terminal takes its new size as the motion starts, not 150 ms after it lands.
            if kind == "terminal", !flags.isEmpty {
                let host = element("host.\(pane)").label,
                    fit = host.components(separatedBy: " fit ").last.flatMap { Int($0) }
                if fit.map({ $0 > Int(Self.slide) }) ?? true {
                    problems.append("\(name) \(step): the terminal fitted late: \(host)")
                }
            }
            if !flags.isEmpty {
                try await problems += keyed("\(name) \(step)", step, tab: tab, cards: (pane, new), known: &known)
            }
            try await problems += moves("\(name) \(step) close", in: tab, known: &known) {
                _ = try await Self.call(one, "pane.close", ["pane_id": new])
                try await expect("\(name) \(step): the close") { try await order(tab).count == 1 }
            }
            element("pane.\(pane)").click()
        }
        // A bar of many tabs would scroll the next one out of view.
        _ = try await Self.call(one, "tab.close", ["tab_id": tab])
        return problems
    }

    /// After a key's split: a third card, zoom and back, a divider drag.
    private func keyed(_ what: String, _ step: String, tab: String, cards: (String, String),
                       known: inout [String: String]) async throws -> [String]
    {
        var problems: [String] = []
        if step == "⌘D" {
            // Thirds: herdr's ratios as 32-bit floats must not move a card again.
            try await problems += moves("\(what) thirds", in: tab, known: &known) {
                app.typeKey("d", modifierFlags: .command)
                try await expect("\(what): the third card") { try await order(tab).count == 3 }
            }
            let third = try await order(tab).first { $0 != cards.0 && $0 != cards.1 } ?? ""
            try await problems += moves("\(what) thirds close", in: tab, known: &known) {
                _ = try await Self.call(one, "pane.close", ["pane_id": third])
                try await expect("\(what): the close") { try await order(tab).count == 2 }
            }
        }
        for again in ["zoom", "restore"] {
            try await problems += moves("\(what) \(again)", in: tab, known: &known) {
                app.typeKey(.return, modifierFlags: [.command, .shift])
            }
        }
        // Followed at once, with no curve; nothing moves after the drop.
        try await problems += moves("\(what) divider drag", in: tab, curve: false, known: &known) {
            let divider = element("divider.\(tab).root").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            divider.click(forDuration: 0.2, thenDragTo: divider.withOffset(step == "⌘D" ? CGVector(dx: -80, dy: 0)
                    : CGVector(dx: 0, dy: -60)))
        }
        return problems
    }

    private static let smooth = "/tmp/ovvi-e2e-smooth"

    private static func iid() -> String {
        String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(6))
    }

    private func rename(_ pane: String, _ label: String) async throws {
        try await Self.call(one, "pane.rename", ["pane_id": pane, "label": label])
    }

    /// Acts, then waits for each card's track (published 0.4 s after its last change) and 1 s more, which catches a
    /// second motion herdr's answer starts. `known`: each card's last label read, as an away card's is hidden during a
    /// zoom.
    private func moves(_ step: String, in tab: String, curve: Bool = true, known: inout [String: String],
                       _ act: () async throws -> Void) async throws -> [String]
    {
        for id in try await order(tab) where element("motion.\(id)").exists {
            known[id] = element("motion.\(id)").label
        }
        let before = known
        try await act()
        try await Task.sleep(for: .seconds(1.5))
        let ids = try await order(tab)
        var problems: [String] = [], moved = 0
        for id in ids {
            let card = element("motion.\(id)")
            guard card.exists else { continue }
            let label = card.label, count = Self.slides(label) - Self.slides(before[id] ?? "")
            known[id] = label
            if count > 1 {
                problems.append("\(step) \(id): \(count) motions: \(label)")
            }
            if label != before[id] {
                moved += 1
                problems += Self.smoothness(label, curve: curve).map { "\(step) \(id): \($0)" }
            }
        }
        if moved == 0 {
            problems.append("\(step): no card moved")
        }
        return problems
    }

    static func slides(_ label: String) -> Int {
        let words = label.split(separator: " ")
        return words.firstIndex(of: "slides").flatMap { Int(words[min($0 + 1, words.count - 1)]) } ?? 0
    }

    /// The motion's curve: ease-out over 0.13 s, at most 1.72 times its mean speed (its start). A sample's time and
    /// the frame it shows can be two display frames apart (a late commit starts the motion after its arm).
    static let slide = 130.0, steepest = 1.75, near: CGFloat = 1.5, frame: CGFloat = 2000 / 60

    /// What breaks a smooth motion in a card's track, empty when none does. A drag (no `curve`) moves at the
    /// pointer's pace and lays the content out at each step.
    static func smoothness(_ label: String, curve: Bool = true) -> [String] {
        let words = label.components(separatedBy: " track "), samples = samples(words.count == 2 ? words[1] : "")
        guard label.count < 510 else { return ["the track was cut: \(label)"] }
        guard samples.count >= 2, let first = samples.first, let last = samples.last else {
            return ["no track: \(label)"]
        }
        let head = words[0].split(separator: " ")
        var problems: [String] = []
        if let off = head.firstIndex(of: "surface").flatMap({ Int(head[$0 + 1]) }), off > 0 {
            problems.append("the surface was off the card in \(off) frames")
        }
        // Over a point: SwiftUI rounds a frame to the pixel, and herdr's 32-bit ratios differ by less.
        let sizes = head.firstIndex(of: "content")
            .map { head[($0 + 1)...].map { $0.split(separator: "x").compactMap { Double($0) } } }
        if curve, let sizes, let first = sizes.first,
           sizes.contains(where: { zip($0, first).contains { abs($0 - $1) > 1 } })
        {
            problems
                .append("the content laid out again: \(sizes.map { $0.map { "\(Int($0))" }.joined(separator: "x") })")
        }
        let names = ["left", "top", "right", "bottom"]
        let edges = { (row: [CGFloat]) in [row[1], row[2], row[1] + row[3], row[2] + row[4]] }
        let start = edges(first), end = edges(last)
        var landed: CGFloat?
        for (index, sample) in samples.enumerated() {
            let now = edges(sample)
            for edge in 0 ..< 4 {
                let before = index > 0 ? (edges(samples[index - 1])[edge], samples[index - 1][0]) : nil
                problems += edgeProblems(names[edge], (now[edge], sample[0]), before: before,
                                         way: (start[edge], end[edge]), curve: curve)
            }
            if landed == nil, zip(now, end).allSatisfy({ abs($0 - $1) <= near }) {
                landed = sample[0]
            } else if landed != nil, zip(now, end).contains(where: { abs($0 - $1) > near }) {
                problems.append("moved after landing at \(landed ?? 0) ms: \(sample)")
            }
        }
        if curve, let landed, landed - first[0] > slide + 100 {
            problems.append("landed at \(landed) ms")
        }
        return Array(Set(problems)).sorted().map { "\($0) (\(label))" }
    }

    /// The first sample whole (ms x y w h), each next one as its change.
    private static func samples(_ track: String) -> [[CGFloat]] {
        var samples: [[CGFloat]] = []
        for step in track.split(separator: ";") {
            let numbers = step.split(separator: " ").compactMap { Double($0) }.map { CGFloat($0) }
            if numbers.count == 5 {
                samples.append(samples.last.map { zip($0, numbers).map { $0 + $1 } } ?? numbers)
            }
        }
        return samples
    }

    /// One edge at one sample: between its start and its end, never back, in a step the curve allows.
    private static func edgeProblems(_ name: String, _ sample: (CGFloat, CGFloat), before: (CGFloat, CGFloat)?,
                                     way: (CGFloat, CGFloat), curve: Bool) -> [String]
    {
        let (now, time) = sample, (start, end) = way
        var problems: [String] = []
        if !(min(start, end) - near ... max(start, end) + near).contains(now) {
            problems.append("the \(name) edge at \(now), outside \(start) → \(end) at \(time) ms")
        }
        guard let (last, then) = before else { return problems }
        let step = now - last, sign: CGFloat = end >= start ? 1 : -1
        if step * sign < -near {
            problems.append("the \(name) edge went back \(last) → \(now) at \(time) ms")
        }
        if curve, abs(step) > abs(end - start) * steepest * (time - then + frame) / slide + near {
            problems.append("the \(name) edge jumped \(last) → \(now) at \(time) ms")
        }
        return problems
    }
}
