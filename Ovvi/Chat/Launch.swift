import HerdrKit

/// An agent Ovvi typed with its chat flags (ui/chat-view#which-panes-have-it). Its processes carry the launch's marker
/// in their arguments, unless they dropped them: a Node CLI that sets its process title (npm's pi) overwrites its
/// arguments on macOS, and herdr then lists none. Bound to the agent's processes when they first show, the launch
/// marks them instead; an agent started again by hand in the terminal is not one of them.
struct Launch {
    let command: String
    let token: String
    var pids: Set<Int> = []
}

extension HostStore.Pane {
    /// The chat adapter of what it runs: its processes' marker, else Ovvi's launch's while those processes run.
    var adapter: (any ChatAdapter)? {
        if let found = ChatAdapters.recognize(program) {
            return found
        }
        guard let launch, let foreground = program?.foreground,
              foreground.contains(where: { launch.pids.contains($0.pid) }) else { return nil }
        return ChatAdapters.adapter(launch.command)?.init(token: launch.token, pids: launch.pids.sorted())
    }

    /// The launch's processes, from the first answer that has the agent: those named as its command.
    func bind(_ program: Program?) {
        guard var launch, launch.pids.isEmpty else { return }
        launch.pids = Set(program?.foreground.filter { $0.runs(launch.command) }.map(\.pid) ?? [])
        if !launch.pids.isEmpty {
            self.launch = launch
        }
    }
}

extension Program.Foreground {
    /// The agent `command`, by its name (`claude.exe` from npm), its `argv[0]` (a process title, a path) or its
    /// first argument.
    func runs(_ command: String) -> Bool {
        let base = { (path: String?) -> String? in path?.split(separator: "/").last.map(String.init) }
        let names: [String?] = [name, base(argv0), base(argv.first)]
        return names.contains { $0 == command || $0 == command + ".exe" }
    }
}

extension HostStore {
    /// Its marker or its launch's processes before the loader goes, so a chat pane shows its chat at once: asked
    /// again every 0.5 s, 10 s at most, while neither shows (an agent whose process comes after its status).
    func settle(_ paneID: String) async {
        await askProgram(paneID, soon: true)
        for _ in 0 ..< 20 {
            guard let pane = pane(paneID), pane.launch?.pids.isEmpty == true, pane.adapter == nil else { return }
            try? await Task.sleep(for: .seconds(0.5))
            await askProgram(paneID, soon: true)
        }
    }

    /// As the line goes in, and again once herdr reports the agent (a new tab's pane can be missing from the
    /// snapshot as the line goes in): the launch, when the line has its marker, and the chat first when Settings ▸
    /// Agents says so, as after Relaunch with Chat. No card makes the chat while the chooser is there.
    func launched(_ paneID: String, _ agent: Chooser.Agent, _ chooser: Chooser, line: String?) {
        guard let pane = pane(paneID) else { return }
        if line?.contains(chooser.token) == true, pane.launch?.token != chooser.token {
            pane.launch = Launch(command: agent.command, token: chooser.token)
        }
        if AppSettings().agentView == .chat {
            pane.relaunched = true
        }
    }
}
