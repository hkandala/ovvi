import HerdrKit
import SwiftUI

struct ArchivedShelf: View {
    let pages: WindowPages
    let page: Page
    @AppStorage("archivedAgent", store: .sidebar) private var agent = ""
    @AppStorage(Page.foldsAndShelves, store: .sidebar) private var opened = ""
    @State private var list = ClosedList()
    @State private var reading: Set<String> = []
    @State private var failed: Set<String> = []
    @State private var loading = true
    @State private var generation = 0
    @State private var attempt = 0
    @State private var search = ""
    @State private var focusSearch = 0
    @State private var opening = false
    private static var lists: [String: ClosedList] = [:]

    var body: some View {
        let key = page.archivedKey
        let open = opened.hasLine(key)
        let shown = agent.isEmpty ? Chooser.agents.map(\.command) : [agent]
        let rows = open ? rows(shown) : []
        let next = list.next(of: shown).filter { !failed.contains($0) }
        let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty
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
                    .onExitCommand {
                        toggle(key)
                        inView.focusKeyboardCard()
                    }
                    .overlay(alignment: .trailing) { menu.padding(.trailing, 8) }
                    .padding(.horizontal, 4)
                Group {
                    if loading {
                        Loader(text: "Reading sessions…", delay: .milliseconds(300))
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(rows) { row($0) }
                                if rows.isEmpty {
                                    status(shown, next: next, rows: false).frame(maxWidth: .infinity)
                                        .frame(height: Self.height)
                                        .overlay(alignment: .bottom) { end(next, searching: searching) }
                                } else {
                                    end(next, searching: searching)
                                    if !failed.isDisjoint(with: shown) || !reading.isDisjoint(with: shown)
                                        || problem(shown) != nil || searching && !next.isEmpty && !bounded(shown)
                                    {
                                        status(shown, next: next, rows: true).frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .scrollIndicators(.never)
                        .fadesScrolledEdges()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .padding(.bottom, 4)
            }
        }
        .background {
            if open {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.14))
            }
        }
        .onChange(of: open) {
            if !open {
                search = ""
            }
        }
        .task(id: open && searching ? "\(agent) \(search)" : "") {
            guard open, searching else { return }
            try? await Task.sleep(for: .milliseconds(300))
            await searchOlder(shown)
        }
        .task(id: [open ? 1 : 0, attempt]) {
            let machine = page.store.machine.id
            (list, loading) = (Self.lists[machine] ?? ClosedList(), Self.lists[machine] == nil)
            (reading, failed, generation) = ([], [], generation + 1)
            guard open else { return }
            await readFirst()
        }
    }

    static let height: CGFloat = 5 * 48 + 4 * 4

    @ViewBuilder private func end(_ next: [String], searching: Bool) -> some View {
        if !next.isEmpty, !searching {
            Color.clear.frame(height: 1).id(list.agents.values.map(\.looked).reduce(0, +))
                .onAppear { Task { await readNext(next) } }
        }
    }

    private func toggle(_ key: String) {
        withAnimation(Animation.reduced ? nil : .easeOut(duration: 0.2)) {
            opened = opened.togglingLine(key)
        }
        opening = opened.hasLine(key)
    }

    private func header(open: Bool, key: String) -> some View {
        Button {
            toggle(key)
        } label: {
            HStack(spacing: 6) {
                Text(Self.label)
                Spacer(minLength: 0)
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

    @ViewBuilder private func status(_ shown: [String], next: [String], rows: Bool) -> some View {
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
        } else if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            if !reading.isDisjoint(with: shown) || !next.isEmpty && !bounded(shown) {
                Loader(text: "Searching older sessions…", delay: .milliseconds(300)).padding(12)
            } else if !rows {
                EmptyState(symbol: "magnifyingglass", title: next.isEmpty ? "No sessions found."
                    : "No matches in the last \(list.sessions(of: shown).count) sessions.", compact: true)
            }
        } else if !next.isEmpty || !reading.isDisjoint(with: shown) {
            Loader(text: "Reading sessions…", delay: .milliseconds(300)).padding(12)
        } else {
            EmptyState(symbol: "archivebox", title: agent.isEmpty ? "No closed sessions on \(machine)."
                : "No \(Chooser.name(agent)) sessions.", compact: true)
        }
    }

    private var inView: Page {
        pages.current ?? page
    }

    private func row(_ session: ClosedSession) -> some View {
        // pi's session is a file path.
        let id = "agents.archived.\(session.agent).\((session.value as NSString).lastPathComponent)"
        return ArchivedRow(icon: session.agent, title: session.title,
                           line2: MachinePath.short(session.folder, remote: page.store.machine.isRemote),
                           date: session.date, id: id) { inView.resume(session) }
            .contextMenu {
                Button("Resume") { inView.resume(session, beside: false) }
                Button("Resume to the Side") { inView.resume(session, beside: true) }
            }
    }
}

private extension ArchivedShelf {
    /// ponytail: polls every 0.2 s while another read runs; a read's own end could signal it if this ever shows.
    func searchOlder(_ shown: [String]) async {
        while !Task.isCancelled, !bounded(shown) {
            let next = list.next(of: shown).filter { !failed.contains($0) }
            if loading || !reading.isDisjoint(with: shown) {
                try? await Task.sleep(for: .milliseconds(200))
            } else if next.isEmpty {
                return
            } else {
                // Its own task: a new query's cancel would cut the read short, and mark the agents failed.
                await Task { await readNext(next) }.value
            }
        }
    }

    func bounded(_ shown: [String]) -> Bool {
        list.sessions(of: shown).count >= 1000
    }

    func readFirst() async {
        var generation = generation
        let agents = Chooser.agents.map(\.command), exec = await page.store.machine.exec()
        var staged = ClosedList(), missing: Set<String> = [], waiting = Set(agents), shown = false
        await withTaskGroup(of: (String, ClosedPage?).self) { group in
            for agent in agents {
                group.addTask {
                    await (agent, try? exec.closedSessions(agent: agent, offset: 0, home: HostStore.archivedHome))
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
                    // A next page read meanwhile from the last list must land nowhere.
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

    func readNext(_ agents: [String]) async {
        // Marked as reading ahead of the await: a second read meanwhile would read the same offset.
        let agents = agents.filter { !reading.contains($0) }, generation = generation, base = list
        reading.formUnion(agents)
        let exec = await page.store.machine.exec()
        let pages = await withTaskGroup(of: (String, ClosedPage?).self) { group in
            for agent in agents {
                let offset = base.agents[agent]?.looked ?? 0
                group.addTask {
                    await (agent, try? exec.closedSessions(agent: agent, offset: offset, home: HostStore.archivedHome))
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

    func keep() {
        if reading.isEmpty, failed.isEmpty {
            Self.lists[page.store.machine.id] = list
        }
    }
}
