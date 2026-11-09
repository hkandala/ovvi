import HerdrKit

extension HostStore {
    /// Relaunch with Chat (ui/chat-view#which-panes-have-it): an agent herdr knows, started without Ovvi's flags, in a
    /// session herdr knows, again with the flags in that session, with the chooser's loader meanwhile. A retry names
    /// the agent and its session: it may have ended.
    func enableChat(_ pane: Pane, _ agent: Chooser.Agent? = nil, session: String? = nil) {
        guard let agent = agent ?? Chooser.agents.first(where: { $0.command == pane.agent }),
              let session = session ?? pane.session, chooser(pane.id) == nil else { return }
        let chooser = Chooser()
        chooser.paneID = pane.id
        chooser.terminalID = pane.terminalID
        choosers.append(chooser)
        pane.relaunched = true
        start(agent, chooser, resume: session)
    }

    /// The agent's line with Ovvi's flags (Relaunch with Chat's, made before its agent quit), else its command; with
    /// its extra arguments either way.
    func firstLine(_ agent: Chooser.Agent, _ chooser: Chooser, _ resumed: String?) async -> String {
        if let resumed {
            return resumed
        }
        let arguments = Chooser.arguments(agent.command)
        return await ChatAdapters.launch(agent.command, token: chooser.token, arguments: arguments, on: machine.exec())
            ?? agent.command + arguments
    }

    /// Relaunch with Chat's launch line, made first so a failed run on the machine leaves the agent running, once the
    /// agent quit; nil (with a notice) when either failed, and with no session.
    func restart(_ agent: Chooser.Agent, _ chooser: Chooser, _ session: String?) async -> String? {
        guard let session else { return nil }
        guard let id = chooser.paneID,
              let line = await ChatAdapters.launch(agent.command, token: chooser.token, resume: session,
                                                   arguments: Chooser.arguments(agent.command), on: machine.exec())
        else {
            relaunchFailed("\(agent.name) could not start with chat", agent, chooser, session)
            return nil
        }
        guard await quit(id, agent, chooser) else {
            // A closed pane's chooser is gone: nothing to say.
            if choosers.contains(where: { $0 === chooser }) {
                relaunchFailed("\(agent.name) did not quit", agent, chooser, session)
            }
            return nil
        }
        return line
    }

    /// A resume's launch line: Relaunch with Chat's (`restart`), else a closed session's, with Ovvi's flags; nil (with
    /// a notice) when the value is not one the agent takes or the run on the machine failed.
    func resumed(_ agent: Chooser.Agent, _ chooser: Chooser, resume: String?, closed: String?) async -> String? {
        guard let closed else { return await restart(agent, chooser, resume) }
        guard let line = await ChatAdapters.launch(agent.command, token: chooser.token, resume: closed,
                                                   arguments: Chooser.arguments(agent.command), on: machine.exec())
        else {
            await show(Notice(text: "\(agent.name) could not resume the session"))
            return nil
        }
        return line
    }

    /// Quits the agent as its user would: a turn or a dialog stopped first, the prompt cleared (⌃C, which alone ends
    /// OpenCode with an empty prompt), then its quit command. True once only the shell runs and herdr let go of the
    /// agent, within 30 s, while its chooser is there (its pane did not close). 30 s since an agent runs its exit
    /// hooks first (Claude Code's SessionEnd ones, up to 8 s each in a company setup), and on a busy Mac each herdr
    /// call here can take a second.
    private func quit(_ paneID: String, _ agent: Chooser.Agent, _ chooser: Chooser) async -> Bool {
        guard let client, let adapter = ChatAdapters.adapter(agent.command) else { return false }
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
            if await (try? client.pane(paneID))?.agent == nil {
                return true
            }
        }
        return false
    }

    /// Relaunch with Chat did not end with the chat: why, for 10 s, with Retry (the same agent and session again).
    /// Not awaited: the chooser goes meanwhile. `late`: the agent may still come, and its chat then first.
    func relaunchFailed(_ text: String, _ agent: Chooser.Agent, _ chooser: Chooser, _ session: String,
                        late: Bool = false)
    {
        guard let id = chooser.paneID else { return }
        // Else no chat to open first: a later agent in the pane opens as Settings says.
        if !late {
            pane(id)?.relaunched = false
        }
        let retry: @MainActor @Sendable () -> Void = { [weak self] in
            if let self, let pane = pane(id) {
                enableChat(pane, agent, session: session)
            }
        }
        Task { await show(Notice(text: text, retry: retry), for: .seconds(10)) }
    }

    /// How a relaunch's start ended, said with Retry unless the chat is there (ui/chat-view#relaunch-with-chat).
    func relaunchEnded(_ ended: Started, _ agent: Chooser.Agent, _ chooser: Chooser, _ session: String) {
        let why: String? = switch ended {
        case .agent: chooser.paneID.flatMap(pane)?.adapter == nil ? "started again without chat" : nil
        case .shell: "did not start again"
        case .timeout: "is not back after 10 s"
        case .gone: nil
        }
        if let why {
            relaunchFailed("\(agent.name) \(why)", agent, chooser, session, late: ended == .timeout)
        }
    }
}

/// How a chooser's start ended: herdr reported the agent, the shell came back, 10 s went by, or its pane went.
enum Started {
    case agent, shell, timeout, gone
}
