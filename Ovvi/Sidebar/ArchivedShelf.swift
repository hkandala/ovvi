import HerdrKit
import SwiftUI

/// The agents section's other view: the closed sessions on the window's machine, with their search.
struct ArchivedShelf: View {
    let pages: WindowPages
    let page: Page
    /// Shown by the user: the keys go to its search.
    let focuses: Bool
    let back: () -> Void
    @AppStorage("archivedAgent", store: .sidebar) private var agent = ""
    @State private var list = ClosedList()
    @State private var reading: Set<String> = []
    @State private var failed: Set<String> = []
    @State private var loading = true
    @State private var generation = 0
    @State private var attempt = 0
    @State private var search = ""
    @State private var focusSearch = 0
    private static var lists: [String: ClosedList] = [:]

    var body: some View {
        let shown = agent.isEmpty ? Chooser.agents.map(\.command) : [agent]
        let rows = rows(shown)
        let next = list.next(of: shown).filter { !failed.contains($0) }
        let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(spacing: 4) {
            FilterField(prompt: "Search", text: $search, identifier: "agents.archived.search",
                        symbol: "magnifyingglass", focus: focusSearch, leading: -3.5, trailing: 22)
                .onAppear {
                    if focuses {
                        focusSearch += 1
                    }
                }
                .onExitCommand(perform: back)
                // The magnifier's and the menu's ink on the section's columns.
                .overlay(alignment: .trailing) { menu.padding(.trailing, 5) }
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
                    }
                    .scrollIndicators(.never)
                    .fadesScrolledEdges()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
        }
        .task(id: searching ? "\(agent) \(search)" : "") {
            guard searching else { return }
            try? await Task.sleep(for: .milliseconds(300))
            await searchOlder(shown)
        }
        .task(id: attempt) {
            let machine = page.store.machine.id
            (list, loading) = (Self.lists[machine] ?? ClosedList(), Self.lists[machine] == nil)
            (reading, failed, generation) = ([], [], generation + 1)
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
        .tip("Show Agent")
        .accessibilityLabel("Show Agent")
        .accessibilityValue(agent.isEmpty ? "All Agents" : Chooser.name(agent))
        .accessibilityIdentifier("agents.archived.filter")
    }

    private func rows(_ shown: [String]) -> [ClosedSession] {
        let live = page.liveSessions
        return list.sessions(of: shown).filter { session in
            !live.contains(session.value) && (session.title.matches(search) || session.folder.matches(search))
        }
    }

    private func problem(_ shown: [String]) -> String? {
        shown.lazy.compactMap { agent in
            list.agents[agent]?.problem.map { "\(Chooser.name(agent)) \($0) on \(page.store.machine.name)" }
        }.first
    }

    @ViewBuilder private func status(_ shown: [String], next: [String], rows: Bool) -> some View {
        let machine = page.store.machine.name
        if !failed.isDisjoint(with: shown) {
            let names = shown.filter(failed.contains).map(Chooser.name).formatted(.list(type: .and))
            EmptyState(
                symbol: "exclamationmark.triangle",
                title: failed.isSuperset(of: shown) ? "Could not read \(machine)'s sessions"
                    : "Could not read \(names) sessions on \(machine)",
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
                EmptyState(symbol: "magnifyingglass", title: next.isEmpty ? "No sessions found"
                    : "No matches in the last \(list.sessions(of: shown).count) sessions", compact: true)
            }
        } else if !next.isEmpty || !reading.isDisjoint(with: shown) {
            Loader(text: "Reading sessions…", delay: .milliseconds(300)).padding(12)
        } else {
            EmptyState(symbol: "archivebox", title: agent.isEmpty ? "No closed sessions on \(machine)"
                : "No \(Chooser.name(agent)) sessions", compact: true)
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
