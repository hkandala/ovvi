import Synchronization
import XCTest

extension OvviUITests {
    /// `recent_unwrapped` joins the lines the pane's width wrapped (CI's panes and prompts vary).
    func read(_ pane: String, in session: String? = nil, _ source: String = "visible") async throws -> String {
        let read = try await Self.call(session ?? one, "pane.read", ["pane_id": pane, "source": source])["read"]
        return try field((read as? [String: Any])?["text"], "pane.read's text")
    }

    func pane(_ id: String, in session: String? = nil) async throws -> [String: Any] {
        try await field(Self.call(session ?? one, "pane.get", ["pane_id": id])["pane"], "pane \(id)")
    }

    func paneLabel(_ pane: String) async throws -> String {
        try await self.pane(pane)["label"] as? String ?? ""
    }

    func tabOf(_ pane: String, in session: String? = nil) async throws -> String {
        try await field(self.pane(pane, in: session)["tab_id"], "\(pane)'s tab")
    }

    func terminalID(_ pane: String, in session: String? = nil) async throws -> String {
        try await field(self.pane(pane, in: session)["terminal_id"], "\(pane)'s terminal")
    }

    func send(_ text: String, to pane: String, in session: String? = nil) async throws {
        try await Self.call(session ?? one, "pane.send_text", ["pane_id": pane, "text": text])
    }

    func sendAfter(_ text: String, to pane: String) {
        addTeardownBlock { [one] in _ = try? await Self.call(one, "pane.send_text", ["pane_id": pane, "text": text]) }
    }

    struct Failed: Error, CustomStringConvertible {
        let description: String
    }

    func field<T>(_ value: Any?, _ what: String) throws -> T {
        guard let value = value as? T else { throw Failed(description: "no \(what)") }
        return value
    }

    func id(_ reply: [String: Any], _ key: String) throws -> String {
        let name = key.split(separator: "_").last ?? ""
        return try field((reply[key] as? [String: Any])?["\(name)_id"], "\(key) id")
    }

    /// herdr sends no event for a rename: the metadata report makes the app read the snapshot (the app reads no token
    /// of this one).
    func relabel(_ pane: String, _ label: String, in session: String? = nil) async throws {
        try await Self.call(session ?? one, "pane.rename", ["pane_id": pane, "label": label])
        try await Self.call(session ?? one, "pane.report_metadata", ["pane_id": pane, "source": "ovvi-e2e-relabel",
                                                                     "tokens": ["relabel": "1"], "ttl_ms": 1000])
    }

    func closeAfter(_ kind: String, _ id: String, in session: String? = nil) {
        let session = session ?? one
        addTeardownBlock { _ = try? await Self.call(session, "\(kind).close", ["\(kind)_id": id]) }
    }

    func closeNew(_ kind: String, besides before: [String]) {
        addTeardownBlock { [one] in
            for id in try await Self.ids(kind, in: one) where !before.contains(id) {
                _ = try? await Self.call(one, "\(kind).close", ["\(kind)_id": id])
            }
        }
    }

    /// herdr's ids are `w<n>:t<m>`.
    func workspace(of tab: String) -> String {
        String(tab.prefix { $0 != ":" })
    }

    @discardableResult
    func split(_ pane: String, _ direction: String = "right", in session: String? = nil) async throws -> String {
        try await id(
            Self.call(session ?? one, "pane.split", ["target_pane_id": pane, "direction": direction, "cwd": "/tmp",
                                                     "focus": false]),
            "pane",
        )
    }

    func createTab(in workspace: String, label: String? = nil,
                   session: String? = nil) async throws -> (tab: String, pane: String)
    {
        var params: [String: Any] = ["workspace_id": workspace, "cwd": "/tmp", "focus": false]
        params["label"] = label
        let created = try await Self.call(session ?? one, "tab.create", params)
        return try (id(created, "tab"), id(created, "root_pane"))
    }

    func createWorkspace(_ label: String, cwd: String = "/tmp") async throws -> (tab: String, pane: String) {
        let created = try await Self.call(one, "workspace.create", ["label": label, "cwd": cwd, "focus": false])
        try closeAfter("workspace", id(created, "workspace"))
        return try (id(created, "tab"), id(created, "root_pane"))
    }

    func pane(of tab: String) async throws -> String {
        try await field((snapshot()["panes"] as? [[String: Any]])?.first { $0["tab_id"] as? String == tab }?["pane_id"],
                        "a pane of \(tab)")
    }

    func sidePane(in tab: String, besides panes: [String]) async throws -> String {
        try await poll("a pane beside the card") { () async throws -> String? in
            try await (snapshot()["panes"] as? [[String: Any]] ?? []).first {
                $0["tab_id"] as? String == tab && !panes.contains($0["pane_id"] as? String ?? "")
            }?["pane_id"] as? String
        }
    }

    func newCard(_ label: String, cwd: String = "/tmp", show shown: Bool = true) async throws
        -> (tab: String, pane: String)
    {
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": cwd, "label": label, "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        closeAfter("tab", tab)
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        if shown {
            try await show(tab)
        }
        return (tab, pane)
    }

    /// A shell's startup runs programs (`path_helper`, nvm's `ls`), which would make a close ask.
    func settle(_ tabs: [String]) async throws {
        for pane in try await snapshot()["panes"] as? [[String: Any]] ?? []
            where tabs.contains(pane["tab_id"] as? String ?? "")
        {
            try await waitForPrompt(field(pane["pane_id"], "pane id"))
        }
    }

    func runSleep(_ pane: String) async throws {
        try await waitForPrompt(pane)
        try await send("sleep 100\r", to: pane)
        try await expect("sleep in \(pane)") { try await foreground(pane).contains("sleep") }
    }

    func foreground(_ pane: String) async throws -> [String] {
        let info = try await Self.call(one, "pane.process_info", ["pane_id": pane])["process_info"]
        let processes = (info as? [String: Any])?["foreground_processes"] as? [[String: Any]] ?? []
        return processes.compactMap { $0["name"] as? String }
    }

    func answer(_ session: String) async throws -> [String: Any]? {
        do {
            return try await Self.snapshot(session)
        } catch is Failed {
            return nil
        }
    }

    func snapshot() async throws -> [String: Any] {
        try await Self.snapshot(one)
    }

    @discardableResult
    nonisolated static func snapshot(_ session: String) async throws -> [String: Any] {
        let snapshot = try await call(session, "session.snapshot", [:])["snapshot"]
        guard let snapshot = snapshot as? [String: Any] else { throw Failed(description: "no snapshot of \(session)") }
        return snapshot
    }

    @discardableResult
    func running(_ session: String, start: Bool = true) async throws -> [String: Any] {
        if start, try await answer(session) == nil {
            try await Self.post("\(session)/start")
        }
        let snapshot = try await poll("\(session) to answer") { try await answer(session) }
        guard start, (snapshot["workspaces"] as? [Any] ?? []).isEmpty else { return snapshot }
        try await Self.call(session, "workspace.create", ["label": "five", "cwd": "/tmp", "focus": false])
        return try await Self.snapshot(session)
    }

    /// Tests close and make five's workspaces, so its ids change from run to run.
    func shown(_ snapshot: [String: Any]) throws -> (workspace: String, pane: String) {
        let workspace: [String: Any] = try field((snapshot["workspaces"] as? [[String: Any]])?.first, "workspace")
        let tab: String = try field(workspace["active_tab_id"], "active tab")
        let panes = snapshot["panes"] as? [[String: Any]] ?? []
        return try (field(workspace["workspace_id"], "workspace id"),
                    field(panes.first { $0["tab_id"] as? String == tab }?["pane_id"], "pane of \(tab)"))
    }

    func tabIDs(in session: String? = nil) async throws -> [String] {
        try await Self.ids("tab", in: session ?? one)
    }

    /// Off the main actor for async teardown blocks: after a failure, one on the main actor waits for it until the
    /// 2-minute allowance runs out.
    nonisolated static func ids(_ kind: String, in session: String) async throws -> [String] {
        try await (snapshot(session)[kind + "s"] as? [[String: Any]] ?? []).compactMap { $0[kind + "_id"] as? String }
    }

    func newTabID(after before: [String], in session: String? = nil) async throws -> String {
        try await poll("a new tab in herdr") { () async throws -> String? in
            try await tabIDs(in: session).first { !before.contains($0) }
        }
    }

    func order(of tab: String) async throws -> Int? {
        try await (Self.call(one, "tab.list", ["workspace_id": "w2"])["tabs"] as? [[String: Any]] ?? [])
            .compactMap { $0["tab_id"] as? String }.firstIndex(of: tab)
    }

    /// XCUITest looks too seldom to see a one-snapshot jump.
    func expectBeside(_ tab: String, _ card: String) async throws {
        XCTAssertTrue(element("tab.\(tab)").exists(within: 5))
        let after = element("tab.\(card)").frame.maxX, start = element("tab.\(tab)").frame.minX
        let capsules = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", #"tab\.[^.]+"#))
            .allElementsBoundByIndex.map(\.frame.midX)
        XCTAssertTrue(start > after && !capsules.contains { $0 > after && $0 < start }, "\(tab) is not beside \(card)")
        let index = try await order(of: card)
        try await expect("\(tab) right after \(card) in herdr") {
            try await self.order(of: tab) == index.map { $0 + 1 }
        }
    }

    /// By its key: a click misses a tab past the tab bar's end on CI's screen.
    func show(_ tab: String) async throws {
        let found = try await order(of: tab)
        let index = try XCTUnwrap(found)
        // herdr's new tab reaches the app with the next snapshot.
        XCTAssertTrue(element("tab.\(tab)").exists(within: 5))
        app.typeKey("\(index + 1)", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))
    }

    /// setUp's app goes first, as it saves its window too.
    func forgetWindows() async throws {
        app.terminate()
        _ = try await Self.post("\(one)/forget-windows")
    }

    func hasSSH() async throws -> Bool {
        try await String(decoding: Self.post("\(one)/ssh-connections"), as: UTF8.self) != "none"
    }

    /// Skips where the pane's shell would start this Mac's own claude: no claude, or the stand-in (CI's, which only
    /// exits), goes on.
    func skipIfThisMacHasClaude(_ pane: String, _ which: String) async throws {
        try await send("case \"$(command -v claude)\" in ''|*/Fixtures/agents/*) echo claude-$((6*7))-safe;; "
            + "*) echo claude-$((6*7))-real;; esac\r", to: pane)
        try await waitFor(pane) { $0.contains("\nclaude-42-") }
        if try await read(pane).contains("\nclaude-42-real") {
            throw XCTSkip("this Mac has claude, which \(which)")
        }
    }

    func skipWithoutSSH() async throws {
        if try await !hasSSH() {
            throw XCTSkip("no sshd on 127.0.0.1:2222 (scripts/ci-sshd.sh, CI only)")
        }
    }

    func keep(_ text: String, as name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func runs(_ session: String) async throws -> [String] {
        try await String(decoding: Self.post("\(session)/children"), as: UTF8.self).split(separator: "\n")
            .map(String.init)
    }

    func streams(_ session: String) async throws -> [String] {
        try await runs(session).filter { $0.contains("terminal session") }
    }

    @discardableResult
    nonisolated static func call(_ session: String, _ method: String,
                                 _ params: [String: Any]) async throws -> [String: Any]
    {
        let body = try JSONSerialization.data(withJSONObject: ["id": "1", "method": method, "params": params])
        let data = try await post(session, body + Data("\n".utf8))
        let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = reply?["result"] as? [String: Any] else {
            throw Failed(description: "\(method): \(String(decoding: data, as: UTF8.self))")
        }
        return result
    }

    /// A failed test keeps the plugin pages' console and errors in its result: CI's recordings show no web content.
    /// Sync, for tearDown: URLSession answers on a queue of its own, never the main thread.
    nonisolated func keepPluginConsole() {
        let env = ProcessInfo.processInfo.environment
        let path = "\(env["OVVI_HELPER"] ?? "")/\(env["OVVI_SESSION"] ?? "")/plugin-logs"
        guard testRun?.hasSucceeded == false, let url = URL(string: path) else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = Data("\(started.withLock(\.self))".utf8)
        let log = Mutex(""), done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            log.withLock { $0 = data.map { String(decoding: $0, as: UTF8.self) } ?? "" }
            done.signal()
        }.resume()
        done.wait()
        let text = log.withLock(\.self), attachment = XCTAttachment(string: text.isEmpty ? "(none)" : text)
        attachment.name = "plugin console"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    nonisolated static func post(_ path: String, _ body: Data = Data()) async throws -> Data {
        let helper = ProcessInfo.processInfo.environment["OVVI_HELPER"] ?? "run through make e2e"
        guard let url = URL(string: "\(helper)/\(path)") else { throw Failed(description: "no URL \(helper)") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        // The stress test's session takes up to a few minutes to fill on CI.
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failed(description: "\(path): \(String(decoding: data, as: UTF8.self))")
        }
        return data
    }
}
