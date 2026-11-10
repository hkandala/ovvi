import HerdrKit

extension HostStore {
    /// A retry names the agent and its session: it may have ended.
    func enableChat(_ pane: Pane, _ agent: Chooser.Agent? = nil, session: String? = nil) {
        guard let agent = agent ?? Chooser.agent(pane.agent),
              let session = session ?? pane.session, chooser(pane.id) == nil else { return }
        let chooser = Chooser()
        chooser.paneID = pane.id
        chooser.terminalID = pane.terminalID
        chooser.opensChat = true
        choosers.append(chooser)
        start(agent, chooser, resume: session)
    }

    func firstLine(_ agent: Chooser.Agent, _ chooser: Chooser, _ resumed: String?) async -> String {
        if let resumed {
            return resumed
        }
        return await ChatAdapters.launch(agent.command, token: chooser.token, on: machine.exec())
            ?? agent.command + Chooser.arguments(agent.command)
    }

    /// The launch line is made ahead of the quit, so a failed run on the machine leaves the agent running.
    func restart(_ agent: Chooser.Agent, _ chooser: Chooser, _ session: String?) async -> String? {
        guard let session else { return nil }
        guard let id = chooser.paneID,
              let line = await ChatAdapters.launch(agent.command, token: chooser.token, resume: session,
                                                   on: machine.exec())
        else {
            relaunchFailed("\(agent.name) could not start with chat", agent, chooser, session)
            return nil
        }
        guard await quit(id, agent, chooser) else {
            if choosers.contains(where: { $0 === chooser }) {
                relaunchFailed("\(agent.name) did not quit", agent, chooser, session)
            }
            return nil
        }
        return line
    }

    func resumed(_ agent: Chooser.Agent, _ chooser: Chooser, resume: String?, closed: String?) async -> String? {
        guard let closed else { return await restart(agent, chooser, resume) }
        guard let line = await ChatAdapters.launch(agent.command, token: chooser.token, resume: closed,
                                                   on: machine.exec())
        else {
            show(Notice(text: "\(agent.name) could not resume the session"))
            return nil
        }
        return line
    }

    /// ⌃C clears the prompt; alone it ends OpenCode with an empty prompt. 30 s: an agent runs its exit hooks first
    /// (Claude Code's SessionEnd ones, up to 8 s each in a company setup), and on a busy Mac each herdr call here can
    /// take a second.
    private func quit(_ paneID: String, _ agent: Chooser.Agent, _ chooser: Chooser) async -> Bool {
        guard let client else { return false }
        let adapter = agent.adapter
        if pane(paneID)?.state.map({ $0 == .working || $0 == .needsYou }) == true {
            try? await client.sendKeys(adapter.stopKeys, pane: paneID)
            try? await Task.sleep(for: .seconds(1))
        }
        try? await client.sendKeys(["ctrl+c"], pane: paneID)
        var typed = false
        let clock = ContinuousClock(), begun = clock.now
        while clock.now - begun < .seconds(30), choosers.contains(where: { $0 === chooser }) {
            // OpenCode stops its server first: the quit command would land in the shell.
            try? await Task.sleep(for: .seconds(typed ? 0.3 : 2))
            guard await (try? client.program(paneID))?.isShell == true else {
                if !typed {
                    typed = true
                    try? await client.sendInput(adapter.quit, keys: ["enter"], pane: paneID)
                }
                continue
            }
            // The agent has gone: no quit command into the shell, where a prompt's own program can run.
            typed = true
            if await (try? client.pane(paneID))?.agent == nil {
                return true
            }
        }
        return false
    }

    /// Not awaited: the chooser goes meanwhile.
    func relaunchFailed(_ text: String, _ agent: Chooser.Agent, _ chooser: Chooser, _ session: String) {
        guard let terminal = chooser.terminalID ?? chooser.paneID.flatMap(pane)?.terminalID else { return }
        // By terminal: a pane id can name another pane after a move.
        let retry: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, let pane = terminalPane(terminal),
                  pane.agent == nil || pane.agent == agent.command, adapter(pane) == nil else { return }
            enableChat(pane, agent, session: session)
        }
        show(Notice(text: text, retry: retry), for: .seconds(10))
    }

    func relaunchEnded(_ ended: Started, _ agent: Chooser.Agent, _ chooser: Chooser, _ session: String) {
        let why: String? = switch ended {
        case .agent: chooser.paneID.flatMap(pane).flatMap(adapter) == nil ? "started again without chat" : nil
        case .shell: "did not start again"
        case .timeout: "is not back after 10 s"
        case .gone: nil
        }
        if let why {
            relaunchFailed("\(agent.name) \(why)", agent, chooser, session)
        }
    }
}

enum Started {
    case agent, shell, timeout, gone
}
