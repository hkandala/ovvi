import HerdrKit

enum AgentPlace {
    case beside(PaneTarget, down: Bool)
    case tab(float: Bool)
    case replace(PaneTarget)
}

extension AgentCall {
    mutating func place() async throws -> AgentPlace {
        let down = flag("--down"), tab = flag("--tab"), float = flag("--float")
        let beside = try value("--beside"), replace = try value("--replace")
        guard [beside != nil || down, tab, float, replace != nil].count(where: \.self) <= 1 else {
            throw AgentError.usage("give one place: --beside <pane> [--down], --tab, --float or --replace <pane>")
        }
        if let replace {
            return try await .replace(target(replace))
        }
        return tab || float ? .tab(float: float) : try await .beside(target(beside ?? pane), down: down)
    }

    func newPane(_ place: AgentPlace, label: PaneLabel? = nil) async throws -> (store: HostStore, pane: String) {
        let near: PaneTarget, split: SplitNode.Direction?
        switch place {
        case let .beside(target, down): (near, split) = (target, down ? .down : .right)
        case .tab: (near, split) = (asking, nil)
        case .replace: throw AgentError.usage("--replace makes no pane")
        }
        let found = try found(near), store = found.0
        if case .tab(float: true) = place, store.windows.isEmpty {
            throw AgentError.noWindow(store.session)
        }
        let made = try await store.request { client in
            // Its tab after the queued writes: they can move panes.
            guard let card = store.pane(found.1.id), let workspace = store.workspace(of: card.tabID)
            else { throw AgentError(code: "pane_not_found", message: "pane \(near.id) is in no tab") }
            let spot = split.map { PanePlace.split(tab: card.tabID, pane: card.id, $0) } ?? .tab(after: card.tabID)
            return try await store.newPane(client, in: workspace.id, cwd: cwd, label: label, spot)
        }
        // A snapshot between the new tab and the move has it in a temporary tab.
        try await settle { store.pane(made.id)?.tabID == made.tabID }
        if case .tab(float: true) = place {
            let call = AgentCall(store: store, pane: pane, cwd: cwd, id: id, args: [])
            do {
                _ = try await call.float(call.target(made.id), onTop: false)
            } catch {
                try? await store.request { try await $0.close(pane: made.id) }
                throw error
            }
        }
        return (store, made.id)
    }
}

func settle(for limit: Duration = .seconds(5), _ done: () -> Bool) async throws {
    let end = ContinuousClock.now + limit
    while !done(), end > .now {
        try await Task.sleep(for: .milliseconds(50))
    }
}
