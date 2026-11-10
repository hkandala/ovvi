import Foundation

public protocol Multiplexer: Sendable {
    func sessions() async throws -> [Session]
    func stopSession() async throws
    /// The session must be stopped.
    func deleteSession() async throws
    func snapshot() async throws -> Snapshot
    /// Called once.
    func updates() async -> AsyncStream<Update>
    func refresh() async
    @discardableResult
    func startServer(within timeout: Duration) async throws -> Bool

    /// Its cwd follows a `cd` that no event reports.
    func pane(_ paneID: String) async throws -> Pane
    func mark(_ paneID: String, shown: Bool) async throws
    func mark(workspace workspaceID: String, open: Bool) async throws
    /// herdr keeps it with the pane, past the app: no time limit.
    func mark(_ paneID: String, chat: String) async throws
    func program(_ paneID: String) async throws -> Program?
    func terminal(_ terminalID: String, cols: Int, rows: Int, observe: Bool, takeover: Bool) async throws
        -> TerminalStream

    func screen(_ paneID: String) async throws -> String
    func recent(_ paneID: String, lines: Int) async throws -> String
    /// The viewport is shared by every client of the pane; 0 is the bottom. The multiplexer clamps it.
    func scroll(_ paneID: String, offsetFromBottom offset: Int) async throws

    /// None of the actions moves the multiplexer's focus, except `swap` (herdr 0.9.5).
    /// `cwd`: where its shell starts; nil, the split pane's folder.
    func split(_ paneID: String, _ direction: SplitNode.Direction, cwd: String?) async throws -> Pane?
    /// Moves herdr's focus to that tab (herdr 0.9.5 has no way around it).
    func swap(_ paneID: String, _ heading: Heading) async throws
    /// herdr refuses panes of two tabs, and moves its focus as the other `swap` does.
    func swap(_ paneID: String, with targetID: String) async throws
    func resize(_ paneID: String, _ heading: Heading, amount: Double) async throws
    /// One split's ratio; `path` from the root, `false` = first child.
    func setRatio(tab tabID: String, path: [Bool], ratio: Double) async throws
    /// A move to another workspace gives the pane a new id. A move into its own tab is refused.
    func move(pane paneID: String, to destination: Destination) async throws -> Pane?
    func rename(pane paneID: String, label: String?) async throws
    func newTab(workspace workspaceID: String, cwd: String, label: String, command: [String]) async throws -> String?
    func newTab(workspace workspaceID: String, cwd: String) async throws -> Pane?
    func newWorkspace(label: String?, cwd: String) async throws -> Pane?
    func rename(workspace workspaceID: String, label: String) async throws
    func move(workspaces workspaceIDs: [String], before workspaceID: String?) async throws
    /// herdr refuses to close a repository's workspace that has linked worktree workspaces without `group`.
    func close(workspace workspaceID: String, group: Bool) async throws
    func close(pane paneID: String) async throws
    func close(tab tabID: String) async throws
    func rename(tab tabID: String, label: String) async throws
    func move(tab tabID: String, to index: Int) async throws
    /// herdr encodes the logical keys (`ctrl+c`) for the program's input modes.
    func sendKeys(_ keys: [String], pane paneID: String) async throws
    func sendInput(_ text: String, keys: [String], pane paneID: String) async throws
    /// herdr refuses it while the agent is blocked.
    func prompt(_ text: String, pane paneID: String) async throws
}

public enum Heading: String, Sendable {
    // herdr's words.
    // swiftlint:disable:next identifier_name
    case left, right, up, down
}

public enum Destination: Sendable {
    /// With herdr's default label (its number) when none.
    case newTab(workspaceID: String, label: String? = nil)
    /// Split right or down beside a pane of the tab, else beside the tab's focused pane (herdr 0.9.5); `ratio` is the
    /// first side's share, else herdr halves the place.
    case tab(String, beside: String? = nil, split: SplitNode.Direction = .right, ratio: Double? = nil)
    /// With herdr's default labels (the pane's folder, the tab's number) when none.
    case newWorkspace(tabLabel: String? = nil)
}

extension HerdrClient: Multiplexer {
    public nonisolated func stopSession() async throws {
        try await session("stop")
    }

    public nonisolated func deleteSession() async throws {
        try await session("delete")
    }

    public nonisolated func screen(_ paneID: String) async throws -> String {
        try await (call("pane.read", ["pane_id": paneID, "source": "visible", "format": "text"]) as Read).read.text
    }

    public nonisolated func recent(_ paneID: String, lines: Int) async throws -> String {
        try await (call("pane.read", ["pane_id": paneID, "source": "recent", "lines": lines,
                                      "format": "text"]) as Read).read.text
    }

    public nonisolated func scroll(_ paneID: String, offsetFromBottom offset: Int) async throws {
        let _: Created = try await call("pane.scroll", ["pane_id": paneID, "offset_from_bottom": offset])
    }

    public nonisolated func split(_ paneID: String, _ direction: SplitNode.Direction, cwd: String?) async throws
        -> Pane?
    {
        var params: [String: any Sendable] = ["target_pane_id": paneID, "direction": direction.rawValue, "focus": false]
        params["cwd"] = cwd
        return try await (call("pane.split", params) as Created).pane
    }

    public nonisolated func swap(_ paneID: String, _ heading: Heading) async throws {
        // A swap with no card that way (`no_neighbor`) is no error: the keys do nothing at an edge.
        let _: Created = try await call("pane.swap", ["pane_id": paneID, "direction": heading.rawValue,
                                                      "focus": false])
    }

    public nonisolated func swap(_ paneID: String, with targetID: String) async throws {
        try await (call("pane.swap", ["source_pane_id": paneID, "target_pane_id": targetID,
                                      "focus": false]) as Swapped).swap.check()
    }

    public nonisolated func resize(_ paneID: String, _ heading: Heading, amount: Double) async throws {
        let _: Created = try await call("pane.resize", ["pane_id": paneID, "direction": heading.rawValue,
                                                        "amount": amount])
    }

    public nonisolated func setRatio(tab tabID: String, path: [Bool], ratio: Double) async throws {
        let _: Created = try await call("layout.set_split_ratio", ["tab_id": tabID, "path": path, "ratio": ratio])
    }

    public nonisolated func move(pane paneID: String, to destination: Destination) async throws -> Pane? {
        let place: [String: any Sendable] = switch destination {
        case let .newTab(workspaceID, label): [
                "type": "new_tab",
                "workspace_id": workspaceID,
                "label": label ?? NSNull(),
            ]
        case let .tab(tabID, target, split, ratio):
            ["type": "tab", "tab_id": tabID, "split": split.rawValue, "target_pane_id": target ?? NSNull(),
             "ratio": ratio ?? NSNull()]
        case let .newWorkspace(tabLabel): ["type": "new_workspace", "tab_label": tabLabel ?? NSNull()]
        }
        let result = try await (call("pane.move", ["pane_id": paneID, "destination": place,
                                                   "focus": false]) as Moved).moveResult
        try result.check()
        return result.pane
    }

    /// The app marks again every 10 s, so a mark goes 30 s after the app that made it stopped.
    private static let markLife = 30000

    public nonisolated func mark(_ paneID: String, shown: Bool) async throws {
        // "remote": the pane is on another machine than this Mac, so its programs' own copy (pbcopy) misses this Mac.
        let tokens: [String: any Sendable] = [Tokens.shown: shown ? (exec.isRemote ? "remote" : "1") : NSNull()]
        let _: Created = try await call("pane.report_metadata", ["pane_id": paneID, "source": "ovvi",
                                                                 "tokens": tokens, "ttl_ms": Self.markLife])
    }

    public nonisolated func mark(_ paneID: String, chat: String) async throws {
        let _: Created = try await call("pane.report_metadata", ["pane_id": paneID, "source": "ovvi-chat",
                                                                 "tokens": [Tokens.chat: chat]])
    }

    public nonisolated func mark(workspace workspaceID: String, open: Bool) async throws {
        let tokens: [String: any Sendable] = [Tokens.open: open ? "\(AgentRequest.version)" : NSNull()]
        let _: Created = try await call("workspace.report_metadata", ["workspace_id": workspaceID, "source": "ovvi",
                                                                      "tokens": tokens, "ttl_ms": Self.markLife])
    }

    public nonisolated func rename(pane paneID: String, label: String?) async throws {
        let _: Created = try await call("pane.rename", ["pane_id": paneID, "label": label ?? NSNull()])
    }

    public nonisolated func newTab(workspace workspaceID: String, cwd: String) async throws -> Pane? {
        try await (call("tab.create", ["workspace_id": workspaceID, "cwd": cwd, "focus": false]) as Created).rootPane
    }

    public nonisolated func newTab(workspace workspaceID: String, cwd: String, label: String,
                                   command: [String]) async throws -> String?
    {
        // Never a `tab_id`: layout.apply would replace that tab and kill its panes.
        let root: [String: any Sendable] = ["type": "pane", "cwd": cwd, "label": label, "command": command]
        return try await (call("layout.apply", ["workspace_id": workspaceID, "focus": false, "root": root])
            as Applied).layout.root.pane_id
    }

    public nonisolated func newWorkspace(label: String?, cwd: String) async throws -> Pane? {
        var params: [String: any Sendable] = ["cwd": cwd, "focus": false]
        params["label"] = label
        return try await (call("workspace.create", params) as Created).rootPane
    }

    public nonisolated func rename(workspace workspaceID: String, label: String) async throws {
        let _: Created = try await call("workspace.rename", ["workspace_id": workspaceID, "label": label])
    }

    public nonisolated func move(workspaces workspaceIDs: [String], before workspaceID: String?) async throws {
        var params: [String: any Sendable] = ["workspace_ids": workspaceIDs]
        params["before_workspace_id"] = workspaceID
        let _: Created = try await call("workspace.move_block", params)
    }

    public nonisolated func close(workspace workspaceID: String, group: Bool) async throws {
        let _: Created = try await call("workspace.close", ["workspace_id": workspaceID, "close_group": group])
    }

    public nonisolated func close(pane paneID: String) async throws {
        let _: Created = try await call("pane.close", ["pane_id": paneID])
    }

    public nonisolated func close(tab tabID: String) async throws {
        let _: Created = try await call("tab.close", ["tab_id": tabID])
    }

    public nonisolated func rename(tab tabID: String, label: String) async throws {
        let _: Created = try await call("tab.rename", ["tab_id": tabID, "label": label])
    }

    public nonisolated func move(tab tabID: String, to index: Int) async throws {
        let _: Created = try await call("tab.move", ["tab_id": tabID, "insert_index": index])
    }

    public nonisolated func sendKeys(_ keys: [String], pane paneID: String) async throws {
        let _: Created = try await call("pane.send_keys", ["pane_id": paneID, "keys": keys])
    }

    public nonisolated func sendInput(_ text: String, keys: [String], pane paneID: String) async throws {
        let _: Created = try await call("pane.send_input", ["pane_id": paneID, "text": text, "keys": keys])
    }

    public nonisolated func prompt(_ text: String, pane paneID: String) async throws {
        let _: Created = try await call("agent.prompt", ["target": paneID, "text": text])
    }
}
