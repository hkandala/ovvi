import HerdrKit

/// An agent Ovvi typed with its chat flags (ui/chat-view#which-panes-have-it). Its processes carry the launch's marker
/// in their arguments, unless they dropped them: a Node CLI that sets its process title (npm's pi) overwrites its
/// arguments on macOS, and herdr then lists none. Bound to the agent's processes when they first show, the launch
/// marks them instead; an agent started again by hand in the terminal is not one of them.
struct Launch {
    let command: String
    let token: String
    /// The pane's asks when the line went in: an older ask's answer can be the agent before.
    let after: Int
    var pids: Set<Int> = []
}

extension HostStore {
    /// The chat adapter of what the pane runs: its processes' marker, else Ovvi's launch's while those processes run.
    func adapter(_ pane: Pane) -> (any ChatAdapter)? {
        if let found = ChatAdapters.recognize(pane.program) {
            return found
        }
        guard let launch = pane.terminalID.flatMap({ launches[$0] }), let foreground = pane.program?.foreground,
              foreground.contains(where: { launch.pids.contains($0.pid) }) else { return nil }
        return ChatAdapters.adapter(launch.command)?.init(token: launch.token, pids: launch.pids.sorted())
    }

    /// Binds the terminal's launch to its agent's processes: the first newer answer with processes named as its
    /// command.
    func bind(_ pane: Pane, _ program: Program?, ask: Int) {
        guard let terminal = pane.terminalID, var launch = launches[terminal], launch.pids.isEmpty,
              ask > launch.after else { return }
        launch.pids = Set(program?.foreground.filter { $0.runs(launch.command) }.map(\.pid) ?? [])
        if !launch.pids.isEmpty {
            launches[terminal] = launch
        }
    }

    /// Its marker or its launch's processes before the loader goes, so a chat pane shows its chat at once: asked
    /// again every 0.5 s, 10 s at most, while neither shows (an agent whose process comes after its status).
    func settle(_ paneID: String) async {
        await askProgram(paneID, soon: true)
        for _ in 0 ..< 20 {
            guard let pane = pane(paneID), let terminal = pane.terminalID, launches[terminal]?.pids.isEmpty == true,
                  adapter(pane) == nil else { return }
            try? await Task.sleep(for: .seconds(0.5))
            await askProgram(paneID, soon: true)
        }
    }

    /// As the line goes in, and again once herdr reports the agent (a new tab's pane can be missing from the
    /// snapshot as the line goes in): the launch, when the line has its marker (none for the bare command), and the
    /// chat first when Settings ▸ Agents says so, as after Relaunch with Chat. No card makes the chat while the chooser
    /// is there.
    func launched(_ paneID: String, _ agent: Chooser.Agent, _ chooser: Chooser, line: String?) {
        guard let pane = pane(paneID), let terminal = pane.terminalID else { return }
        if line?.contains(chooser.token) != true {
            launches[terminal] = nil
        } else if launches[terminal]?.token != chooser.token {
            launches[terminal] = Launch(command: agent.command, token: chooser.token, after: pane.asks)
        }
        if AppSettings().agentView == .chat {
            pane.relaunched = true
        }
    }

    /// A start that ended without its agent's processes leaves no launch: an agent started by hand later is not it.
    /// ponytail: after a 10 s timeout it stays and binds the next agent named so; bound it in time if that shows.
    func unlaunch(_ chooser: Chooser, unless ended: Started) {
        guard ended != .timeout, let terminal = chooser.paneID.flatMap(pane)?.terminalID,
              launches[terminal]?.token == chooser.token, launches[terminal]?.pids.isEmpty == true else { return }
        launches[terminal] = nil
    }
}

extension Program.Foreground {
    /// The agent `command`, by its name (`claude.exe` from npm) or its `argv[0]` (herdr's `argv0`, a process title,
    /// else the first of `argv`), as a path's last part.
    func runs(_ command: String) -> Bool {
        let base = { (path: String?) -> String? in path?.split(separator: "/").last.map(String.init) }
        let names: [String?] = [name, base(argv0), base(argv.first)]
        return names.contains { $0 == command || $0 == command + ".exe" }
    }
}
