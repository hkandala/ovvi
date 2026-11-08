import HerdrKit
import SwiftUI

/// The sidebar's Archived Sessions (ui/window#archived-sessions): the sessions of Claude Code, Codex, Pi and OpenCode
/// on the page's machine that no pane runs, from the agents' own stores, newest first. Read each time it opens; the
/// next page of an agent as the list's end scrolls into view. A menu in its header shows one agent.
struct ArchivedShelf: View {
    let page: Page
    /// The footer's filter: by title and folder.
    let filter: String
    /// The agent the menu shows ("" for all), kept across relaunches.
    @AppStorage("archivedAgent", store: .agents) private var agent = ""
    @AppStorage(Page.openShelves, store: .agents) private var opened = ""
    @State private var list = ClosedList()
    @State private var reading: Set<String> = []
    @State private var failed: Set<String> = []
    @State private var slow = false
    /// Each read anew (an open, Retry); an older one's pages land nowhere.
    @State private var generation = 0
    @State private var attempt = 0

    /// UI tests' stores (`-archivedHome`), never the user's; the agents' session titles too.
    static let home = UserDefaults.standard.string(forKey: "archivedHome")

    var body: some View {
        let open = opened.split(separator: "\n").contains { $0 == page.shelfKey(Self.label) }
        let shown = agent.isEmpty ? Chooser.agents.map(\.command) : [agent]
        let rows = open ? rows(shown) : []
        let next = list.next(of: shown).filter { !failed.contains($0) }
        Shelf(label: Self.label, page: page) {
            menu
        } content: {
            ForEach(rows) { row($0) }
            if !next.isEmpty {
                // The list's end: anew after each page, so it reads on while it stays in view (a short filtered list,
                // a page with nothing to show).
                Color.clear.frame(height: 1).id(list.agents.values.map(\.looked).reduce(0, +))
                    .onAppear { Task { await read(next) } }
            }
            if rows.isEmpty || !failed.isDisjoint(with: shown) || problem(shown) != nil {
                status(shown, more: !next.isEmpty).frame(maxWidth: .infinity)
            }
        }
        .task(id: [open ? 1 : 0, attempt]) {
            (list, reading, failed, slow, generation) = (ClosedList(), [], [], false, generation + 1)
            guard open else { return }
            async let pages: Void = read(Chooser.agents.map(\.command))
            // No line while a page reads fast (This Mac).
            if await (try? Task.sleep(for: .seconds(0.3))) != nil {
                slow = true
            }
            await pages
        }
    }

    private var menu: some View {
        Menu {
            Picker("Agents", selection: $agent) {
                Text("All Agents").tag("")
                Divider()
                ForEach(Chooser.agents, id: \.command) { Text($0.name).tag($0.command) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // Filled while it shows one agent.
            Image(systemName: agent.isEmpty ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show Agent")
        .accessibilityLabel("Show Agent")
        .accessibilityValue(agent.isEmpty ? "All Agents" : Chooser.name(agent))
        .accessibilityIdentifier("agents.archived.filter")
    }

    static let label = "Archived Sessions"

    /// The sessions shown: none a live pane runs (on any page of the machine), none resuming.
    private func rows(_ shown: [String]) -> [ClosedSession] {
        let live = page.liveSessions.union(page.store.resuming)
        return list.sessions(of: shown).filter { session in
            !live.contains(session.value) && (session.title.matches(filter) || session.folder.matches(filter))
        }
    }

    private func problem(_ shown: [String]) -> String? {
        shown.lazy.compactMap { agent in
            list.agents[agent]?.problem.map { "\(Chooser.name(agent)) \($0) on \(page.store.machine.name)." }
        }.first
    }

    /// Why there is no row, or what is missing: the app's empty state and loader (ui/states), compact.
    @ViewBuilder private func status(_ shown: [String], more: Bool) -> some View {
        let machine = page.store.machine.name
        if !failed.isDisjoint(with: shown) {
            EmptyState(
                symbol: "exclamationmark.triangle",
                title: "Could not read \(machine)'s sessions.",
                compact: true,
                id: "agents.archived.status",
            ) {
                Button("Retry") { attempt += 1 }.accessibilityIdentifier("agents.archived.retry")
            }
        } else if let problem = problem(shown) {
            EmptyState(symbol: "exclamationmark.triangle", title: problem, compact: true, id: "agents.archived.status")
        } else if more || !reading.isDisjoint(with: shown) {
            if slow {
                Loader(text: "Reading sessions…", id: "agents.archived.status").padding(12)
            }
        } else if !filter.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "No matching sessions.", compact: true,
                       id: "agents.archived.status")
        } else {
            EmptyState(symbol: "archivebox", title: agent.isEmpty ? "No closed sessions on \(machine)."
                : "No \(Chooser.name(agent)) sessions.", compact: true, id: "agents.archived.status")
        }
    }

    /// A click resumes it in a new tab of the workspace for its folder; ⌥-click beside the keyboard card.
    private func row(_ session: ClosedSession) -> some View {
        // pi's file by its name.
        let id = "agents.archived.\(session.agent).\((session.value as NSString).lastPathComponent)"
        return AgentRow(icon: session.agent, title: session.title, line2: page.short(session.folder), id: id,
                        action: { page.resume(session) },
                        hover: {
                            IconButton(symbol: "arrow.uturn.backward", help: "Resume", size: 18) {
                                page.resume(session)
                            }
                            .accessibilityIdentifier(id + ".resume")
                        },
                        trailing: { AgeText(date: session.date) })
            .contextMenu {
                Button("Resume") { page.resume(session, beside: false) }
                Button("Resume to the Side") { page.resume(session, beside: true) }
            }
    }

    /// The first page of each agent, else the next; each agent's rows show as they come.
    private func read(_ agents: [String]) async {
        // Marked as reading before the await: a second read meanwhile would read the same offset.
        let generation = generation
        let pages = agents.filter { !reading.contains($0) }.map { ($0, list.agents[$0]?.looked ?? 0) }
        reading.formUnion(pages.map(\.0))
        let exec = await page.store.machine.exec()
        await withTaskGroup(of: (String, ClosedPage?).self) { group in
            for (agent, offset) in pages {
                group.addTask {
                    await (agent, try? exec.closedSessions(agent: agent, offset: offset, home: Self.home))
                }
            }
            for await (agent, page) in group where generation == self.generation {
                reading.remove(agent)
                if let page {
                    list.add(page, for: agent)
                } else {
                    failed.insert(agent)
                }
            }
        }
    }
}

extension Page {
    /// ⌥: beside the keyboard card.
    func resume(_ session: ClosedSession) {
        resume(session, beside: NSEvent.modifierFlags.contains(.option))
    }

    /// A folder as line 2 shows it: the home folder as `~`.
    func short(_ folder: String) -> String {
        PathField.short(folder, remote: store.machine.isRemote)
    }

    /// The agents' sessions the panes of every open session of the machine run.
    var liveSessions: Set<String> {
        Set(HostStore.all.filter { $0.machine.id == store.machine.id }.flatMap(\.agentPanes).compactMap(\.session))
    }
}

extension Chooser {
    static func name(_ command: String) -> String {
        agents.first { $0.command == command }?.name ?? command
    }
}
