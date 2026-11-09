import HerdrKit
import SwiftUI

/// The sidebar's Archived Sessions (ui/window#archived-sessions), at its foot under every page: the sessions of Claude
/// Code, Codex, Pi and OpenCode on the window's machine that no pane runs, from the agents' own stores, newest first,
/// in a border as a space row's. Folded at first; open, a search field (with a menu that shows one agent) over at most
/// five rows that scroll. Read each time it opens; the next page of an agent as the list's end scrolls into view.
struct ArchivedShelf: View {
    let pages: WindowPages
    /// The page in view when drawn: its machine's sessions. A resume goes to the page in view when it runs.
    let page: Page
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
    /// The search field's text: by title and folder.
    @State private var search = ""
    @State private var under = (top: false, bottom: false)
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
                            symbol: "magnifyingglass", trailing: 22)
                    .onExitCommand { search = "" }
                    .overlay(alignment: .trailing) { menu.padding(.trailing, 8) }
                    .padding(.horizontal, 4)
                // Lazy, for the pages; as tall as its rows, up to five.
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(rows) { row($0) }
                        if !next.isEmpty {
                            // The list's end: anew after each page, so it reads on while it stays in view (a short
                            // searched list, a page with nothing to show).
                            Color.clear.frame(height: 1).id(list.agents.values.map(\.looked).reduce(0, +))
                                .onAppear { Task { await read(next) } }
                        }
                        if rows.isEmpty || !failed.isDisjoint(with: shown) || problem(shown) != nil {
                            status(shown, more: !next.isEmpty).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 5 * 48 + 4 * 4) // five 48 pt rows, 4 pt apart
                .fixedSize(horizontal: false, vertical: true)
                .onScrollGeometryChange(for: [Bool].self) { geometry in
                    [geometry.contentOffset.y > 0.5,
                     geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 0.5]
                } action: {
                    under = ($1[0], $1[1])
                }
                .fadeEdges(.vertical, start: under.top ? 18 : 0, end: under.bottom ? 18 : 0)
                .padding(.bottom, 4)
            }
        }
        // As a space row that is not selected: a border, no glass.
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.14)))
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

    /// "Archived Sessions" and the chevron: a click folds or opens it.
    private func header(open: Bool, key: String) -> some View {
        Button {
            withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) {
                opened = opened.togglingLine(key)
            }
            search = ""
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
            // Filled while it shows one agent.
            Image(systemName: agent.isEmpty ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
                // As the field's own symbol at its other end.
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

    /// The sessions shown: none a live pane runs, none resuming (on any page of the machine).
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
        } else if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "No matching sessions.", compact: true,
                       id: "agents.archived.status")
        } else {
            EmptyState(symbol: "archivebox", title: agent.isEmpty ? "No closed sessions on \(machine)."
                : "No \(Chooser.name(agent)) sessions.", compact: true, id: "agents.archived.status")
        }
    }

    /// A click resumes it in a new tab of the workspace for its folder; ⌥-click beside the keyboard card.
    /// The page in view as an action runs: the shelf stays while the pages change.
    private var inView: Page {
        pages.current ?? page
    }

    private func row(_ session: ClosedSession) -> some View {
        // pi's file by its name.
        let id = "agents.archived.\(session.agent).\((session.value as NSString).lastPathComponent)"
        return AgentRow(icon: session.agent, title: session.title, line2: page.short(session.folder), id: id,
                        action: { inView.resume(session) },
                        hover: {
                            IconButton(symbol: "arrow.uturn.backward", help: "Resume", size: 18) {
                                inView.resume(session)
                            }
                            .accessibilityIdentifier(id + ".resume")
                        },
                        trailing: { AgeText(date: session.date) })
            .contextMenu {
                Button("Resume") { inView.resume(session, beside: false) }
                Button("Resume to the Side") { inView.resume(session, beside: true) }
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
