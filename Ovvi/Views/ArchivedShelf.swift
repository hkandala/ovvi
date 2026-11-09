import HerdrKit
import SwiftUI

/// The sidebar's Archived Sessions (ui/window#archived-sessions): the agents' sessions on the window's machine that no
/// pane runs, from the agents' own stores. Read each time it opens: the machine's last list at once, else a loader,
/// until every agent's first page came or 2 s after the first did. The next pages read as the list's end scrolls in.
struct ArchivedShelf: View {
    let pages: WindowPages
    /// The page in view when drawn: its machine's sessions. A resume goes to the page in view when it runs.
    let page: Page
    /// The agent the menu shows, "" for all.
    @AppStorage("archivedAgent", store: .agents) private var agent = ""
    @AppStorage(Page.openShelves, store: .agents) private var opened = ""
    @State private var list = ClosedList()
    @State private var reading: Set<String> = []
    @State private var failed: Set<String> = []
    /// No list yet: the loader shows.
    @State private var loading = true
    /// Each read anew (an open, Retry); an older one's pages land nowhere.
    @State private var generation = 0
    @State private var attempt = 0
    @State private var search = ""
    @State private var focusSearch = 0
    /// The user opened it: its search field takes the keyboard as it appears.
    @State private var opening = false
    /// Each machine's last list, shown as it opens again while it reads anew.
    private static var lists: [String: ClosedList] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// UI tests' stores (`-archivedHome`), never the user's; the agents' session titles too.
    static let home = UserDefaults.standard.string(forKey: "archivedHome")

    var body: some View {
        let key = page.archivedKey
        let open = opened.hasLine(key)
        let shown = agent.isEmpty ? Chooser.agents.map(\.command) : [agent]
        let rows = open ? rows(shown) : []
        let next = list.next(of: shown).filter { !failed.contains($0) }
        VStack(spacing: 4) {
            header(open: open, key: key)
            if open {
                FilterField(prompt: "Search", text: $search, identifier: "agents.archived.search",
                            symbol: "magnifyingglass", focus: focusSearch, trailing: 22)
                    .onAppear {
                        if opening {
                            opening = false
                            focusSearch += 1
                        }
                    }
                    .onExitCommand { search = "" }
                    .overlay(alignment: .trailing) { menu.padding(.trailing, 8) }
                    .padding(.horizontal, 4)
                Group {
                    if loading {
                        Loader(text: "Reading sessions…", delay: .milliseconds(300)).padding(12)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Lazy, for the pages; as tall as its rows, up to five.
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(rows) { row($0) }
                                if !next.isEmpty {
                                    // The list's end: anew after each page, so it reads on while it stays in view
                                    // (a short searched list, a page with nothing to show).
                                    Color.clear.frame(height: 1).id(list.agents.values.map(\.looked).reduce(0, +))
                                        .onAppear { Task { await readNext(next) } }
                                }
                                if rows.isEmpty || !failed.isDisjoint(with: shown) || !reading.isDisjoint(with: shown)
                                    || problem(shown) != nil
                                {
                                    status(shown, more: !next.isEmpty).frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .scrollIndicators(.never)
                        .frame(maxHeight: 5 * 48 + 4 * 4) // five 48 pt rows, 4 pt apart
                        .fixedSize(horizontal: false, vertical: true)
                        .fadesScrolledEdges()
                    }
                }
                .padding(.bottom, 4)
            }
        }
        // Open, as a space row that is not selected: a border, no glass.
        .background {
            if open {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.14))
            }
        }
        .task(id: [open ? 1 : 0, attempt]) {
            // Also while folded, for the next open's first frame.
            let machine = page.store.machine.id
            (list, loading) = (Self.lists[machine] ?? ClosedList(), Self.lists[machine] == nil)
            (reading, failed, generation) = ([], [], generation + 1)
            guard open else { return }
            await readFirst()
        }
    }

    private func header(open: Bool, key: String) -> some View {
        Button {
            withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) {
                opened = opened.togglingLine(key)
            }
            search = ""
            opening = opened.hasLine(key)
        } label: {
            HStack(spacing: 6) {
                Text(Self.label)
                Spacer(minLength: 0)
                // Where a space row's chevron is.
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12)
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .padding(.leading, WorkspaceRow.textInset).padding(.trailing, 8)
            .frame(height: 30)
            .contentShape(.rect)
        }
        .buttonStyle(ChromeStyle(radius: 10))
        .accessibilityLabel(Self.label)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(open ? "expanded" : "collapsed")
        .accessibilityIdentifier("agents.shelf.\(Self.label)")
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
            Image(systemName: agent.isEmpty ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.secondary)
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

    private func rows(_ shown: [String]) -> [ClosedSession] {
        let live = page.liveSessions
        return list.sessions(of: shown).filter { session in
            !live.contains(session.value) && (session.title.matches(search) || session.folder.matches(search))
        }
    }

    private func problem(_ shown: [String]) -> String? {
        shown.lazy.compactMap { agent in
            list.agents[agent]?.problem.map { "\(Chooser.name(agent)) \($0) on \(page.store.machine.name)." }
        }.first
    }

    @ViewBuilder private func status(_ shown: [String], more: Bool) -> some View {
        let machine = page.store.machine.name
        if !failed.isDisjoint(with: shown) {
            let names = shown.filter(failed.contains).map(Chooser.name).formatted(.list(type: .and))
            EmptyState(
                symbol: "exclamationmark.triangle",
                title: failed.isSuperset(of: shown) ? "Could not read \(machine)'s sessions."
                    : "Could not read \(names) sessions on \(machine).",
                compact: true,
            ) {
                Button("Retry") { attempt += 1 }
            }
        } else if let problem = problem(shown) {
            EmptyState(symbol: "exclamationmark.triangle", title: problem, compact: true)
        } else if more || !reading.isDisjoint(with: shown) {
            Loader(text: "Reading sessions…", delay: .milliseconds(300)).padding(12)
        } else if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "No matching sessions.", compact: true)
        } else {
            EmptyState(symbol: "archivebox", title: agent.isEmpty ? "No closed sessions on \(machine)."
                : "No \(Chooser.name(agent)) sessions.", compact: true)
        }
    }

    /// The page in view as an action runs: the shelf stays while the pages change.
    private var inView: Page {
        pages.current ?? page
    }

    private func row(_ session: ClosedSession) -> some View {
        // pi's session is a file path: its name is enough.
        let id = "agents.archived.\(session.agent).\((session.value as NSString).lastPathComponent)"
        return ArchivedRow(icon: session.agent, title: session.title,
                           line2: PathField.short(session.folder, remote: page.store.machine.isRemote),
                           date: session.date, id: id) { inView.resume(session) }
            .contextMenu {
                Button("Resume") { inView.resume(session, beside: false) }
                Button("Resume to the Side") { inView.resume(session, beside: true) }
            }
    }
}

private extension ArchivedShelf {
    /// Every agent's first page, shown together once all came, or 2 s after the first one did: a slow agent is read
    /// on (`reading`) and comes in when it does, a failed one is marked (`failed`).
    func readFirst() async {
        var generation = generation
        let agents = Chooser.agents.map(\.command), exec = await page.store.machine.exec()
        var staged = ClosedList(), missing: Set<String> = [], waiting = Set(agents), shown = false
        await withTaskGroup(of: (String, ClosedPage?).self) { group in
            for agent in agents {
                group.addTask {
                    await (agent, try? exec.closedSessions(agent: agent, offset: 0, home: Self.home))
                }
            }
            for await (agent, page) in group where generation == self.generation {
                if !agent.isEmpty {
                    waiting.remove(agent)
                    if shown {
                        reading.remove(agent)
                        if let page {
                            list.add(page, for: agent)
                        } else {
                            failed.insert(agent)
                        }
                    } else if let page {
                        staged.add(page, for: agent)
                    } else {
                        missing.insert(agent)
                    }
                    if waiting.isEmpty {
                        group.cancelAll()
                    } else if waiting.count == agents.count - 1 {
                        group.addTask {
                            try? await Task.sleep(for: .seconds(2))
                            return ("", nil)
                        }
                    }
                }
                if !shown, agent.isEmpty || waiting.isEmpty {
                    // A next page read meanwhile from the last list lands nowhere.
                    (shown, self.generation) = (true, self.generation + 1)
                    generation = self.generation
                    (list, failed, reading, loading) = (staged, missing, waiting, false)
                }
                if shown {
                    keep()
                }
            }
        }
    }

    /// The pages after the list's end, for the agents that have more, added all at once.
    func readNext(_ agents: [String]) async {
        // Marked as reading before the await: a second read meanwhile would read the same offset.
        let agents = agents.filter { !reading.contains($0) }, generation = generation, base = list
        reading.formUnion(agents)
        let exec = await page.store.machine.exec()
        let pages = await withTaskGroup(of: (String, ClosedPage?).self) { group in
            for agent in agents {
                let offset = base.agents[agent]?.looked ?? 0
                group.addTask {
                    await (agent, try? exec.closedSessions(agent: agent, offset: offset, home: Self.home))
                }
            }
            var pages: [(String, ClosedPage?)] = []
            for await page in group {
                pages.append(page)
            }
            return pages
        }
        guard generation == self.generation else { return }
        for (agent, page) in pages {
            if let page {
                list.add(page, for: agent)
            } else {
                failed.insert(agent)
            }
        }
        reading.subtract(agents)
        keep()
    }

    /// A list that read whole is the machine's next first frame.
    func keep() {
        if reading.isEmpty, failed.isEmpty {
            Self.lists[page.store.machine.id] = list
        }
    }
}

extension Page {
    /// ⌥: beside the keyboard card.
    func resume(_ session: ClosedSession) {
        resume(session, beside: NSEvent.modifierFlags.contains(.option))
    }

    /// The agents' sessions the panes of every open session of the machine run, or resume.
    var liveSessions: Set<String> {
        let stores = HostStore.all.filter { $0.machine.id == store.machine.id }
        return Set(stores.flatMap(\.agentPanes).compactMap(\.session)).union(stores.flatMap(\.resuming))
    }
}

extension Chooser {
    static func name(_ command: String) -> String {
        agents.first { $0.command == command }?.name ?? command
    }
}
