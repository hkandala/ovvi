import HerdrKit
import SwiftUI

/// The sidebar's Archived Sessions (ui/window#archived-sessions): the agents' sessions on the window's machine that no
/// pane runs, from the agents' own stores. Read each time it opens, whole before it shows: the machine's last list at
/// once, else a loader. The agents' next pages read as the list's end scrolls into view.
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
    @State private var loading = false
    /// Each read anew (an open, Retry); an older one's pages land nowhere.
    @State private var generation = 0
    @State private var attempt = 0
    @State private var search = ""
    @State private var focusSearch = 0
    /// Each machine's last list, shown as it opens again while it reads anew.
    private static var lists: [String: ClosedList] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// UI tests' stores (`-archivedHome`), never the user's; the agents' session titles too.
    static let home = UserDefaults.standard.string(forKey: "archivedHome")

    var body: some View {
        // The machine's, not the session's: every page shows the same.
        let key = "\(page.store.machine.id) archived-sessions"
        let open = opened.hasLine(key)
        let shown = agent.isEmpty ? Chooser.agents.map(\.command) : [agent]
        let rows = open ? rows(shown) : []
        let next = list.next(of: shown).filter { !failed.contains($0) }
        VStack(spacing: 4) {
            header(open: open, key: key)
            if open {
                FilterField(prompt: "Search", text: $search, identifier: "agents.archived.search",
                            symbol: "magnifyingglass", focus: focusSearch, trailing: 22)
                    .onExitCommand { search = "" }
                    .overlay(alignment: .trailing) { menu.padding(.trailing, 8) }
                    .padding(.horizontal, 4)
                // Lazy, for the pages; as tall as its rows, up to five.
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(loading ? [] : rows) { row($0) }
                        if !next.isEmpty, !loading {
                            // The list's end: anew after each page, so it reads on while it stays in view (a short
                            // searched list, a page with nothing to show).
                            Color.clear.frame(height: 1).id(list.agents.values.map(\.looked).reduce(0, +))
                                .onAppear { Task { await readNext(next) } }
                        }
                        if loading {
                            Loader(text: "Reading sessions…", delay: .milliseconds(300)).padding(12)
                                .frame(maxWidth: .infinity)
                        } else if rows.isEmpty || !failed.isDisjoint(with: shown) || problem(shown) != nil {
                            status(shown, more: !next.isEmpty).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 5 * 48 + 4 * 4) // five 48 pt rows, 4 pt apart
                .fixedSize(horizontal: false, vertical: true)
                .fadesScrolledEdges()
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
            let machine = page.store.machine.id
            (reading, failed, generation) = ([], [], generation + 1)
            guard open else { return }
            list = Self.lists[machine] ?? ClosedList()
            loading = Self.lists[machine] == nil
            let generation = generation
            let (fresh, missing) = await read(Chooser.agents.map(\.command), from: ClosedList())
            guard generation == self.generation else { return }
            (list, failed, loading) = (fresh, missing, false)
            Self.lists[machine] = fresh
        }
    }

    private func header(open: Bool, key: String) -> some View {
        Button {
            withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) {
                opened = opened.togglingLine(key)
            }
            search = ""
            // Once the field is there.
            if opened.hasLine(key) {
                Task { focusSearch += 1 }
            }
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
            EmptyState(
                symbol: "exclamationmark.triangle",
                title: "Could not read \(machine)'s sessions.",
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

    /// The next page of each of `agents`, added to `base` all at once; the agents whose page did not come.
    private func read(_ agents: [String], from base: ClosedList) async -> (ClosedList, Set<String>) {
        let exec = await page.store.machine.exec()
        var list = base, missing: Set<String> = []
        await withTaskGroup(of: (String, ClosedPage?).self) { group in
            for agent in agents {
                let offset = base.agents[agent]?.looked ?? 0
                group.addTask {
                    await (agent, try? exec.closedSessions(agent: agent, offset: offset, home: Self.home))
                }
            }
            for await (agent, page) in group {
                if let page {
                    list.add(page, for: agent)
                } else {
                    missing.insert(agent)
                }
            }
        }
        return (list, missing)
    }

    /// The pages after the list's end, for the agents that have more.
    private func readNext(_ agents: [String]) async {
        // Marked as reading before the await: a second read meanwhile would read the same offset.
        let agents = agents.filter { !reading.contains($0) }, generation = generation
        reading.formUnion(agents)
        let (next, missing) = await read(agents, from: list)
        guard generation == self.generation else { return }
        reading.subtract(agents)
        (list, failed) = (next, failed.union(missing))
        Self.lists[page.store.machine.id] = list
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
