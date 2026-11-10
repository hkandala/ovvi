import AppKit
import HerdrKit

extension Page {
    /// Claude Code refuses a session from another folder; pi keeps its folder in its file, so it resumes in the home
    /// folder. Once: a second click ahead of herdr's report of the session would start a second agent on it.
    func resume(_ session: ClosedSession, beside: Bool) {
        guard let agent = Chooser.agent(session.agent),
              store.resuming.insert(session.value).inserted else { return }
        Task {
            if let problem = await resumeNow(session, agent, beside: beside) {
                store.resuming.remove(session.value)
                store.show(Notice(text: problem))
            }
        }
    }

    private func resumeNow(_ session: ClosedSession, _ agent: Chooser.Agent, beside: Bool) async -> String? {
        if let installed = terminals.pages?.agents, !installed.contains(agent.command) {
            return "\(agent.name) is not on \(store.machine.name)"
        }
        // herdr starts a pane in the home folder when its folder is gone.
        let exec = await store.machine.exec()
        guard let found = try? await exec.output(["sh", "-c", #"test -d "$1" && echo yes"#, "sh", session.folder])
            .contains("yes") else { return "\(store.machine.name) did not answer" }
        guard found || agent.adapter.resumesAnywhere else {
            return "\(MachinePath.short(session.folder, remote: store.machine.isRemote)) is gone"
        }
        let cwd = found ? session.folder : "~", card = beside ? keyboardPane : nil
        guard let workspace = card.flatMap({ store.workspace(of: $0.tabID) }) ?? workspace(holding: cwd) else {
            guard let chooser = await newWorkspace(cwd: cwd, fixed: false).flatMap({ store.chooser($0.id) }) else {
                store.resuming.remove(session.value)
                return nil
            }
            store.start(agent, chooser, closed: session.value)
            return nil
        }
        let made = await store.write { client in
            let spot = if let card {
                PanePlace.split(tab: card.tabID, pane: card.id, .right)
            } else {
                PanePlace.tab(after: selectedTabIDs[workspace.id] ?? workspace.activeTabID)
            }
            let pane = try await store.newPane(client, in: workspace.id, cwd: cwd, label: nil, spot)
            store.choose(pane, starting: agent, closed: session.value)
            follow(pane, pane.terminalID)
        }
        if !made {
            store.resuming.remove(session.value)
        }
        return nil
    }

    /// A folder one or two levels deep (`/`, a home folder) holds only itself: every session is under it.
    private func workspace(holding folder: String) -> HostStore.Workspace? {
        store.workspaces.compactMap { workspace in store.root(of: workspace).map { (workspace, $0) } }
            .filter { $0.1 == folder || $0.1.split(separator: "/").count > 2 && folder.hasPrefix($0.1 + "/") }
            .max { $0.1.count < $1.1.count }?.0
    }
}

extension HostStore {
    func root(of workspace: Workspace) -> String? {
        workspace.worktree?.checkoutPath ?? workspace.tabs.first.flatMap { panes(in: $0.id).first?.cwd }
    }
}

extension Page {
    func resume(_ session: ClosedSession) {
        resume(session, beside: NSEvent.modifierFlags.contains(.option))
    }

    var liveSessions: Set<String> {
        let stores = HostStore.all.filter { $0.machine.id == store.machine.id }
        return Set(stores.flatMap(\.agentPanes).compactMap(\.session)).union(stores.flatMap(\.resuming))
    }
}
